import Foundation
import Postbox
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGItemListUI
import SGSimpleSettings

private enum AyuAppearanceSection: Int32, SGItemListSection {
    case local
    case streamer
    case interface
    case menu
    case transfers
}

private enum AyuAppearanceToggle: Hashable {
    case localPremium
    case streamer
    case hideChatList
    case fasterDownloads
    case simple(SGSimpleSettings.Keys)
}

private enum AyuAppearanceAction: Hashable {
    case clearLocalStatus
}

private struct AyuSimpleOption {
    let section: AyuAppearanceSection
    let key: SGSimpleSettings.Keys
    let path: ReferenceWritableKeyPath<SGSimpleSettings, Bool>
    let en: String
    let ru: String
}

private let ayuSimpleOptions: [AyuSimpleOption] = [
    AyuSimpleOption(section: .interface, key: .hidePhoneInSettings, path: \.hidePhoneInSettings, en: "Hide phone in own profile", ru: "Скрывать номер в своём профиле"),
    AyuSimpleOption(section: .interface, key: .quickTranslateButton, path: \.quickTranslateButton, en: "Quick translation button", ru: "Кнопка быстрого перевода"),
    AyuSimpleOption(section: .interface, key: .disableScrollToNextChannel, path: \.disableScrollToNextChannel, en: "Disable next-channel swipe", ru: "Отключить переход в следующий канал"),
    AyuSimpleOption(section: .interface, key: .disableScrollToNextTopic, path: \.disableScrollToNextTopic, en: "Disable next-topic swipe", ru: "Отключить переход в следующую тему"),
    AyuSimpleOption(section: .interface, key: .disableChatSwipeOptions, path: \.disableChatSwipeOptions, en: "Disable chat swipe actions", ru: "Отключить действия свайпом по чату"),
    AyuSimpleOption(section: .interface, key: .disableDeleteChatSwipeOption, path: \.disableDeleteChatSwipeOption, en: "Remove delete from chat swipe", ru: "Убрать удаление из свайпа по чату"),
    AyuSimpleOption(section: .interface, key: .disableGalleryCamera, path: \.disableGalleryCamera, en: "Hide camera tile in attachments", ru: "Скрыть камеру в меню вложений"),
    AyuSimpleOption(section: .interface, key: .disableSendAsButton, path: \.disableSendAsButton, en: "Hide Send As button", ru: "Скрыть кнопку «Отправить от имени»"),
    AyuSimpleOption(section: .interface, key: .hideRecordingButton, path: \.hideRecordingButton, en: "Hide voice/video recording button", ru: "Скрыть кнопку записи голоса и видео"),
    AyuSimpleOption(section: .interface, key: .forceBuiltInMic, path: \.forceBuiltInMic, en: "Use built-in microphone", ru: "Использовать встроенный микрофон"),
    AyuSimpleOption(section: .interface, key: .forceSystemSharing, path: \.forceSystemSharing, en: "Use system sharing menu", ru: "Использовать системное меню «Поделиться»"),
    AyuSimpleOption(section: .interface, key: .confirmCalls, path: \.confirmCalls, en: "Confirm before calling", ru: "Подтверждать начало звонка"),
    AyuSimpleOption(section: .menu, key: .contextShowSelectFromUser, path: \.contextShowSelectFromUser, en: "Select messages from a user", ru: "Выделение сообщений пользователя"),
    AyuSimpleOption(section: .menu, key: .contextShowSaveToCloud, path: \.contextShowSaveToCloud, en: "Save to Saved Messages", ru: "Сохранение в «Избранное»"),
    AyuSimpleOption(section: .menu, key: .contextShowHideForwardName, path: \.contextShowHideForwardName, en: "Forward without author", ru: "Пересылка без автора"),
    AyuSimpleOption(section: .menu, key: .contextShowJson, path: \.contextShowJson, en: "View message JSON", ru: "Просмотр JSON сообщения"),
    AyuSimpleOption(section: .menu, key: .contextShowRestrict, path: \.contextShowRestrict, en: "Restrict user", ru: "Ограничение пользователя"),
    AyuSimpleOption(section: .menu, key: .contextShowReport, path: \.contextShowReport, en: "Report message", ru: "Жалоба на сообщение"),
    AyuSimpleOption(section: .transfers, key: .uploadSpeedBoost, path: \.uploadSpeedBoost, en: "Larger parallel upload parts", ru: "Ускоренная параллельная загрузка")
]

private typealias AyuAppearanceEntry = SGItemListUIEntry<AyuAppearanceSection, AyuAppearanceToggle, AnyHashable, AnyHashable, AnyHashable, AyuAppearanceAction>

