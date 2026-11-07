#!/usr/bin/env python3
"""Validate an iPhone archive before making it available as a build artifact."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import struct
import zipfile


CPU_TYPE_ARM64 = 0x0100000C


def contains_arm64(header):
    if len(header) < 8:
        return False
    magic = header[:4]
    if magic in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe"):
        return struct.unpack_from("<I", header, 4)[0] == CPU_TYPE_ARM64
    if magic in (b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce"):
        return struct.unpack_from(">I", header, 4)[0] == CPU_TYPE_ARM64
    if magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        count = struct.unpack_from(">I", header, 4)[0]
        stride = 32 if magic == b"\xca\xfe\xba\xbf" else 20
        for index in range(min(count, (len(header) - 8) // stride)):
            if struct.unpack_from(">I", header, 8 + index * stride)[0] == CPU_TYPE_ARM64:
                return True
    return False


def validate_archive(ipa, expected_bundle_id, expected_version=None, expected_build=None):
    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("IPA contains duplicate ZIP entries")
        for name in names:
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts or "\\" in name:
                raise ValueError("IPA contains an unsafe path")
        corrupt = archive.testzip()
        if corrupt:
            raise ValueError("IPA contains a corrupt ZIP entry")

        app_plists = [name for name in names if name.startswith("Payload/")
                      and len(PurePosixPath(name).parts) == 3
                      and name.endswith(".app/Info.plist")]
        if len(app_plists) != 1:
            raise ValueError("IPA must contain exactly one top-level iOS app")
        app_plist = app_plists[0]
        app_root = app_plist.rsplit("/", 1)[0]
        info = plistlib.loads(archive.read(app_plist))
        if info.get("CFBundleIdentifier") != expected_bundle_id:
            raise ValueError("IPA bundle identifier differs from the requested configuration")
        if info.get("CFBundlePackageType") != "APPL":
            raise ValueError("IPA does not contain an application bundle")
        if expected_version is not None and str(info.get("CFBundleShortVersionString")) != str(expected_version):
            raise ValueError("IPA version differs from versions.json")
        if expected_build is not None and str(info.get("CFBundleVersion")) != str(expected_build):
            raise ValueError("IPA build number differs from the current build")

        def verify_executable(root, bundle):
            executable = bundle.get("CFBundleExecutable", "")
            if not executable or "/" in executable or "\\" in executable or executable in {".", ".."}:
                raise ValueError("Bundle has an invalid executable name")
            try:
                with archive.open(root + "/" + executable) as file:
                    header = file.read(4096)
            except KeyError as error:
                raise ValueError("Bundle executable is missing") from error
            if not contains_arm64(header):
                raise ValueError("Bundle executable does not contain iPhone ARM64 code")

        verify_executable(app_root, info)
        extension_count = 0
        for name in names:
            if name.startswith(app_root + "/PlugIns/") and name.endswith(".appex/Info.plist"):
                extension = plistlib.loads(archive.read(name))
                if not extension.get("CFBundleIdentifier", "").startswith(expected_bundle_id + "."):
                    raise ValueError("Extension bundle identifier does not belong to the application")
                verify_executable(name.rsplit("/", 1)[0], extension)
                extension_count += 1

        if extension_count == 0:
            raise ValueError("IPA is missing Telegram application extensions")

    digest = hashlib.sha256()
    with open(ipa, "rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return {
        "bundle_id": expected_bundle_id,
        "app_version": info["CFBundleShortVersionString"],
        "build_number": info["CFBundleVersion"],
        "architecture": "arm64",
        "extensions": extension_count,
        "size_bytes": Path(ipa).stat().st_size,
        "sha256": digest.hexdigest(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa")
    parser.add_argument("--configuration", required=True)
    parser.add_argument("--versions", default="versions.json")
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--signing", choices=("signed", "unsigned"), required=True)
    parser.add_argument("--report", required=True)
    arguments = parser.parse_args()
    try:
        configuration = json.loads(Path(arguments.configuration).read_text(encoding="utf-8"))
        versions = json.loads(Path(arguments.versions).read_text(encoding="utf-8"))
        report = validate_archive(arguments.ipa, configuration["bundle_id"], versions["app"], arguments.build_number)
        report.update({"commit": arguments.commit, "signing": arguments.signing, "xcode": versions["xcode"]})
        Path(arguments.report).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, indent=2))
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as error:
        parser.exit(1, "::error::" + str(error) + "\n")


if __name__ == "__main__":
    main()
