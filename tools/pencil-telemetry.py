#!/usr/bin/env python3
"""Experimental local Pencil state relay. Never forwards or saves raw iPad logs."""

import argparse
import asyncio
import json
import re
import socket


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


def emit(event, **values):
    print(json.dumps({"event": event, **values}), flush=True)


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


async def watch(udid, host):
    from pymobiledevice3.exceptions import PyMobileDevice3Exception
    from pymobiledevice3.lockdown import create_using_tcp
    from pymobiledevice3.pair_records import get_usbmux_pairing_record
    from pymobiledevice3.services.syslog import SyslogService

    while True:
        client = None
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
            async with SyslogService(client) as service:
                emit("ready", name=client.all_values["DeviceName"])
                tracker = PencilStateTracker()
                async for line in service.watch():
                    if isinstance(line, bytes):
                        line = line.decode(errors="replace")
                    state = tracker.update(line)
                    if state is not None:
                        emit("state", **state)
        except (OSError, asyncio.TimeoutError, PyMobileDevice3Exception) as error:
            detail = str(error) or type(error).__name__
            emit("error", message=f"iPad unavailable: {detail}. Retrying in 10 seconds.")
        finally:
            if client is not None:
                await client.close()
        await asyncio.sleep(10)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("udid")
    parser.add_argument("host")
    args = parser.parse_args()
    try:
        asyncio.run(watch(args.udid, args.host))
    except (RuntimeError, KeyError) as error:
        emit("error", message=str(error))
        raise SystemExit(1)