public func ayuAppearanceController(context: AccountContext) -> ViewController {
    let changes = ValuePromise(true, ignoreRepeated: false)
    let preferences = AyuAppearanceSettings.shared
    let accountId = context.account.peerId.toInt64()
    let arguments = SGItemListArguments<AyuAppearanceToggle, AnyHashable, AnyHashable, AnyHashable, AyuAppearanceAction>(
        context: context,
        setBoolValue: { setting, value in
            switch setting {
            case .localPremium: preferences.localPremium = value
            case .streamer: preferences.streamerMode = value
            case .hideChatList: preferences.hideChatList = value
            case .fasterDownloads:
                SGSimpleSettings.shared.downloadSpeedBoost = (value ? SGSimpleSettings.DownloadSpeedBoostValues.maximum : .none).rawValue
            case let .simple(key):
                if let option = ayuSimpleOptions.first(where: { $0.key == key }) {
                    SGSimpleSettings.shared[keyPath: option.path] = value
                }
            }
            changes.set(true)
        },
        action: { action in
            switch action {
            case .clearLocalStatus: preferences.setLocalEmojiStatus(accountId: accountId, fileId: nil, expiration: nil)
            }
            changes.set(true)
        }
    )
    let signal = combineLatest(changes.get(), context.sharedContext.presentationData)
    |> map { _, data -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let russian = data.strings.baseLanguageCode == "ru"
        func text(_ en: String, _ ru: String) -> String { return russian ? ru : en }
        let id = SGItemListCounter()
        var entries: [AyuAppearanceEntry] = []
        entries.append(.header(id: id.count, section: .local, text: text("LOCAL PREMIUM", "ЛОКАЛЬНЫЙ PREMIUM"), badge: nil))
        entries.append(.toggle(id: id.count, section: .local, settingName: .localPremium, value: preferences.localPremium, text: text("Local Premium appearance", "Локальное оформление Premium"), enabled: true))
        entries.append(.notice(id: id.count, section: .local, text: text("Unlocks bundled app icons and a Premium badge in your own profile on this device. Tap the badge in Settings to choose a local emoji status. Other people do not see this status. Telegram Premium limits, uploads and subscriptions are unchanged.", "Открывает встроенные иконки и значок Premium в своём профиле на этом устройстве. Нажмите значок в настройках, чтобы выбрать локальный эмодзи-статус. Другие пользователи его не видят. Лимиты Telegram Premium, отправка файлов и подписка не меняются.")))
        if preferences.localEmojiStatus(accountId: accountId) != nil {
            entries.append(.action(id: id.count, section: .local, actionType: .clearLocalStatus, text: text("Reset local emoji status", "Сбросить локальный эмодзи-статус"), kind: .generic))
        }
        entries.append(.header(id: id.count, section: .streamer, text: text("STREAMER MODE", "РЕЖИМ СТРИМЕРА"), badge: nil))
        entries.append(.toggle(id: id.count, section: .streamer, settingName: .streamer, value: preferences.streamerMode, text: text("Cover app during screen capture", "Закрывать приложение при записи экрана"), enabled: true))
        entries.append(.toggle(id: id.count, section: .streamer, settingName: .hideChatList, value: preferences.hideChatList, text: text("Always mask chat list rows", "Всегда скрывать строки списка чатов"), enabled: true))
        entries.append(.notice(id: id.count, section: .streamer, text: text("Screen recording or mirroring covers the whole app until capture stops; the app switcher is covered too. Chat-list masking also hides VoiceOver previews. Open chats remain visible when capture is off. Ordinary screenshots and system notifications cannot be hidden by this mode; capture detection may be delayed by iOS.", "При записи или трансляции экрана приложение закрыто до остановки захвата; превью в переключателе приложений тоже скрыто. Маска списка чатов скрывает и превью VoiceOver. Без записи открытый чат виден. Обычные скриншоты и системные уведомления этот режим не скрывает; iOS может сообщить о записи с задержкой.")))
        for section in [AyuAppearanceSection.interface, .menu, .transfers] {
            let title: String
            switch section {
            case .interface: title = text("INTERFACE", "ИНТЕРФЕЙС")
            case .menu: title = text("MESSAGE MENU", "МЕНЮ СООБЩЕНИЙ")
            default: title = text("TRANSFERS", "ПЕРЕДАЧА ФАЙЛОВ")
            }
            entries.append(.header(id: id.count, section: section, text: title, badge: nil))
            for option in ayuSimpleOptions where option.section == section {
                entries.append(.toggle(id: id.count, section: section, settingName: .simple(option.key), value: SGSimpleSettings.shared[keyPath: option.path], text: text(option.en, option.ru), enabled: true))
            }
            if section == .transfers {
                entries.append(.toggle(id: id.count, section: section, settingName: .fasterDownloads, value: SGSimpleSettings.shared.downloadSpeedBoost != SGSimpleSettings.DownloadSpeedBoostValues.none.rawValue, text: text("Parallel downloads", "Параллельное скачивание"), enabled: true))
                entries.append(.notice(id: id.count, section: section, text: text("Transfer settings affect new transfers and do not bypass server limits. Some interface changes require reopening the screen or restarting the app.", "Настройки передачи действуют для новых файлов и не обходят лимиты сервера. Для части настроек интерфейса нужно заново открыть экран или перезапустить приложение.")))
            }
        }
        let state = ItemListControllerState(presentationData: ItemListPresentationData(data), title: .text(text("Local appearance and interface", "Оформление и интерфейс")), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back))
        let list = ItemListNodeState(presentationData: ItemListPresentationData(data), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (state, (list, arguments))
    }
    return ItemListController(context: context, state: signal)
}
