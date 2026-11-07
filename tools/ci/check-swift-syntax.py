#!/usr/bin/env python3
"""Parse every Swift file changed since the verified baseline before a full build."""
import argparse
import concurrent.futures
from pathlib import Path
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    changed = subprocess.run(
        ["git", "diff", "--name-only", "-z", "--diff-filter=ACMR", args.base, "--", "*.swift"],
        cwd=root, check=True, capture_output=True,
    )
    paths = [value.decode("utf-8") for value in changed.stdout.split(b"\0") if value]

    def parse(path: str) -> tuple[str, subprocess.CompletedProcess[str]]:
        # Parse files separately: test entry points share the filename main.swift.
        result = subprocess.run(
            ["xcrun", "swiftc", "-frontend", "-parse", "-warnings-as-errors", str(root / path)],
            cwd=root, capture_output=True, text=True,
        )
        return path, result

    failures = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for path, result in pool.map(parse, paths):
            if result.returncode:
                failures += 1
                print(f"Swift syntax failed: {path}", file=sys.stderr)
                print(result.stdout + result.stderr, file=sys.stderr)
    print(f"Parsed {len(paths)} changed Swift files; {failures} failed.")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
