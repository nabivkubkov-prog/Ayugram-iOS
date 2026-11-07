import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
MAKE = ROOT / "build-system" / "Make"
sys.path.insert(0, str(MAKE))
import BuildEnvironment
import BazelLocation
sys.path.pop(0)


class BazelLocationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.binary = b"verified Intel Bazel fixture"
        self.digest = hashlib.sha256(self.binary).hexdigest()
        self.config = {
            "app": "12.0", "xcode": "16.2", "macos": "15",
            "bazel": "8.3.1:" + "a" * 64,
            "bazel_sha256": {"darwin-arm64": "a" * 64, "darwin-x86_64": self.digest},
        }
        self.write_config()
        self.cache = self.root / "cache"
        self.cache_entry = self.cache / "cas" / self.digest[:2] / self.digest
        self.bazel_path = self.root / "build-input" / "bazel-8.3.1-darwin-x86_64"
        for module in (BuildEnvironment, BazelLocation):
            patcher = patch.object(module, "is_apple_silicon", return_value=False)
            patcher.start()
            self.addCleanup(patcher.stop)

    def write_config(self):
        (self.root / "versions.json").write_text(json.dumps(self.config), encoding="utf-8")

    def locate(self):
        return BazelLocation.locate_bazel(str(self.root), None, str(self.cache))

    def download(self, arguments):
        Path(arguments[arguments.index("--output") + 1]).write_bytes(self.binary)

    def test_intel_and_apple_silicon_use_their_own_digest(self):
        self.assertEqual(BuildEnvironment.BuildEnvironmentVersions(str(self.root)).bazel_version_sha256, self.digest)
        with patch.object(BuildEnvironment, "is_apple_silicon", return_value=True):
            self.assertEqual(BuildEnvironment.BuildEnvironmentVersions(str(self.root)).bazel_version_sha256, "a" * 64)

    def test_legacy_pin_still_works_without_an_architecture_map(self):
        del self.config["bazel_sha256"]
        self.write_config()
        self.assertEqual(BuildEnvironment.BuildEnvironmentVersions(str(self.root)).bazel_version_sha256, "a" * 64)

    def test_missing_host_digest_does_not_use_another_architecture(self):
        del self.config["bazel_sha256"]["darwin-x86_64"]
        self.write_config()
        with self.assertRaisesRegex(ValueError, "Missing Bazel SHA256 for darwin-x86_64"):
            BuildEnvironment.BuildEnvironmentVersions(str(self.root))

    def test_download_is_verified_before_it_enters_the_cache(self):
        with patch.object(BazelLocation, "call_executable", side_effect=self.download) as download:
            self.assertEqual(Path(self.locate()), self.bazel_path)
        self.assertEqual(self.bazel_path.read_bytes(), self.binary)
        self.assertEqual(self.cache_entry.read_bytes(), self.binary)
        self.assertIn("--fail", download.call_args.args[0])

    def test_wrong_download_is_rejected_without_copying_a_deleted_file(self):
        def wrong_download(arguments):
            Path(arguments[arguments.index("--output") + 1]).write_bytes(b"wrong architecture or damaged download")
        with patch.object(BazelLocation, "call_executable", side_effect=wrong_download):
            with self.assertRaisesRegex(RuntimeError, "Bazel checksum mismatch"):
                self.locate()
        self.assertFalse(self.bazel_path.exists())
        self.assertFalse(self.cache_entry.exists())

    def test_verified_cache_avoids_network_access(self):
        self.cache_entry.parent.mkdir(parents=True)
        self.cache_entry.write_bytes(self.binary)
        with patch.object(BazelLocation, "call_executable") as download:
            self.locate()
            download.assert_not_called()
        self.assertEqual(self.bazel_path.read_bytes(), self.binary)

    def test_corrupt_cache_is_replaced_with_a_verified_download(self):
        self.cache_entry.parent.mkdir(parents=True)
        self.cache_entry.write_bytes(b"corrupt cache")
        with patch.object(BazelLocation, "call_executable", side_effect=self.download):
            self.locate()
        self.assertEqual(self.cache_entry.read_bytes(), self.binary)


if __name__ == "__main__":
    unittest.main()
