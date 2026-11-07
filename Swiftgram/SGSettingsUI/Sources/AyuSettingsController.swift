import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGSimpleSettings
import SGItemListUI

private enum AyuSection: Int32, SGItemListSection { case ghost, interactions, archive, tools, locks }
private enum AyuToggle: String {
    case global, ghost, reads, online, typing, stories, uploads
    case readOnSend, readOnReaction, readOnPoll, offlineAfterSend, scheduled, silent
    case deleted, edits, media
    case lockReads, lockOnline, lockTyping, lockStories, lockUploads
}
private enum AyuLink: Hashable { case history, filters, chat, appearance }
private typealias AyuEntry = SGItemListUIEntry<AyuSection, AyuToggle, AnyHashable, AnyHashable, AyuLink, AnyHashable>
private func ayuText(_ russian: Bool, _ english: String, _ russianText: String) -> String { return russian ? russianText : english }

public func ayuSettingsController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise(true, ignoreRepeated: false)
    weak var controller: ViewController?
    let accountPath = context.account.basePath
    let arguments = SGItemListArguments<AyuToggle, AnyHashable, AnyHashable, AyuLink, AnyHashable>(context: context, setBoolValue: { key, value in
        let settings = SGSimpleSettings.shared
        switch key {
        case .global: AyuGhostPreferences.shared.useGlobalSettings = value
        case .deleted: settings.keepDeletedMessages = value
        case .edits: settings.saveEditHistory = value
        case .media: settings.saveHistoryMedia = value
        default:
            settings.updateAyuGhostSettings(accountPath: accountPath) { ghost in
                switch key {
                case .ghost: ghost.setEnabled(value)
                case .reads: ghost.hideReadReceipts = value
                case .online: ghost.hideOnline = value
                case .typing: ghost.hideTyping = value
                case .stories: ghost.hideStories = value
                case .uploads: ghost.hideUploadProgress = value
                case .readOnSend: ghost.readOnSend = value
                case .readOnReaction: ghost.readOnReaction = value
                case .readOnPoll: ghost.readOnPoll = value
                case .offlineAfterSend: ghost.offlineAfterSend = value
                case .scheduled: ghost.useScheduledMessages = value
                case .silent: ghost.silentSendInGhostMode = value
                case .lockReads, .lockOnline, .lockTyping, .lockStories, .lockUploads:
                    let option: AyuGhostOption
                    switch key {
                    case .lockReads: option = .readReceipts
                    case .lockOnline: option = .online
                    case .lockTyping: option = .typing
                    case .lockStories: option = .stories
                    default: option = .uploadProgress
                    }
                    if value { ghost.lockedOptions.insert(option) } else { ghost.lockedOptions.remove(option) }
                default: break
                }
            }
        }
        refresh.set(true)
    }, openDisclosureLink: { link in
        switch link {
        case .history: controller?.push(ayuHistoryController(context: context))
        case .filters: controller?.push(ayuMessageFiltersController(context: context))
        case .appearance: controller?.push(ayuAppearanceController(context: context))
        case .chat:
            let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSecretChats, .doNotSearchMessages], hasContactSelector: false, hasGlobalSearch: false))
            picker.peerSelected = { [weak picker] peer, _ in
                picker?.push(ayuChatPrivacyController(context: context, peerId: peer.id, title: peer.debugDisplayTitle))
            }
            controller?.push(picker)
        }
    })
    let signal = combineLatest(refresh.get(), context.sharedContext.presentationData)
    |> map { _, data -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = data.strings.baseLanguageCode.hasPrefix("ru")
        let settings = SGSimpleSettings.shared
        let ghost = settings.ayuGhostSettings(accountPath: accountPath)
        let id = SGItemListCounter()
        var entries: [AyuEntry] = []
        func header(_ section: AyuSection, _ en: String, _ rus: String) {
            entries.append(.header(id: id.count, section: section, text: ayuText(ru, en, rus), badge: nil))
        }
        func toggle(_ section: AyuSection, _ key: AyuToggle, _ value: Bool, _ en: String, _ rus: String) {
            entries.append(.toggle(id: id.count, section: section, settingName: key, value: value, text: ayuText(ru, en, rus), enabled: true))
        }
        header(.ghost, "GHOST MODE", "РЕЖИМ ПРИЗРАКА")
        toggle(.ghost, .global, AyuGhostPreferences.shared.useGlobalSettings, "Same Settings for All Accounts", "Общие настройки для всех аккаунтов")
        toggle(.ghost, .ghost, ghost.isEnabled, "Ghost Mode", "Режим призрака")
        toggle(.ghost, .reads, ghost.hideReadReceipts, "Don't Send Read Receipts", "Не отправлять прочтения")
        toggle(.ghost, .online, ghost.hideOnline, "Don't Send Online Status", "Не показывать «в сети»")
        toggle(.ghost, .typing, ghost.hideTyping, "Don't Send Typing Status", "Не показывать «печатает»")
        toggle(.ghost, .uploads, ghost.hideUploadProgress, "Don't Send Upload Progress", "Скрывать статус загрузки")
        toggle(.ghost, .stories, ghost.hideStories, "Don't Send Story Views", "Не отправлять просмотры историй")
        entries.append(.disclosure(id: id.count, section: .ghost, link: .chat, text: ayuText(ru, "Chat Exceptions and Manual Read", "Исключения для чатов и ручное прочтение")))
        entries.append(.notice(id: id.count, section: .ghost, text: ayuText(ru, "These controls apply to this client. Activity from your other Telegram sessions is independent.", "Настройки действуют в этом клиенте. Активность других сеансов Telegram управляется отдельно.")))
        header(.interactions, "SENDING AND INTERACTIONS", "ОТПРАВКА И ДЕЙСТВИЯ")
        toggle(.interactions, .readOnSend, ghost.readOnSend, "Mark Read When Sending", "Прочитывать при отправке")
        toggle(.interactions, .readOnReaction, ghost.readOnReaction, "Mark Read When Reacting", "Прочитывать при реакции")
        toggle(.interactions, .readOnPoll, ghost.readOnPoll, "Mark Read When Voting", "Прочитывать при голосовании")
        entries.append(.notice(id: id.count, section: .interactions, text: ayuText(ru, "Sending or reacting marks the chat read when you perform the action, even if delivery later fails. Voting marks it read after the server accepts your vote. A chat's Never Send rule takes priority.", "Отправка и реакция отмечают чат прочитанным в момент действия, даже если доставка затем не удастся. Голосование — после принятия голоса сервером. Правило чата «никогда» имеет приоритет.")))
        toggle(.interactions, .offlineAfterSend, ghost.offlineAfterSend, "Restore Offline Status Automatically", "Автоматически возвращаться офлайн")
        toggle(.interactions, .scheduled, ghost.useScheduledMessages, "Scheduled Sending in Ghost Mode", "Отложенная отправка в режиме призрака")
        toggle(.interactions, .silent, ghost.silentSendInGhostMode, "Silent Sending in Ghost Mode", "Без звука в режиме призрака")
        entries.append(.notice(id: id.count, section: .interactions, text: ayuText(ru, "Scheduled sending adds about 11 seconds and keeps manually chosen schedules. It is not used for bots, secret chats, Saved Messages, or paid messages.", "Отложенная отправка добавляет около 11 секунд и сохраняет выбранное вручную время. Не применяется к ботам, секретным чатам, «Избранному» и платным сообщениям.")))
        header(.archive, "MESSAGE HISTORY", "ИСТОРИЯ СООБЩЕНИЙ")
        toggle(.archive, .deleted, settings.keepDeletedMessages, "Save Deleted Messages", "Сохранять удалённые сообщения")
        toggle(.archive, .edits, settings.saveEditHistory, "Save Edit History", "Сохранять историю правок")
        toggle(.archive, .media, settings.saveHistoryMedia, "Retain Downloaded Attachments", "Сохранять загруженные вложения")
        entries.append(.disclosure(id: id.count, section: .archive, link: .history, text: ayuText(ru, "Archive, Search and Backup", "Архив, поиск и резервная копия")))
        entries.append(.notice(id: id.count, section: .archive, text: ayuText(ru, "Only content received by this device can be saved. Archive settings include chat exclusions and a retained-file limit.", "Сохраняется только содержимое, полученное этим устройством. В архиве можно настроить исключения для чатов и лимит вложений.")))
        header(.tools, "MESSAGE FILTERS", "ФИЛЬТРЫ СООБЩЕНИЙ")
        entries.append(.disclosure(id: id.count, section: .tools, link: .filters, text: ayuText(ru, "Filters, Ads and Blocked Users", "Фильтры, реклама и заблокированные")))
        entries.append(.disclosure(id: id.count, section: .tools, link: .appearance, text: ayuText(ru, "Appearance, Local Premium and Streamer Mode", "Оформление, локальный Premium и режим стримера")))
        header(.locks, "LOCK INDIVIDUAL GHOST OPTIONS", "ФИКСАЦИЯ НАСТРОЕК ПРИЗРАКА")
        toggle(.locks, .lockReads, ghost.lockedOptions.contains(.readReceipts), "Keep Read Setting on Master Toggle", "Не менять прочтения общим переключателем")
        toggle(.locks, .lockOnline, ghost.lockedOptions.contains(.online), "Keep Online Setting", "Не менять статус «в сети»")
        toggle(.locks, .lockTyping, ghost.lockedOptions.contains(.typing), "Keep Typing Setting", "Не менять статус «печатает»")
        toggle(.locks, .lockStories, ghost.lockedOptions.contains(.stories), "Keep Story Setting", "Не менять просмотры историй")
        toggle(.locks, .lockUploads, ghost.lockedOptions.contains(.uploadProgress), "Keep Upload Setting", "Не менять статус загрузки")
        return (ItemListControllerState(presentationData: ItemListPresentationData(data), title: .text("AyuGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back)), (ItemListNodeState(presentationData: ItemListPresentationData(data), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil), arguments))
    }
    let result = ItemListController(context: context, state: signal)
    controller = result
    return result
}

private enum AyuChatAction: Hashable { case readRule, typingRule, localRead, serverRead }
private typealias AyuChatEntry = SGItemListUIEntry<AyuSection, AnyHashable, AnyHashable, AnyHashable, AnyHashable, AyuChatAction>

private func ayuChatPrivacyController(context: AccountContext, peerId: PeerId, title: String) -> ViewController {
    let refresh = ValuePromise(true, ignoreRepeated: false)
    weak var controller: ViewController?
    let ru = context.sharedContext.currentPresentationData.with { $0.strings.baseLanguageCode.hasPrefix("ru") }
    let arguments = SGItemListArguments<AnyHashable, AnyHashable, AnyHashable, AnyHashable, AyuChatAction>(context: context, action: { action in
        switch action {
        case .readRule, .typingRule:
            SGSimpleSettings.shared.updateAyuGhostSettings(accountPath: context.account.basePath) { ghost in
                let key = String(peerId.toInt64())
                let old = (action == .readRule ? ghost.readRules[key] : ghost.typingRules[key]) ?? .inherit
                let next: AyuPeerGhostRule = old == .inherit ? .alwaysHide : (old == .alwaysHide ? .alwaysAllow : .inherit)
                if action == .readRule { ghost.readRules[key] = next } else { ghost.typingRules[key] = next }
            }
            refresh.set(true)
        case .localRead:
            let _ = ayuReadChatLocally(account: context.account, peerId: peerId).startStandalone()
        case .serverRead:
            controller?.present(textAlertController(context: context, title: ayuText(ru, "Mark Read on Server?", "Отметить прочитанным на сервере?"), text: ayuText(ru, "The sender will see a read receipt for received messages in this chat.", "Собеседник увидит прочтение полученных сообщений в этом чате."), actions: [
                TextAlertAction(type: .genericAction, title: ayuText(ru, "Cancel", "Отмена"), action: {}),
                TextAlertAction(type: .defaultAction, title: ayuText(ru, "Mark Read", "Прочитать"), action: {
                    let _ = (ayuReadChatOnServer(account: context.account, peerId: peerId) |> deliverOnMainQueue).startStandalone(next: { success in
                        controller?.present(textAlertController(context: context, title: "AyuGram", text: success ? ayuText(ru, "Read receipt sent.", "Прочтение отправлено.") : ayuText(ru, "Could not send the read receipt.", "Не удалось отправить прочтение."), actions: [TextAlertAction(type: .defaultAction, title: "OK", action: {})]), in: .window(.root))
                    })
                })
            ]), in: .window(.root))
        }
    })
    let signal = combineLatest(refresh.get(), context.sharedContext.presentationData) |> map { _, data -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ghost = SGSimpleSettings.shared.ayuGhostSettings(accountPath: context.account.basePath)
        func rule(_ value: AyuPeerGhostRule?) -> String {
            switch value ?? .inherit {
            case .inherit: return ayuText(ru, "Default", "По умолчанию")
            case .alwaysHide: return ayuText(ru, "Never send", "Никогда не отправлять")
            case .alwaysAllow: return ayuText(ru, "Always send", "Всегда отправлять")
            }
        }
        let entries: [AyuChatEntry] = [
            .action(id: 0, section: .ghost, actionType: .readRule, text: ayuText(ru, "Read Receipts: ", "Прочтения: ") + rule(ghost.readRules[String(peerId.toInt64())]), kind: .generic),
            .action(id: 1, section: .ghost, actionType: .typingRule, text: ayuText(ru, "Typing: ", "Набор текста: ") + rule(ghost.typingRules[String(peerId.toInt64())]), kind: .generic),
            .notice(id: 2, section: .ghost, text: ayuText(ru, "Tap a rule to cycle through Default, Never send, and Always send.", "Нажатие переключает правило: по умолчанию → никогда → всегда.")),
            .action(id: 3, section: .tools, actionType: .localRead, text: ayuText(ru, "Mark Read Only on This Device", "Прочитать только на этом устройстве"), kind: .generic),
            .action(id: 4, section: .tools, actionType: .serverRead, text: ayuText(ru, "Mark Read on Telegram Server", "Отправить прочтение на сервер"), kind: .generic)
        ]
        return (ItemListControllerState(presentationData: ItemListPresentationData(data), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back)), (ItemListNodeState(presentationData: ItemListPresentationData(data), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil), arguments))
    }
    let result = ItemListController(context: context, state: signal)
    controller = result
    return result
}
