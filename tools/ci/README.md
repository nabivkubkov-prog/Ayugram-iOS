# AyuGram iOS builds

The `AyuGram iOS build` workflow builds branch `ayugram-ios-port`. It uses the
Xcode and Bazel versions in `versions.json` on `macos-15-intel`, preserving the
host architecture of the verified predecessor. API credentials are required;
normal CI never substitutes a dummy Telegram API identity.

## Telegram credentials

Open the repository's **Settings → Secrets and variables → Actions → Secrets**:

https://github.com/nabivkubkov-prog/Ayugram-iOS/settings/secrets/actions

Create or update these existing secret names:

| Secret | Value |
| --- | --- |
| `RUFATGRAM_API_ID` | Your numeric `api_id` from https://my.telegram.org/apps |
| `RUFATGRAM_API_HASH` | The matching 32-character `api_hash` |

These names retain compatibility with earlier builds. The workflow writes the
values to the ignored `build-system/rufatgram-configuration.local.json` and
removes that file after the build. Do not put credentials in the committed
configuration template. Updating a secret does not start a build automatically;
run the workflow again to embed the updated application identity.

## Download and installation

After the entire workflow succeeds, open its run and download the
`AyuGram-<run>-unsigned` artifact. It contains `AyuGram.ipa`, debug symbols and
`build-manifest.json` with the source commit, version, architecture and SHA-256.
The verification step checks that the executable and app extensions contain
ARM64 code and their identifiers belong to the configured app.

An unsigned build uses temporary self-signed assets to complete compilation.
It must be re-signed with your own Apple identity before an iPhone will install
it. GitHub Actions compilation does not supply an Apple signing identity or
grant push-notification entitlements. The workflow does not publish a release.

For a signed CI build, also configure `RUFATGRAM_TEAM_ID`, optionally
`RUFATGRAM_BUNDLE_ID`, `BUILD_CERTIFICATE_BASE64` (a .p12), `P12_PASSWORD`,
`KEYCHAIN_PASSWORD`, and `PROFILES_JSON_BASE64` (base64 JSON mapping profile names
to base64 .mobileprovision contents). Profiles must cover the application and
all embedded extensions. Then use the workflow's `signed` input. A single main
app profile is insufficient for the full extension-enabled application.

## Checks

`python3 -m unittest discover -s tools/ci/tests -v` runs credential validation
and archive validation tests. Pull requests run the checks without consuming
the repository's API secrets. The `checks_only` workflow input skips the full
application compilation. These checks do not replace real-device testing of
login, background delivery, privacy settings and message history.
