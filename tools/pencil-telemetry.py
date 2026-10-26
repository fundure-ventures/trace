#!/usr/bin/env python3
"""Local Pencil state relay. Never forwards or saves raw iPad logs."""

import argparse
import asyncio
import json
import re
import socket
import os
import pty
import select
import subprocess
import signal
import time


def pencil_state(line):
    if "Unsupported pencil detached." in line:
        return False, True
    if "Pencil2 received HID charger notification: attached" in line:
        return True, True
    if "SpringBoard(BatteryCenter)" in line and "name = Apple Pencil;" in line:
        match = re.search(r"; charging = (YES|NO);", line)
        if match:
            return match[1] == "YES", False
    return None


LAYOUT_ELEMENT = re.compile(
    r"<SBSDisplayLayoutElement: [^;>]+; ([^;>]+);(?: bundleID: ([^;>]+);)?"
    r"[^>]*?level: (\d+);[^>]*?role: primary>"
)


def app_open(message):
    """Whether a non-system app tops the iPad's main display, from SpringBoard layout logs."""
    if "_updateLayout" not in message or "displayIdentity: Main" not in message:
        return None
    primaries = LAYOUT_ELEMENT.findall(message)
    if not primaries:
        return None
    _, top = max((int(level), bundle or element) for element, bundle, level in primaries)
    return not top.startswith("com.apple.springboard.") and "sidecar" not in top.lower()


def emit(event, **values):
    print(json.dumps({"event": event, **values}), flush=True)


def bonjour_query(arguments, seconds):
    master, slave = pty.openpty()
    process = subprocess.Popen(
        ["/usr/bin/dns-sd", *arguments], stdout=slave, stderr=slave
    )
    os.close(slave)
    output = b""
    try:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.2)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    if process.poll() is not None:
                        break
                    raise
                if not chunk:
                    break
                output += chunk
    finally:
        process.terminate()
        process.wait(timeout=3)
        os.close(master)
    if process.returncode not in (0, -15):
        raise RuntimeError("Local network discovery failed. Check Local Network permission.")
    return output.decode(errors="replace")


def bonjour_host(instance):
    output = bonjour_query(["-L", instance, "_apple-mobdev2._tcp", "local."], 2)
    match = re.search(r"can be reached at ([^\s:]+):\d+", output)
    return match[1] if match else None


async def discover():
    from pymobiledevice3.exceptions import PyMobileDevice3Exception
    from pymobiledevice3.lockdown import create_using_tcp

    output = await asyncio.to_thread(
        bonjour_query, ["-B", "_apple-mobdev2._tcp", "local."], 4
    )
    instances = set()
    for line in output.splitlines():
        fields = line.split(None, 6)
        if len(fields) == 7 and fields[1] == "Add":
            instances.add(fields[6])
    devices = []
    unavailable = 0
    hosts = set()
    for instance in sorted(instances):
        host = await asyncio.to_thread(bonjour_host, instance)
        if host is None or host in hosts:
            continue
        hosts.add(host)
        client = None
        try:
            addresses = await asyncio.get_running_loop().getaddrinfo(
                host, 62078, family=socket.AF_INET, type=socket.SOCK_STREAM
            )
            client = await asyncio.wait_for(
                create_using_tcp(addresses[0][4][0], autopair=False), 4
            )
            if client.all_values.get("DeviceClass") == "iPad":
                devices.append({"name": client.all_values["DeviceName"], "host": host})
        except (OSError, asyncio.TimeoutError, PyMobileDevice3Exception):
            unavailable += 1
        finally:
            if client is not None:
                await client.close()
    emit("devices", devices=devices, unavailable=unavailable)


async def prepare(name, host, enable=False):
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.usbmux import list_devices

    devices = [device for device in await list_devices() if device.is_usb]
    if not devices:
        if not enable:
            emit("waiting", message="Connect your iPad by USB and unlock it.")
            return False
        raise RuntimeError("Connect your iPad by USB, unlock it, and tap Trust if asked.")
    for device in devices:
        client = await asyncio.wait_for(
            create_using_usbmux(
                serial=device.serial, connection_type="USB", autopair=False
            ), 10
        )
        try:
            if client.all_values.get("DeviceClass") != "iPad":
                continue
            device_name = client.all_values["DeviceName"]
            if name and device_name != name:
                continue
            if not name and len(devices) != 1:
                raise RuntimeError("Leave only the iPad you want to configure connected by USB.")
            if not client.paired:
                emit("trustNeeded")
                return False
            if enable:
                domain = "com.apple.mobile.wireless_lockdown"
                await client.set_value(True, domain=domain, key="EnableWifiConnections")
                if await client.get_value(domain=domain, key="EnableWifiConnections") is not True:
                    raise RuntimeError("The iPad did not enable wireless connections. Try again.")
                if not host:
                    service = await client.get_value(domain=domain, key="BonjourFullServiceName")
                    instance = service.split("._apple-mobdev2._tcp")[0]
                    for _ in range(3):
                        host = await asyncio.to_thread(bonjour_host, instance)
                        if host:
                            break
                        await asyncio.sleep(1)
                    if not host:
                        raise RuntimeError(
                            "Wireless connections are enabled, but the iPad is not visible on Wi-Fi yet. "
                            "Keep both devices on the same Wi-Fi and try again."
                        )
            emit(
                "prepared" if enable else "trusted",
                udid=client.udid, name=device_name, host=host,
            )
            return True
        finally:
            await client.close()
    if not enable:
        emit("waiting", message="Connect the selected iPad by USB and unlock it.")
        return False
    raise RuntimeError("The selected iPad is not connected by USB. Connect it and try again.")


