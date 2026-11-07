# AyuGram iOS: фактический статус переноса

Обновлено: 2026-11-07. Ветка `ayugram-ios-port`; база Telegram/Swiftgram 12.0,
Xcode 16.2, Bazel 8.3.1. **Полное соответствие Android APK пока не достигнуто.**
Наличие исходного кода ниже означает найденный hook, а не успешную проверку поведения
на iPhone. Все проверки на устройстве сейчас **NOT RUN**.

## Проверки и сборка

| Проверка | Подтверждённый результат | Граница доказательства |
| --- | --- | --- |
| Базовая unsigned-сборка `471e68b` | [PASS, run 40033401105](https://github.com/nabivkubkov-prog/Ayugram-iOS/actions/runs/40033401105) | Старая основа до переноса; не доказывает компиляцию новых модулей. |
| Первые policy/model-тесты `15db04a` | [checks и swift-checks PASS, run 42366637039](https://github.com/nabivkubkov-prog/Ayugram-iOS/actions/runs/42366637039) | Полная сборка отменена после последующих изменений. |
| Тесты конфигурации и IPA fixtures, `8392ed8` | [checks PASS, run 42367696167](https://github.com/nabivkubkov-prog/Ayugram-iOS/actions/runs/42367696167/job/128389239383) | Это тестовые fixtures, нового IPA ещё нет. |
| Swift parse всех изменений и standalone-тесты, `8392ed8` | [swift-checks PASS](https://github.com/nabivkubkov-prog/Ayugram-iOS/actions/runs/42367696167/job/128389239095) | Ghost policy, фильтры, archive model/filesystem/media budget, appearance preferences. Не компиляция всех UIKit/Postbox/TelegramCore targets. |
| Полный unsigned target, `8392ed8` | IN PROGRESS в run 42367696167 на момент обновления | Финальный результат и artifact ещё ожидаются. Последующие локальные исправления требуют собственной проверки. |
| Подпись, установка, запуск, login, APNs | NOT RUN | Нужны API credentials, действующая подпись/capabilities и устройство. |
| Два аккаунта: read/typing/online/story; deletion/edit/cache clearing | NOT RUN | Сценарии в [DEVICE_TEST_MATRIX.md](DEVICE_TEST_MATRIX.md). Policy unit test не подтверждает отсутствие реального RPC. |

Последующие исправления lifecycle AyuForward, forum destinations и album keys не
покрыты автоматически результатом `8392ed8`. Статусы привязаны к конкретным коммитам,
чтобы старый зелёный запуск не выдавался за проверку нового кода.

## Реализация и evidence

ID соответствуют [полной матрице исходных функций](AYUGRAM_FEATURE_AUDIT.md).
SOURCE — код и место вызова существуют; PARTIAL — реализована указанная часть.
Device result каждой строки — **NOT RUN**.

| ID / функция | Состояние и конкретные hooks | Автоматическая проверка / предел реализации |
| --- | --- | --- |
| G01–G02: read receipts и stories | SOURCE: [Network.request](../submodules/TelegramCore/Sources/Network/Network.swift), [AyuGhostPolicy](../Swiftgram/SGSimpleSettings/Sources/AyuGhostPolicy.swift), read/consume/story call sites | Policy PASS: RPC list, overrides, обычные send/get не блокируются. Реальные server state, voice, mentions/reactions, forum и queued operations NOT RUN. |
| G03–G05: online, typing/upload, offline restoration | SOURCE: [ManagedAccountPresence](../submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift), [ManagedLocalInputActivities](../submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift), [AyuGhostActions](../submodules/TelegramCore/Sources/State/AyuGhostActions.swift), send/edit/reaction completion hooks | Таймер действует пока приложение исполняется. Не гарантия полной серверной невидимости или постоянной фоновой работы. |
| G06–G09: toggle/locks/account/global/chat rules | SOURCE: [AyuGhostPreferences](../Swiftgram/SGSimpleSettings/Sources/AyuGhostPreferences.swift), [AyuSettingsController](../Swiftgram/SGSettingsUI/Sources/AyuSettingsController.swift) | [Policy/persistence tests](../Tests/AyuGramCoreTests/main.swift) PASS: locks, account isolation, global switching, corrupt storage. UIKit и правильный peer на реальных RPC NOT RUN. |
| G10: read-on-send/reaction/poll | PARTIAL: [EnqueueMessage](../submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift), [MessageReactions](../submodules/TelegramCore/Sources/State/MessageReactions.swift), [Polls](../submodules/TelegramCore/Sources/TelegramEngine/Messages/Polls.swift) | Send/reaction trigger при локальном действии, даже при последующей ошибке доставки; poll — после успешного RPC. UI теперь явно описывает это поведение; never-read rule имеет приоритет. Failed/cancelled send и forum scope на устройстве NOT RUN. |
| G11–G12: scheduled/silent send | PARTIAL: EnqueueMessage добавляет schedule около +11 секунд и muted default | Ручное schedule сохраняется, исключены bots/secret/Saved/paid. Silent только в ghost; полного Android never/ghost/always нет. Альбомы, отмена и failure NOT RUN. |
| G13: story prompt | PARTIAL: унаследованный Privacy Center и story flow | Есть подтверждение перед открытием; соответствие всем Ayu suggestion flows не проверено. |
| G14: local/server manual read | PARTIAL: AyuGhostActions, экран chat exceptions | Локальная transaction и явный RPC bypass раздельны. UI читает весь чат; «до выбранного сообщения» и отдельный forum-topic read не добавлены. |
| G15: shortcut/status | SOURCE: [ApplicationShortcutItem](../submodules/TelegramUI/Sources/ApplicationShortcutItem.swift), AppDelegate, [ChatListController](../submodules/ChatListUI/Sources/ChatListController.swift) | Shortcut включает ghost, индикатор слушает изменения. Cold launch/account switching NOT RUN. |
| H01–H03: deletion/edit/media-only archive | SOURCE: [AyuHistoryStore](../submodules/TelegramCore/Sources/State/AyuHistoryStore.swift), [AccountStateManagementUtils](../submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift), [RufatDeletedMessageAttribute](../submodules/TelegramCore/Sources/SyncCore/RufatDeletedMessageAttribute.swift), [RequestEditMessage](../submodules/TelegramCore/Sources/PendingMessages/RequestEditMessage.swift) | Model tests PASS. Postbox durable collection и capture до замены есть. Реальные updates/difference/own edit/repeated delete/cache restart NOT RUN. |
| H04/H07: retained media/budget | SOURCE: AyuHistoryStore, [AyuHistoryMediaBudget](../submodules/TelegramCore/Sources/State/AyuHistoryMediaBudget.swift); sibling folder `ayugram-history-media` | Filesystem PASS: hard link после удаления cache source, eviction/rebuild, generated-name boundary. Только уже доступные полные resources. Crash/failure/Postbox integration и нагрузка NOT RUN. |
| H05/H08/H09: chat/media/bot rules | PARTIAL: [AyuHistoryModel](../submodules/TelegramCore/Sources/State/AyuHistoryModel.swift), store, [AyuHistoryController](../Swiftgram/SGSettingsUI/Sources/AyuHistoryController.swift) | Policy PASS: account-scoped lists, пустой allow-list, public/private/bot rules. Secret/TTL всегда исключены. |
| H10/H11: attributes/media/entities/forward/reply/forum/album | PARTIAL: model/store сохраняют opaque snapshots и явные metadata | Round-trip PASS. Browser plain text и отдельные файлы; rich replay и отдельная история reactions отсутствуют. |
| H12/H15: browser/search/clear | SOURCE: AyuHistoryController и [message context menu](../submodules/TelegramUI/Sources/Chat/ChatControllerOpenMessageContextMenu.swift) | Search model PASS; pagination по 100, chat/message filter, file error handling есть. UIKit/share/20k-record performance NOT RUN. |
| H13: deleted labels | PARTIAL: унаследованный marker и его rendering | Полные configurable opacity/custom deleted/edited labels не перенесены. |
| H16/H17: backup/compatibility | PARTIAL: собственный JSON v1 metadata backup/merge | [Archive tests](../Tests/AyuHistoryTests/main.swift) PASS: Unicode/Int64/account/version/input bounds/path removal. JSON не содержит retained bytes. Native Android/Desktop SQLite и AyuSync отсутствуют. |
| F01/F02: regex/keyword | PARTIAL: [AyuMessageFilter](../Swiftgram/SGSimpleSettings/Sources/AyuMessageFilter.swift), [ChatHistoryEntriesForView](../submodules/TelegramUI/Sources/ChatHistoryEntriesForView.swift) | [Filter tests](../Tests/AyuMessageFilterTests/main.swift) PASS: Unicode/case/invalid/disabled/zero-length/expensive regex/persistence. Reversed rules отсутствуют, rendering NOT RUN. |
| F04/F07: blocked/sponsored | PARTIAL: [AyuMessageFilterState](../submodules/TelegramUI/Sources/AyuMessageFilterState.swift), ChatHistoryEntriesForView | Policy PASS; blocked-list signal и sponsored insertion hooks есть. Local shadow-ban отсутствует. Sponsored RPC не отключены, скрывается отображение. |
| C01/U10: Local Premium/icons | PARTIAL: [AyuAppearanceSettings](../Swiftgram/SGSimpleSettings/Sources/AyuAppearanceSettings.swift), [PeerInfoScreen](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift), [ThemeSettingsController](../submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift) | [Appearance tests](../Tests/AyuAppearanceTests/main.swift) PASS. Только свой локальный badge/status и bundled icons; серверные Premium права не меняются. |
| C02: AyuForward/copy | PARTIAL: [AyuForward](../submodules/TelegramCore/Sources/PendingMessages/AyuForward.swift), [AyuForwardController](../Swiftgram/SGSettingsUI/Sources/AyuForwardController.swift), message context menu | Text/photo/file/voice/video/contact/location reupload до 100 сообщений. Secret/TTL и специальные poll/game/paid/invoice типы не поддержаны. Parse PASS `8392ed8`; последующие forum/album/cancel patches PENDING. Device download/send NOT RUN. |
| C04/C06: details/Message Shot | PARTIAL: [AyuMessageTools](../Swiftgram/SGSettingsUI/Sources/AyuMessageTools.swift), context menu | ID/time/author/thread/album/MIME/size; snapshot через `ChatMessageItemView.makeContentSnapshot()` до закрытия extracted menu, share после dismiss completion, nil/error и iPad anchor обработаны. Эти последующие исправления ещё PENDING CI. Нет полного details и shot editor/background/decorations/spoiler controls; video/async content и iPad runtime NOT RUN. |
| U11: streamer mode | PARTIAL: [AyuCaptureShield](../submodules/TelegramUI/Sources/AyuCaptureShield.swift), AppDelegate, mask/accessibility в [ChatListItem](../submodules/ChatListUI/Sources/Node/ChatListItem.swift) | Preferences PASS. Capture/mirroring/app switcher/VoiceOver NOT RUN. Не скрывает обычные screenshots и системные уведомления; capture detection может запаздывать. |
| U07/U08, часть C07/C12: меню/composer/translation | PARTIAL: [AyuAppearanceController](../Swiftgram/SGSettingsUI/Sources/AyuAppearanceController.swift) использует существующие Swiftgram options | Hooks найдены в ChatInterfaceStateContextMenus, ChatTextInputPanelNode, ChatMessageItemImpl, MediaPickerScreen, ShareController, ManagedAudioSession. Select-from-user, Saved, hide-forward-author, JSON, restrict/report, quick translation, Send As/record/camera есть; не все Android опции. |
| Передача файлов | SOURCE: AyuAppearanceController и существующие MultipartUpload/download settings | Существующие Swiftgram parallel options. Скорость не измерялась, server limits не обходятся. |

## Ещё отсутствующие ключевые функции

Эти пункты не становятся готовыми из-за похожего переключателя или строки локализации.
Android/Desktop имеют разные наборы функций; точная APK parity требует runtime-сравнения.

- **H06/H14/H17–H21:** archive auto-download с Wi-Fi/cellular лимитами, «удалить у всех,
  оставить себе», совместимые SQLite backups, удержание cache после kick/ban/session
  termination, сохранение наблюдаемых read-time/last-seen данных.
- **F02–F06:** reversed rules, per-chat/shared/type policies и исключения, local
  shadow-ban, временное раскрытие скрытого в чате, import/export/diff фильтров.
- **C03/C05/C08–C13:** повторное открытие одноразовых/TTL media, полная peer-ID
  search/copy система, repeat/send-as-sticker, массовое удаление своих сообщений,
  весь набор sticker/GIF/voice/video confirmations, callback-data copy, выбор всех
  Ayu translator providers и актуальный AyuSync.
- **C02/C04/C06/H10–H13:** все специальные forwarding types и редактор копии,
  полный Message Details, настраиваемый Message Shot, rich archive rendering,
  reaction revisions, opacity/custom deleted/edited marks.
- **U01–U06/U09/U12–U16:** полный набор Ayu hiding/decorations/counters/folders,
  bubble/font controls, channel bottom button, seconds/notification timing,
  picker/recents, webview behavior, оригинальная supporter/crash-reporting
  инфраструктура. Часть есть в базе Swiftgram, но соответствие каждой Ayu опции
  не подтверждено и отдельный полный перенос не объявляется.

## Платформенные ограничения

- **P01:** Android foreground service/FCM не переносится на iOS. Нужны APNs и
  разрешённые background modes; система может приостановить процесс. Архив не
  восстановит сообщение, которое клиент не получил.
- **P02:** retained files находятся в контейнере; Files/document picker заменяет
  произвольный Android storage path. JSON backup не является SQLite/WAL переносом.
- **P03:** tray/taskbar/Ctrl-Shift/macOS pressure trackpad не имеют прямого эквивалента
  на iPhone. Добавленный ghost app shortcut не является desktop tray.
- **C01/U11:** локальное оформление не даёт серверный Premium; публичный iOS capture
  API не гарантирует предотвращение screenshots и может сообщить о записи с задержкой.
- **P04:** нужны собственные API application, Bundle ID и подпись. APK — бинарный
  artifact: revision `6029a7f` не найден в проверенном public Android tree, а старый
  Android source ссылается на отсутствующий proprietary submodule. Это не доказательство
  идентичности публичных исходников APK 2026 года.

## Куда вводить api_id и api_hash

GitHub: [Settings → Secrets and variables → Actions](https://github.com/nabivkubkov-prog/Ayugram-iOS/settings/secrets/actions)
→ **New repository secret**:

| Secret | Значение |
| --- | --- |
| `RUFATGRAM_API_ID` | Свой `api_id` из [my.telegram.org/apps](https://my.telegram.org/apps), положительное число. |
| `RUFATGRAM_API_HASH` | Свой `api_hash`, 32 hex-символа. |
| `RUFATGRAM_TEAM_ID`, `RUFATGRAM_BUNDLE_ID` | Собственные Apple team/bundle для signed build. |
| `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD` | Сертификат и пароли для signed workflow. |
| `PROVISIONING_PROFILE_BASE64` либо `PROFILES_JSON_BASE64` | Профили приложения и extensions/capabilities. |

[prepare-configuration.py](../tools/ci/prepare-configuration.py) подставляет credentials
в генерируемую непубликуемую конфигурацию; Swift-файлы редактировать не нужно.
После добавления Secrets нужна новая сборка. Compile-only placeholder artifact не
сможет войти в Telegram; unsigned IPA требует последующей подписи.
