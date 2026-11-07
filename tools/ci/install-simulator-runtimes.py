#!/usr/bin/env python3
"""Install the simulator versions used by the verified Xcode 16.2 build."""
import argparse
import json
import subprocess
import sys


def installed(platform: str, version: str) -> bool:
    result = subprocess.run(
        ["xcrun", "simctl", "list", "runtimes", "--json"],
        check=True, capture_output=True, text=True, timeout=120,
    )
    prefix = f"com.apple.CoreSimulator.SimRuntime.{platform}-"
    return any(
        runtime.get("identifier", "").startswith(prefix)
        and runtime.get("version") == version
        and runtime.get("isAvailable") is True
        for runtime in json.loads(result.stdout).get("runtimes", [])
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", action="append", required=True, metavar="PLATFORM=VERSION")
    args = parser.parse_args()
    for specification in args.runtime:
        platform, separator, version = specification.partition("=")
        if not separator or platform not in {"iOS", "watchOS"} or not version:
            parser.error(f"Invalid simulator specification: {specification}")
        if installed(platform, version):
            print(f"{platform} {version} is already available; skipping its download.", flush=True)
            continue
        print(f"Installing pinned {platform} {version}; downloads can exceed 8 GB.", flush=True)
        try:
            subprocess.run(
                ["xcodebuild", "-downloadPlatform", platform, "-buildVersion", version],
                check=True, timeout=20 * 60,
            )
        except subprocess.TimeoutExpired:
            print(f"::error::{platform} {version} did not finish downloading/importing within 20 minutes.", file=sys.stderr)
            return 1
        if not installed(platform, version):
            print(f"::error::Xcode reported success but {platform} {version} is not available to CoreSimulator.", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
