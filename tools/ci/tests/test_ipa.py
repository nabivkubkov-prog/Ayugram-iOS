import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("ipa", ROOT / "tools/ci/verify-ipa.py")
ipa = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ipa)
ARM64 = struct.pack("<IIIIIIII", 0xFEEDFACF, ipa.CPU_TYPE_ARM64, 0, 2, 0, 0, 0, 0)


class ArtifactValidationTests(unittest.TestCase):
    def archive(self, directory, bundle="com.example.ayugram", executable=ARM64, extension=True, extra=None):
        path = Path(directory) / "app.ipa"
        with zipfile.ZipFile(path, "w") as archive:
            info = {"CFBundleIdentifier": bundle, "CFBundleExecutable": "AyuGram", "CFBundlePackageType": "APPL",
                    "CFBundleShortVersionString": "12.0", "CFBundleVersion": "42"}
            archive.writestr("Payload/AyuGram.app/Info.plist", plistlib.dumps(info))
            archive.writestr("Payload/AyuGram.app/AyuGram", executable)
            if extension:
                info["CFBundleIdentifier"] = bundle + ".Share"
                info["CFBundleExecutable"] = "Share"
                archive.writestr("Payload/AyuGram.app/PlugIns/Share.appex/Info.plist", plistlib.dumps(info))
                archive.writestr("Payload/AyuGram.app/PlugIns/Share.appex/Share", ARM64)
            for name, contents in (extra or {}).items():
                archive.writestr(name, contents)
        return path

    def test_valid_archive_records_hash_version_and_extensions(self):
        with tempfile.TemporaryDirectory() as temporary:
            report = ipa.validate_archive(self.archive(temporary), "com.example.ayugram", "12.0", "42")
            self.assertEqual(report["extensions"], 1)
            self.assertEqual(len(report["sha256"]), 64)

    def test_wrong_bundle_or_stale_build_cannot_be_published(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = self.archive(temporary)
            for bundle, version, build in [("wrong.id", "12.0", "42"), ("com.example.ayugram", "11.0", "42"),
                                            ("com.example.ayugram", "12.0", "41")]:
                with self.subTest(bundle=bundle, version=version, build=build), self.assertRaises(ValueError):
                    ipa.validate_archive(path, bundle, version, build)

    def test_text_stub_is_not_an_iphone_binary(self):
        with tempfile.TemporaryDirectory() as temporary, self.assertRaisesRegex(ValueError, "ARM64"):
            ipa.validate_archive(self.archive(temporary, executable=b"fake executable"), "com.example.ayugram")

    def test_missing_extensions_fail_validation(self):
        with tempfile.TemporaryDirectory() as temporary, self.assertRaisesRegex(ValueError, "extensions"):
            ipa.validate_archive(self.archive(temporary, extension=False), "com.example.ayugram")

    def test_zip_path_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary, self.assertRaisesRegex(ValueError, "unsafe path"):
            ipa.validate_archive(self.archive(temporary, extra={"../outside": "invalid"}), "com.example.ayugram")


if __name__ == "__main__":
    unittest.main()