async def check_wireless(udid, host):
    from pymobiledevice3.usbmux import list_devices

    while any(device.is_usb and device.matches_udid(udid) for device in await list_devices()):
        emit("waiting", message="Unplug the USB cable. Keep the iPad awake on the same Wi-Fi.")
        await asyncio.sleep(2)
    emit("checkingWireless")
    await watch(udid, host, retry=False)


class PencilStateTracker:
    def __init__(self):
        self.previous = None

    def update(self, line):
        state = pencil_state(line)
        if state is None:
            return None
        charging, explicit = state
        if charging == self.previous:
            return None
        baseline = self.previous is None and not explicit
        self.previous = charging
        return {"charging": charging, "baseline": baseline}


async def watch_foreground(client, foreground):
    """Best effort: on failure the state stays unknown so pickups keep working."""
    from pymobiledevice3.exceptions import PyMobileDevice3Exception
    from pymobiledevice3.services.os_trace import OsTraceService

    try:
        async with OsTraceService(client) as service:
            processes = (await service.get_pid_list())["Payload"]
        pid = next(
            int(pid) for pid, info in processes.items()
            if info.get("ProcessName") == "SpringBoard"
        )
        async with OsTraceService(client) as service:
            async for entry in service.syslog(pid=pid):
                state = app_open(entry.message)
                if state is not None:
                    foreground["appOpen"] = state
    except (OSError, StopIteration, KeyError, ValueError, PyMobileDevice3Exception):
        pass
    foreground["appOpen"] = None


async def watch(udid, host, retry=True):
    from pymobiledevice3.exceptions import PyMobileDevice3Exception
    from pymobiledevice3.lockdown import create_using_tcp
    from pymobiledevice3.pair_records import get_usbmux_pairing_record
    from pymobiledevice3.services.syslog import SyslogService

    while True:
        client = None
        layout = None
        try:
            record = await get_usbmux_pairing_record(udid)
            if record is None:
                raise RuntimeError("iPad trust record missing. Connect USB and trust this Mac.")
            addresses = await asyncio.get_running_loop().getaddrinfo(
                host, 62078, family=socket.AF_INET, type=socket.SOCK_STREAM
            )
            client = await asyncio.wait_for(
                create_using_tcp(
                    addresses[0][4][0], identifier=udid,
                    pair_record=record, autopair=False,
                ),
                timeout=15,
            )
            if not client.paired or client.udid != udid:
                raise RuntimeError("The configured iPad did not accept its existing trust pairing.")
            foreground = {"appOpen": None}
            layout = asyncio.create_task(watch_foreground(client, foreground))
            async with SyslogService(client) as service:
                emit("ready", name=client.all_values["DeviceName"])
                tracker = PencilStateTracker()
                async for line in service.watch():
                    if isinstance(line, bytes):
                        line = line.decode(errors="replace")
                    state = tracker.update(line)
                    if state is not None:
                        emit("state", **state, appOpen=foreground["appOpen"])
        except (OSError, asyncio.TimeoutError, PyMobileDevice3Exception) as error:
            detail = str(error) or type(error).__name__
            if not retry:
                raise RuntimeError(
                    f"Wi-Fi check failed: {detail}. Keep the iPad awake on the same Wi-Fi "
                    "and allow Trace in System Settings > Privacy & Security > Local Network."
                ) from error
            emit("error", message=f"iPad unavailable: {detail}. Retrying in 10 seconds.")
        finally:
            if layout is not None:
                layout.cancel()
            if client is not None:
                await client.close()
        await asyncio.sleep(10)


async def run_command(args):
    task = asyncio.current_task()
    asyncio.get_running_loop().add_signal_handler(signal.SIGTERM, task.cancel)
    if args.discover:
        await discover()
    elif args.trust:
        while not await prepare(args.udid, args.host):
            await asyncio.sleep(2)
    elif args.enable:
        await prepare(args.udid, args.host, enable=True)
    elif args.verify:
        await check_wireless(args.udid, args.host)
    else:
        await watch(args.udid, args.host)


if __name__ == "__main__":
    from pymobiledevice3.exceptions import PyMobileDevice3Exception

    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--discover", action="store_true")
    modes.add_argument("--trust", action="store_true")
    modes.add_argument("--enable", action="store_true")
    modes.add_argument("--verify", action="store_true")
    parser.add_argument("udid", nargs="?", default="")
    parser.add_argument("host", nargs="?", default="")
    args = parser.parse_args()
    try:
        asyncio.run(run_command(args))
    except asyncio.CancelledError:
        pass
    except (RuntimeError, KeyError, OSError, PyMobileDevice3Exception) as error:
        emit("error", message=str(error))
        raise SystemExit(1)
