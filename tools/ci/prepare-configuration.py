#!/usr/bin/env python3
"""Resolve build settings from environment without printing API credentials.

RUFATGRAM_API_ID and RUFATGRAM_API_HASH are the existing repository secrets.
Normal builds require both. --allow-placeholder-api is only for explicit
compile-only verification; artifacts made with that flag cannot sign in.
"""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess

ENVIRONMENT_KEYS = {
    "RUFATGRAM_API_ID": "api_id",
    "RUFATGRAM_API_HASH": "api_hash",
    "RUFATGRAM_TEAM_ID": "team_id",
    "RUFATGRAM_BUNDLE_ID": "bundle_id",
    "RUFATGRAM_URL_SCHEME": "app_specific_url_scheme",
}

REQUIRED_KEYS = {
    "bundle_id", "api_id", "api_hash", "team_id", "app_center_id",
    "is_internal_build", "is_appstore_build", "appstore_id",
    "app_specific_url_scheme", "premium_iap_product_id", "enable_siri",
    "enable_icloud", "sg_config",
}


def resolve_configuration(template, environment, allow_placeholder_api=False, signed=False):
    configuration = dict(template)
    missing = REQUIRED_KEYS - configuration.keys()
    if missing:
        raise ValueError("Configuration is missing keys: " + ", ".join(sorted(missing)))

    for variable, key in ENVIRONMENT_KEYS.items():
        value = environment.get(variable, "").strip()
        if value:
            configuration[key] = value

    api_id = str(configuration["api_id"])
    api_hash = str(configuration["api_hash"])
    if not re.fullmatch(r"[0-9]+", api_id) or int(api_id) > 2147483647:
        raise ValueError("RUFATGRAM_API_ID must be a positive 32-bit integer")
    if not re.fullmatch(r"[0-9a-fA-F]{32}", api_hash):
        raise ValueError("RUFATGRAM_API_HASH must contain exactly 32 hexadecimal characters")
    placeholder_api = int(api_id) == 0 or api_hash == "0" * 32
    if placeholder_api and not allow_placeholder_api:
        raise ValueError("Set both RUFATGRAM_API_ID and RUFATGRAM_API_HASH in repository Actions secrets")
    if placeholder_api and not (int(api_id) == 0 and api_hash == "0" * 32):
        raise ValueError("API id and hash must be provided together")

    bundle_id = str(configuration["bundle_id"])
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle_id):
        raise ValueError("RUFATGRAM_BUNDLE_ID must be a valid reverse-domain identifier")
    if bundle_id in {"ph.telegra.Telegraph", "org.telegram.Telegram-iOS"}:
        raise ValueError("Use a bundle identifier belonging to this fork")
    team_id = str(configuration["team_id"])
    if not re.fullmatch(r"[A-Z0-9]{10}", team_id):
        raise ValueError("RUFATGRAM_TEAM_ID must contain 10 uppercase letters or digits")
    if signed and team_id == "AAAAAAAAAA":
        raise ValueError("Signed builds require RUFATGRAM_TEAM_ID and Apple signing assets")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9+.-]*", str(configuration["app_specific_url_scheme"])):
        raise ValueError("RUFATGRAM_URL_SCHEME is not a valid URL scheme")

    configuration["api_id"] = api_id
    configuration["api_hash"] = api_hash
    return configuration, placeholder_api


def write_configuration(template_path, output_path, configuration):
    template_path = Path(template_path).resolve()
    output_path = Path(output_path).resolve()
    if template_path == output_path:
        raise ValueError("Refusing to overwrite the configuration template")

    repository = Path(__file__).resolve().parents[2]
    try:
        relative_output = output_path.relative_to(repository)
    except ValueError:
        relative_output = None
    if relative_output is not None and (repository / ".git").exists():
        result = subprocess.run(
            ["git", "-C", str(repository), "ls-files", "--error-unmatch", "--", relative_output.as_posix()],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
        )
        if result.returncode == 0:
            raise ValueError("Refusing to write API credentials into a tracked file")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(str(output_path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as file:
        json.dump(configuration, file, indent=2)
        file.write("\n")
    os.chmod(output_path, 0o600)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("template")
    parser.add_argument("output")
    parser.add_argument("--allow-placeholder-api", action="store_true")
    parser.add_argument("--signed", action="store_true")
    arguments = parser.parse_args()
    try:
        with open(arguments.template, encoding="utf-8") as file:
            template = json.load(file)
        configuration, placeholders = resolve_configuration(
            template, os.environ, arguments.allow_placeholder_api, arguments.signed,
        )
        write_configuration(arguments.template, arguments.output, configuration)
    except (ValueError, OSError) as error:
        parser.exit(1, "::error::" + str(error) + "\n")
    if placeholders:
        print("::notice::Compile-only configuration: Telegram sign-in is unavailable")
    else:
        print("Telegram API configuration supplied; credentials were not printed")


if __name__ == "__main__":
    main()
