#!/usr/bin/env python3
"""Write a license inventory for the Pencil helper's locked dependencies."""

from importlib import metadata
from pathlib import Path
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name
import platform
import sys


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: write-pencil-runtime-notices VENV_DIR OUTPUT_FILE")

    venv = Path(sys.argv[1])
    site_packages = next(venv.glob("lib/python*/site-packages"), None)
    if site_packages is None:
        raise SystemExit(f"no site-packages directory found in {venv}")
    output = Path(sys.argv[2])
    distributions = {
        canonicalize_name(distribution.metadata["Name"]): distribution
        for distribution in metadata.distributions(path=[str(site_packages)])
        if distribution.metadata.get("Name")
    }
    pending = ["pymobiledevice3"]
    packages = {}
    while pending:
        package_name = canonicalize_name(pending.pop())
        if package_name in packages:
            continue
        distribution = distributions.get(package_name)
        if distribution is None:
            raise SystemExit(f"missing locked runtime dependency: {package_name}")
        name = distribution.metadata["Name"]
        version = distribution.version
        license_name = (
            distribution.metadata.get("License-Expression")
            or distribution.metadata.get("License")
            or "Not declared"
        )
        packages[package_name] = (name, version, license_name)

        for requirement_text in distribution.requires or []:
            requirement = Requirement(requirement_text)
            if requirement.marker and not requirement.marker.evaluate():
                continue
            pending.append(requirement.name)

    lines = [
        "Pencil telemetry dependency license inventory",
        "",
        "Generated from the locked pymobiledevice3 dependency graph and Python runtime.",
        "Some listed dependencies may not be included in the frozen helper.",
        "This inventory is not a legal determination or a complete source offer.",
        "Review all license and corresponding-source obligations before release.",
        "",
        f"- Python {platform.python_version()} (Python Software Foundation License 2.0)",
        f"- PyInstaller {distributions['pyinstaller'].version} (GPL with bootloader exception)",
    ]
    lines.extend(
        f"- {name} {version} ({license_name})"
        for name, version, license_name in sorted(packages.values(), key=lambda item: item[0].casefold())
    )
    output.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
