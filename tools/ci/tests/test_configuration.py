import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("configuration", ROOT / "tools/ci/prepare-configuration.py")
configuration = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(configuration)


class BuildConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.template = json.loads((ROOT / "build-system/rufatgram-configuration.json").read_text())
        self.environment = {"RUFATGRAM_API_ID": "12345", "RUFATGRAM_API_HASH": "1234567890abcdef" * 2}

    def test_missing_credentials_stop_a_distributable_build(self):
        with self.assertRaisesRegex(ValueError, "Set both"):
            configuration.resolve_configuration(self.template, {})

    def test_compile_only_mode_is_explicit(self):
        resolved, placeholders = configuration.resolve_configuration(self.template, {}, allow_placeholder_api=True)
        self.assertTrue(placeholders)
        self.assertEqual(resolved["api_id"], "0")

    def test_partial_credentials_are_never_accepted(self):
        with self.assertRaises(ValueError):
            configuration.resolve_configuration(self.template, {"RUFATGRAM_API_ID": "12345"}, allow_placeholder_api=True)

    def test_secrets_override_template_without_mutating_it(self):
        resolved, placeholders = configuration.resolve_configuration(self.template, self.environment)
        self.assertFalse(placeholders)
        self.assertEqual(resolved["api_id"], "12345")
        self.assertEqual(self.template["api_id"], "0")

    def test_rejects_invalid_inputs_before_bazel_interpolation(self):
        invalid = {
            "RUFATGRAM_API_ID": ["-1", "2147483648", "123.4"],
            "RUFATGRAM_API_HASH": ["not-a-hash", '"\nfail("injected")'],
            "RUFATGRAM_BUNDLE_ID": ["ph.telegra.Telegraph", 'com.example."bad', "a/b"],
            "RUFATGRAM_TEAM_ID": ["short", "abcdefghij"],
            "RUFATGRAM_URL_SCHEME": ["bad scheme", 'tg"'],
        }
        for variable, values in invalid.items():
            for value in values:
                with self.subTest(variable=variable, value=value), self.assertRaises(ValueError):
                    configuration.resolve_configuration(self.template, dict(self.environment, **{variable: value}))

    def test_signed_build_requires_real_team(self):
        with self.assertRaisesRegex(ValueError, "Signed builds require"):
            configuration.resolve_configuration(self.template, self.environment, signed=True)

    def test_configuration_template_cannot_be_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            template = Path(temporary) / "template.json"
            template.write_text("original")
            with self.assertRaises(ValueError):
                configuration.write_configuration(template, template, self.template)
            self.assertEqual(template.read_text(), "original")

    def test_output_round_trips_credentials_and_restricts_permissions(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "configuration.local.json"
            resolved, _ = configuration.resolve_configuration(self.template, self.environment)
            configuration.write_configuration(Path(temporary) / "template.json", output, resolved)
            self.assertEqual(json.loads(output.read_text()), resolved)
            import os
            if os.name != "nt":
                self.assertEqual(output.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
