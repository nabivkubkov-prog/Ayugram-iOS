# AyuGram → iOS: source and feature audit

Audit date: 2026-11-07. This document describes the reference behavior and acceptance criteria. A row in this document is **not** a claim that the iOS implementation exists or has passed a test.

## Reference sources and confidence

| Reference | Revision / location | What it establishes |
| --- | --- | --- |
| Supplied APK | `ayugram-apk-исходник/vanilla-ayugram-full-20261104.apk`, 133,795,216 bytes | Android release artifact supplied by the user; inspected statically, not executed. |
| APK build metadata | `META-INF/version-control-info.textproto`: `6029a7feaad350cbdd99a91178ea34ad623f1e4f` | Build-declared Git revision. This revision was not found at the corresponding raw URL in AyuGram4A. It is not proof of a specific public source tree. |
| APK English and Russian resources | `assets/ayu_locales/values/ayu.xml`, `assets/ayu_locales/values-ru/ayu.xml`; extracted as `apk-ayu-en.xml` and `apk-ayu-ru.xml` | Feature names, option descriptions, UI strings. They include Desktop-specific strings, so the presence of a key alone does not prove the Android executable exposes that feature. |
| AyuGram Desktop | [AyuGram/AyuGramDesktop](https://github.com/AyuGram/AyuGramDesktop), `dev`, `0f2a31bb420de98f331990432265b131b8d836b5` | Open C++ settings, text archive, filters, forwarding, UI, translation, and platform code. |
| AyuGram Android | [AyuGram/AyuGram4A](https://github.com/AyuGram/AyuGram4A), default branch `rewrite`, `7013145676d36d82ee13c02a89f72097b7490dcd`, commit date 2023-07-28 | Historical Android implementation. Repository metadata reports last push 2023-09-11. It cannot establish exact behavior of the 2026 APK. |
| Missing Android component | `TMessagesProj/src/main/java/com/radolyn/ayugram/proprietary`, gitlink `a3b47ff3af30829cdec58d61d61ebc0a64546563` to `AyuGram/AyuGram4A_proprietary.git` | The inspected public tree does not contain the implementation of `AyuMessageUtils` / `AyuHistoryHook`. Android archive and hooks cannot simply be copied from that tree. |
| Official feature descriptions | [Android docs](https://docs.ayugram.one/android/), [Desktop docs](https://docs.ayugram.one/desktop/) | Published reference feature lists; not an executable test of current behavior. |
| Existing user's iOS fork | [nabivkubkov-prog/Ayugram-iOS](https://github.com/nabivkubkov-prog/Ayugram-iOS) | Swiftgram-based starting point. The successful build branch is being selected separately. This audit does not infer implementation from the repository name or a green packaging workflow. |

## Findings that materially change the port

1. Android and Desktop are distinct products, with different option sets and platform features. “Everything” needs a union matrix plus explicit platform substitutions.
2. The supplied APK is not a source archive. Its shared localization bundle contains desktop tray, Ctrl/Shift, wide-monitor and Android service strings together. Each option must be checked against code or runtime behavior before declaring Android parity.
3. Desktop `ayu/data/messages_storage.cpp` has an explicit `todo: implement mapping` for media. It writes `mediaPath = "/"`, `documentType = 0`, and skips messages with empty text in both `addEditedMessage` and `addDeletedMessage`. It is a reference for text history only, not evidence of complete attachment archiving.
4. Android `AyuMessagesController` explicitly depends on the missing proprietary mapper. It saves the old revision before applying an edit, avoids duplicate deletion records, stores reaction snapshots, and moves attachment references to a retained copy. A new iOS implementation must supply these semantics itself.
5. An iOS app cannot retrieve content Telegram never delivered to it, or revive content whose only copy was removed before the archive observed it. Background suspension makes “all deletions while closed” an unsupported promise.
6. Local Premium changes client behavior only. Server-enforced limits, paid entitlements, and what other users see do not become Premium privileges.
7. A build result and device behavior are distinct evidence. Compilation, IPA packaging, signing, installation, login, notification delivery, and multi-account network behavior require separate verification.

## Feature matrix

Evidence abbreviations: **K** = supplied APK localization key, **D** = Desktop source/docs, **A** = historical Android source/docs. iOS status is `to verify / implement` unless explicitly updated by the implementer.

| ID | Reference feature | Evidence / anchor | Required iOS behavior and acceptance criterion |
| --- | --- | --- | --- |
| G01 | Do not send message read receipts | K `DontReadMessages`, D `GhostModeAccountSettings`, A `AyuGhostUtils` | Preserve independent local read state; with option enabled, reading private/group/channel messages must not advance server read state. Test with a second account. |
| G02 | Do not send story views | K `DontReadStories`, D `sendReadStories` | Story can display without transmitting its view/read request; verify from story owner account. |
| G03 | Suppress online updates | K `DontSendOnlinePackets`, D `sendOnlinePackets` | Block explicit online state updates; do not claim other server activity cannot reveal online status. Verify idle/open/send scenarios. |
| G04 | Suppress typing/upload activity | K `DontSendUploadProgress`, A `sendUploadProgress` | Suppress typing, voice recording and other activity requests; verify both private and group chats. |
| G05 | Send offline status after activity | K `SendOfflinePacketAfterOnline`, D `ayu_worker.cpp` | Schedule offline status restoration while app runs; respect per-account policy and cancellation. Background timer parity is not available on iOS. |
| G06 | One-tap ghost toggle | K `GhostModeToggle`, D `setGhostModeEnabled` | Toggle related switches together, restore individual choices predictably, update visible status immediately. |
| G07 | Lock individual ghost options | K `GhostModeOptionLongTapDescription`, D `*Locked` properties | Long-press or equivalent lock prevents global toggle from modifying a selected option. |
| G08 | Global or per-account ghost settings | K `GhostModeGlobalSettings`, D `AyuSettings::ghost` | Switching accounts must not apply another account's individual policy; explicit global mode shares it. |
| G09 | Per-chat read and typing exceptions | K `ReadExclusionMenuText`, `TypingExclusionMenuText` | Never/default/always behavior takes precedence as documented and is account-scoped. |
| G10 | Read on interaction | K `MarkReadAfterAction`, `MarkReadAfterSend/Reaction/Poll` | Sending, reacting and poll voting can independently authorize read receipts; ordinary viewing must not. |
| G11 | Scheduled sending for ghost mode | K `UseScheduledMessages` | Use server scheduled messages with documented approximate delay; preserve explicit schedule, silent send, media grouping and cancellation. Test network failure and unsupported peers. |
| G12 | Silent send default | K `SendWithoutSoundByDefault` | Never / only in ghost / always, applied to all outgoing message entry paths, with explicit override. |
| G13 | Story ghost suggestion | K `SuggestGhostModeBeforeViewingStory` | Prompt before the story-view request is issued; accepted choice must precede opening. |
| G14 | Local/server manual read commands | K `LReadMessages`, `SReadMessages`, `ReadUntilMenuText` | Local read modifies only local state; server read is an explicit one-shot exception, without disabling global ghost policy. |
| G15 | Ghost quick action and visible status | K `DisplayGhostStatus`, `GhostModeShortcut` | App shortcut and chat-list badge accurately reflect current account policy. |
| H01 | Retain deleted messages | K `SaveDeletedMessages`, D `addDeletedMessage`, A controller | Snapshot delivered messages before remote deletion; preserve account/peer/namespace/message identity. Restart and cache cleaning must not erase archive. |
| H02 | History of edits | K `SaveMessagesHistory`, A `onMessageEditedInner` | Preserve old text, formatting and attachment reference before replacement, with ordered timestamps; ignore replayed identical edits. |
| H03 | Preserve media-only messages | K `MessageSavingSaveMedia`, A `mapMedia` call | Photo/video/file/voice/sticker messages without text produce usable archive entries. Desktop mapper does not establish this implementation. |
| H04 | Durable retained attachments | K `AyuAttachments`, A `attachmentsSubfolder` | Copy complete local resources outside Telegram's evictable cache, never retain only a cache path; track missing/incomplete files honestly. |
| H05 | Attachment rules by chat type | K `MessageSavingSaveMediaIn*` | Separate private chat, public/private channel, public/private group policy. |
| H06 | Cellular/Wi-Fi media limits | K `MaximumMediaSizeCellular/WiFi` | Connection-specific maximum applies before initiating archive downloads; missing media remains marked unavailable. |
| H07 | Archive storage limit and eviction | K `AttachmentsFolderMaxSize*` | Evict oldest retained attachments at the selected limit; preserve message metadata and avoid deleting shared files still referenced by another revision. |
| H08 | Save inclusion/exclusion policy | K `SaveExclusions*`, `ExclusionAlwaysSave` | All-except-selected or selected-only, per-peer and per-type; selected-only with no entries saves nothing. |
| H09 | Bot/secret-chat exclusions | K `SaveExclusionsBotDialogs/BotsInGroups/SecretChats` | Resolve peer type before saving; unknown peer handling is defined, account settings remain isolated. |
| H10 | Preserve reactions and formatting | A `processDeletedReactions`, `AyuMessageBase.textEntities` | Store typed reaction and text-entity data instead of flattening to plain text; unsupported entity types remain recoverable. |
| H11 | Preserve forums, albums, replies, sender data | A `AyuMessageBase` fields, D entities | Include thread/topic, grouped ID, reply IDs, forward metadata, sender IDs/names and original timestamps in record. |
| H12 | Deleted message/revision browser | K `ViewDeletedMenuText`, `EditsHistoryTitle` | Open archive for a chat/message, paginate, search, show time and original context, handle unavailable attachments. |
| H13 | Deleted/edited labels and opacity | K `DeletedMarkText`, `EditedMarkText`, `SemiTransparentDeletedMessages` | Configurable labels/icons and opacity without changing actual content; accessible labels distinguish archived/deleted states. |
| H14 | Keep local copy during own deletion | K `DeleteKeepLocally` | Explicit action snapshots first, completes normal server delete, and does not cause the archival retention policy to block user's deletion intent. |
| H15 | Clear retained data | K `ClearDeletedMenuText` | Remove exactly selected chat/account records and unreferenced media; report failure, preserve other accounts and unrelated files. |
| H16 | Database export/import | K `ExportDatabaseButton`, `ImportDatabaseButton` | Versioned schema, replace/merge choices, duplicate detection, integrity and file-reference validation; no path traversal from imported media paths. |
| H17 | Cross-platform archive compatibility | K `ExportDataCompatHeader` | Claim AyuGram compatibility only after round-trip tests against actual Android/Desktop database fixtures; a custom JSON export is not equivalent. |
| H18 | Retain kicked/banned chat cache | A docs | Separate locally retained history from server membership; do not repeatedly retry unavailable server history. |
| H19 | Retain browsing after terminated session | K `SessionTerminated` | Needs explicit local archive access independent of an active account session; app lock and logout data deletion policy must remain coherent. |
| H20 | Save observed message read times | K `SpySaveReadMarks` | Save only times observed by this client and show provenance; absence of server read time does not justify inventing one. |
| H21 | Approximate observed last-seen | K `SpySaveLocalOnline`, `LikelyOfflineStatus` | Mark inferred timestamps approximate, based only on observed activity; not a bypass for unavailable Telegram data. |
| F01 | Regex/keyword message filters | K `RegexFilters*`, D filters controller | Compile validated Unicode expressions; hide matching incoming messages under enabled policy; handle invalid patterns without crash. |
| F02 | Case-insensitive and reversed filters | K `CaseInsensitiveExpression`, `ReversedExpression` | Specify search vs full-match semantics and inversion; test Unicode, empty input, multiline content and disabled patterns. |
| F03 | Shared/per-chat filters and exclusions | K `RegexFiltersShared/Excluded`, D entities | Shared filters apply only in configured chat types; per-chat exclusions override selected shared filters. |
| F04 | Hide blocked users / local shadow ban | K `FiltersHideFromBlocked`, `FiltersShadowBan` | Filter sender identity without changing server ban/block state; remove policy immediately when toggled off. |
| F05 | Show filtered messages temporarily | K `ShowFilteredMessagesMenuText` | Per-chat temporary reveal changes presentation without destructive deletion. |
| F06 | Filter import/export and diff | K `FiltersMenuImport/Export`, `FiltersSheet*` | Validate format, show additions/removals/updates, support clipboard/file; network publication is explicit user action. |
| F07 | Hide Telegram sponsored messages | K `DisableAds`, D/A docs | Cover sponsored content request and rendering paths; ordinary messages matching ads require the separate filter feature. |
| C01 | Local Premium | K `LocalPremiumNotice`, D/A docs | Enable only implementable local presentation features; server limits and subscription remain unchanged. |
| C02 | Restricted-content copy/save/forward | D/A docs, K `AyuForward*` | Re-upload available content where normal forwarding is unavailable; media progress, cancellation, albums, captions, destination errors handled. |
| C03 | Repeated viewing / explicit expiration of ephemeral media | K `ExpireMediaContextMenuText`, `Once*MessageNote` | Requires changes in capture, receipt and cache expiration paths. Verify exact media types; never claim recovery of content already expired before receipt. |
| C04 | Message details | K `MessageDetails*` | Show actual IDs, times, counts, sizes, type, dimensions, data center; absent values must remain absent. |
| C05 | Peer ID display/copy/search | K `SettingsShowID`, `ContextCopyID`, `SearchByIDResults` | Correct bot-style and native namespaces, no collisions between users/chats/channels; remote resolution may require access hash. |
| C06 | Message shot | K `MessageShot*` | Render selected message(s) to image with selectable background, time, reactions, decorations and spoiler policy. |
| C07 | Jump to first message / sender messages | K `JumpToBeginning`, `UserMessagesMenuText` | Navigate with pagination and access failure handling; avoid assuming first ID is 1. |
| C08 | Repeat message / send media as sticker | K `RepeatMessage`, `SendAsSticker` | Preserve content and explicitly selected send options, validate sticker format/size. |
| C09 | Delete own messages from group | K `DeleteOwnMessages` | User-visible scope and confirmation, paginated deletion, cancellation and flood-wait handling. |
| C10 | Send confirmation for stickers/GIF/voice/round video | K `Confirmation*`, D settings | Confirm before enqueue; cancel leaves recording/message intact or discards it consistently. |
| C11 | Copy inline-button callback data | K `ContextCopyCallbackData` | Display raw callback data without accidentally triggering bot action. |
| C12 | Translator providers | D `features/translator`, K `LinksTranslate` | Translation provider selection, language and error handling; local Premium does not remove remote rate limits. |
| C13 | Read receipts and history sync (AyuSync) | A `sync/*`, README | Old backend protocol is a reference only; current server compatibility, authentication, account isolation and history format require verification. |
| U01 | Hide stories / custom backgrounds / Premium statuses | K respective switches | Individual rendering toggles with reversible effects and live settings updates. |
| U02 | Hide reactions by peer type | K `HideChannelReactions`, `HideGroupReactions` | Distinct channel/group/private policies; hidden visuals do not mutate reactions. |
| U03 | Simplify colorful replies / similar channels | K `SimpleQuotesAndReplies`, `DisableSimilarChannels` | Cover bubble decorations and relevant recommendation surfaces. |
| U04 | Notification badge and folder counters | K `HideNotificationCounters/Badge` | Separate app badge, chat counts and folder indicators; notification delivery is independent. |
| U05 | Chat list folders and All Chats visibility | D docs, K `ChatFoldersHeader` | Avoid leaving no navigable folder; preserve navigation across configuration changes. |
| U06 | Bubble radius / width / tails / fonts | D settings, K `MessageBubbleRadius`, `MainFont`, `MonospaceFont` | Adapt widths to iPhone/iPad rather than desktop dimensions; preserve text layout, Dynamic Type and hit targets. |
| U07 | Context-menu customization | K `SettingsContextMenu*` | iOS long-press selection UI instead of Desktop Ctrl/Shift/right-click behavior. |
| U08 | Composer buttons and popups | K `MessageFieldElements*`, D settings | Hide/show attachment, commands, emoji, voice, TTL, gifts/AI if supported by upstream version. |
| U09 | Channel bottom button | K `ChannelBottomButton*` | Hide/mute/discuss modes with fallback when discussion is unavailable. |
| U10 | App icon variants | K `Icon*` | Bundled alternate icons through supported iOS API; no arbitrary Android icon reuse claim. |
| U11 | Streamer mode | K `StreamerModeToggle`, D platform streamer code | Redact selected app content during active capture/screenshare. iOS cannot guarantee that every screenshot is prevented. |
| U12 | Message seconds / smooth scrolling / notification delay | K respective keys | Settings map to concrete rendering/timing behavior and do not introduce read/activity side effects. |
| U13 | Emoji/sticker recents and picker filtering | K `SettingsUnlimitedRecentStickers`, `ShowOnlyAddedEmojisAndStickers` | Local recents storage and picker presentation; server collection limits remain server-controlled. |
| U14 | Improve link previews / webview UA and sizing | K `ImproveLinkPreviews`, `SettingsSpoofWebviewAsAndroid` | Validate iOS WKWebView behavior and preserve Telegram Mini App integration; desktop window sizing needs iPad adaptation. |
| U15 | Haptics / force-click preview / gesture customization | D macOS feature list, K `GesturesInfo` | iOS long-press/haptic equivalents; Mac pressure-sensitive trackpad semantics are not identical. |
| U16 | Crash reporting and support badges | K `CrashReporting`, `SupporterPopup` | Original infrastructure is not automatically available to a fork; configure owned endpoint or leave feature disabled with accurate UI. |
| P01 | Android foreground keepalive / FCM | K `KeepAliveService`, `PushNotificationCount` | No direct iOS port. Use APNs and permitted iOS background modes; no permanent Android-style service. |
| P02 | Android storage selector / WAL control | K `MessageSavingSavePath`, `WALMode` | iOS app-container storage and document picker; internal database mode is implementation-specific. |
| P03 | Tray menus / taskbar counters / kill app | K `TrayElementsHeader`, `KillApp` | Desktop tray has no iPhone equivalent; use app shortcuts where appropriate. Programmatic force-quit is not a faithful UX substitution. |
| P04 | Original build keys / app identity | A historical README | Use the fork's own API ID/hash and own bundle/signing configuration. The original app's identity is not a feature to copy. |

## Source map for implementation

Desktop prefix: `Telegram/SourceFiles/` at the pinned Desktop revision above.

- `ayu/ayu_settings.h` / `.cpp`: account/global ghost policies, toggles, appearance and context menu configuration.
- `ayu/ayu_worker.cpp`: every-three-second offline status maintenance while running.
- `ayu/data/messages_storage.cpp` / `.h`: capture/query text revisions and deleted messages; incomplete media mapper noted above.
- `ayu/data/entities.h`: account/chat/message identity, revision metadata, filter model.
- `ayu/data/ayu_database.cpp` / `.h`: durable storage and filter queries.
- `ayu/features/filters/{filters_controller,filters_cache_controller,filters_utils}.*`: filtering policy and visibility.
- `ayu/features/forward/ayu_forward*.cpp`: copying/re-uploading content and progress.
- `ayu/features/message_shot/*`: rendered message capture and theme settings.
- `ayu/features/streamer_mode/*`: platform-specific protection behavior; cannot be copied directly to iOS.
- `ayu/features/translator/*`: provider abstraction and implementations.
- `ayu/ui/message_history/*`: revision/history presentation.

Android prefix: `TMessagesProj/src/main/java/com/radolyn/ayugram/` at the pinned historical revision above.

- `AyuConfig.java`: persisted policy and global ghost switch.
- `utils/AyuGhostUtils.java`: explicit local/server reads and request-to-peer mapping.
- `messages/AyuMessagesController.java`: deduplication, old revision detection, archival notifications, reaction snapshots.
- `messages/AyuSavePreferences.java`: account/peer/message identity at capture time.
- `database/entities/*`: old schema; `schemas/com.radolyn.ayugram.database.AyuDatabase/21.json` provides a historical migration snapshot.
- `proprietary`: missing submodule; the public sources cannot independently implement all hooks/mapping.
- `sync/*`: historical AyuSync protocol; current compatibility unverified.

## Minimum evidence for a completed port

- Automated policy tests: ghost global/account/chat precedence; local and server read distinction; one-shot explicit reads; invalid filters; archive identity and duplicate events.
- Automated archive tests: text-only and media-only message retention; multiple edits; restart; cache deletion; import/export; corrupt imports; multi-account separation; interrupted write; missing resource; shared-resource eviction.
- Full target compile on the pinned macOS/Xcode/Bazel combination, not only lint or a packaging shell script.
- Device installation with a valid signature and entitlements; launch and Telegram login with the user's API application.
- Two-account runtime scenarios for online, typing, reads, stories and scheduled sending, including app background/foreground transitions.
- Device checks for editing/deleting delivered messages; media cache cleaning and reopening archive; account logout/switching; APNs while suspended.
- Matrix entries updated with actual source location and test evidence. A toggle without a call-site hook remains unimplemented. A hook without runtime evidence remains unverified.

## Current audit limitation

The APK was inspected as an archive and localization source. It has not been executed on Android and its DEX code has not been fully decompiled. The exact 2026 Android source revision and current private components are unavailable in the inspected public repositories. The matrix therefore explicitly separates observed strings, public implementations and platform constraints, instead of declaring exact binary parity.
