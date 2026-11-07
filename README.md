# AyuGram for iOS

An unofficial iOS port of AyuGram features, built on this repository's Swiftgram / Telegram iOS client. This project is independent of the AyuGram and Telegram teams.

The implementation branch is `ayugram-ios-port`, based on the previously built `feature/ci-and-privacy-center` branch. It preserves the Telegram 12.0, Xcode 16.2 and Bazel 8.3.1 toolchain. Updating Telegram's protocol and upstream version is a separate integration task.

## Implemented in this branch

- Ghost settings shared across accounts or kept individually, a master toggle, locked options, and per-chat read/typing exceptions.
- Read-receipt suppression at the outgoing request boundary, including media contents, mentions, reactions, discussions and stories; an explicit one-shot server-read command and a separate local-read command.
- Online/typing/upload controls, offline restoration after sending, optional read-on-send/reaction/vote, silent sending and delayed sending while ghost mode is active.
- A per-account archive of deleted messages and previous edits, with search, message-specific history, downloaded attachment retention, storage limits, chat rules, and JSON metadata import/export.
- Literal and regular-expression message filters, optional hiding of sponsored posts and blocked users, and filter exceptions.
- AyuForward for copying received text, photos, files, voice messages, contacts and locations as new messages, with attachment reupload; message-image sharing and message details.
- A foreground recording/mirroring shield, optional chat-list masking, local-only Premium icon/status previews, and a launch shortcut that enables ghost mode.
- Existing client customization, multiple accounts, Telegram chats, calls and media support.

Implementation is not equivalent to device verification or complete parity. [The feature audit](docs/AYUGRAM_FEATURE_AUDIT.md) lists the reference features and acceptance criteria, including platform limitations and missing source components. The supplied Android APK has been inspected statically; exact matching source for that binary is not available in the inspected public repository. Features should only be marked verified after the relevant tests actually run.

## Build on GitHub Actions

Repository settings → **Secrets and variables → Actions → New repository secret**:

| Secret | Value |
| --- | --- |
| `RUFATGRAM_API_ID` | Your numerical Telegram `api_id` from <https://my.telegram.org/apps> |
| `RUFATGRAM_API_HASH` | The matching Telegram `api_hash` |

The existing secret names are retained for compatibility with previous builds. They must not be placed in committed files. [Open the repository's Actions secrets](https://github.com/nabivkubkov-prog/Ayugram-iOS/settings/secrets/actions).

Pushes to `ayugram-ios-port` run configuration tests and Swift policy tests, then build the full iOS target on `macos-15-intel`. The workflow rejects missing API credentials. It validates the produced IPA's bundle ID, build number, ARM64 executable and extensions before uploading an artifact and SHA-256 manifest. It does not automatically publish releases.

An unsigned/test-signed IPA requires re-signing before installation on a physical iPhone. A signed build additionally needs the Apple team ID, certificate and matching provisioning profiles described in [CI documentation](tools/ci/README.md). Compilation does not verify login, APNs or on-device behavior.

[Upstream manual build guide](docs/UPSTREAM_BUILD.md) · [Workflows](https://github.com/nabivkubkov-prog/Ayugram-iOS/actions)

## Data and platform behavior

The archive can retain only messages and resources this device has received. Attachments are copied outside Telegram's evictable media cache; unavailable downloads are identified as unavailable. JSON backups contain message metadata and serialized references, not the attachment files themselves. Logging out or deleting application data removes the local account archive.

Other Telegram sessions can publish their own online/read state. iOS can suspend the application in the background. Server-controlled Premium benefits and Android foreground services cannot be reproduced by a local iOS setting. Runtime scenarios for these limits belong in the verification matrix.

## Credits

- [Telegram iOS](https://github.com/TelegramMessenger/Telegram-iOS)
- [Swiftgram](https://github.com/Swiftgram/Telegram-iOS)
- [AyuGram Desktop](https://github.com/AyuGram/AyuGramDesktop) and [AyuGram Android](https://github.com/AyuGram/AyuGram4A), for behavior references and the AyuGram artwork
- The original authors and license notices in individual source files and submodules

Preserve the applicable upstream licenses, attribution, and corresponding-source obligations when distributing modified builds.
