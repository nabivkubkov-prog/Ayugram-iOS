import AccountContext
import Display
import Foundation
import ItemListUI
import Postbox
import PresentationDataUtils
import SGItemListUI
import SGSimpleSettings
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit
import UniformTypeIdentifiers

private enum AyuHistorySection: Int32, SGItemListSection {
    case options
    case search
    case records
    case actions
}

private enum AyuHistoryToggle: String {
    case saveEdits
    case saveMedia
    case onlySelected
}

private enum AyuHistoryAction: Hashable {
    case record(String)
    case exportJSON
    case importJSON
    case clear
    case loadMore
    case mediaLimit
    case editSelection
    case chatTypes
}

private typealias AyuHistoryEntry = SGItemListUIEntry<AyuHistorySection, AyuHistoryToggle, AnyHashable, AnyHashable, AnyHashable, AyuHistoryAction>

private struct AyuHistoryUIState: Equatable {
    var query = ""
    var count = 100
    var revision = 0
}

private func ayuHistoryText(_ russian: Bool, _ english: String, _ russianText: String) -> String {
    return russian ? russianText : english
}

private final class AyuHistoryActions: NSObject, UIDocumentPickerDelegate {
    let context: AccountContext
    weak var controller: ViewController?
    let state = ValuePromise(AyuHistoryUIState(), ignoreRepeated: true)
    var currentState = AyuHistoryUIState()
    var records: [AyuHistoryRecord] = []
    private let operation = MetaDisposable()

    init(context: AccountContext) {
        self.context = context
        super.init()
    }

    deinit {
        operation.dispose()
    }

    var russian: Bool {
        return context.sharedContext.currentPresentationData.with { $0.strings.baseLanguageCode.hasPrefix("ru") }
    }

    func refresh() {
        currentState.revision += 1
        state.set(currentState)
    }

    func message(_ title: String, _ text: String) {
        controller?.present(textAlertController(context: context, title: title, text: text, actions: [TextAlertAction(type: .defaultAction, title: "OK", action: {})]), in: .window(.root))
    }

    private func share(_ items: [Any], from sourceController: ViewController? = nil, completion: (() -> Void)? = nil) {
        guard let controller = sourceController ?? controller else { return }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = controller.view
        activity.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
        activity.completionWithItemsHandler = { _, _, _, _ in completion?() }
        controller.present(activity, animated: true)
    }

    func perform(_ action: AyuHistoryAction) {
        switch action {
        case let .record(id):
            guard let record = records.first(where: { $0.id == id }) else { return }
            show(record)
        case .loadMore:
            currentState.count += 100
            state.set(currentState)
        case .mediaLimit:
            let choices: [Int32] = [256, 1024, 4096, 0]
            var actions = choices.map { value in
                TextAlertAction(type: .genericAction, title: value == 0 ? ayuHistoryText(russian, "No limit", "Без ограничения") : "\(value) MB", action: { [weak self] in
                    SGSimpleSettings.shared.archiveMediaLimitMB = value
                    self?.refresh()
                })
            }
            actions.append(TextAlertAction(type: .genericAction, title: ayuHistoryText(russian, "Cancel", "Отмена"), action: {}))
            controller?.present(textAlertController(context: context, title: ayuHistoryText(russian, "Retained attachment limit", "Лимит сохранённых вложений"), text: ayuHistoryText(russian, "Oldest retained files are removed when new attachments exceed the limit. Message text remains in the archive.", "Старые сохранённые файлы удаляются при добавлении вложений сверх лимита. Текст сообщений остаётся в архиве."), actions: actions, actionLayout: .vertical), in: .window(.root))
        case .editSelection:
            editSelection()
        case .chatTypes:
            controller?.push(ayuHistoryChatRulesController(context: context))
        case .exportJSON:
            exportJSON()
        case .importJSON:
            let picker: UIDocumentPickerViewController
            if #available(iOS 14.0, *) {
                picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
            } else {
                picker = UIDocumentPickerViewController(documentTypes: ["public.json"], in: .import)
            }
            picker.delegate = self
            picker.allowsMultipleSelection = false
            controller?.present(picker, animated: true)
        case .clear:
            let matching = records.filter { $0.matches(query: currentState.query) }
            guard !matching.isEmpty else { return }
            controller?.present(textAlertController(context: context, title: ayuHistoryText(russian, "Clear archive", "Очистить архив"), text: ayuHistoryText(russian, "Delete \(matching.count) matching archive records and their retained attachments? Telegram messages and other accounts will not be affected.", "Удалить найденные записи архива (\(matching.count)) и их сохранённые вложения? Сообщения Telegram и другие аккаунты не затрагиваются."), actions: [
                TextAlertAction(type: .genericAction, title: ayuHistoryText(russian, "Cancel", "Отмена"), action: {}),
                TextAlertAction(type: .destructiveAction, title: ayuHistoryText(russian, "Delete", "Удалить"), action: { [weak self] in
                    guard let self = self else { return }
                    self.operation.set((AyuHistoryStore.remove(postbox: self.context.account.postbox, recordIds: Set(matching.map(\.id))) |> deliverOnMainQueue).start(next: { [weak self] success in
                        guard let self = self, !success else { return }
                        self.message("AyuGram", ayuHistoryText(self.russian, "Some attachment files could not be removed. Their archive records were kept so you can retry.", "Некоторые вложения не удалось удалить. Их записи сохранены в архиве, чтобы можно было повторить попытку."))
                    }))
                })
            ]), in: .window(.root))
        }
    }

    private func show(_ record: AyuHistoryRecord) {
        controller?.push(ayuHistoryDetailController(context: context, record: record, action: { [weak self] action, source in
            guard let self = self else { return }
            switch action {
            case 100:
                UIPasteboard.general.string = record.text
            case 101:
                let files = record.attachments.compactMap { AyuHistoryStore.attachmentURL(mediaBox: self.context.account.postbox.mediaBox, attachment: $0) }
                if !files.isEmpty { self.share(files, from: source) }
            default:
                self.toggleSelection(peerId: record.peerId, peerName: record.peerName, from: source)
            }
        }))
    }

    private func toggleSelection(peerId: Int64, peerName: String, from sourceController: ViewController) {
        let key = "\(context.account.peerId.toInt64()):\(peerId)"
        let selected = SGSimpleSettings.shared.archiveExcludedPeerIds.contains(key)
        let onlySelected = SGSimpleSettings.shared.archiveOnlySelected
        let actionTitle = selected ? ayuHistoryText(russian, "Remove from list", "Удалить из списка") : ayuHistoryText(russian, "Add to list", "Добавить в список")
        sourceController.present(textAlertController(context: context, title: peerName, text: onlySelected ? ayuHistoryText(russian, "Only chats on this list are saved.", "Сохраняются только чаты из этого списка.") : ayuHistoryText(russian, "Chats on this list are excluded from saving.", "Чаты из этого списка исключены из сохранения."), actions: [
            TextAlertAction(type: .genericAction, title: ayuHistoryText(russian, "Cancel", "Отмена"), action: {}),
            TextAlertAction(type: .defaultAction, title: actionTitle, action: { [weak self] in
                var entries = SGSimpleSettings.shared.archiveExcludedPeerIds
                if selected { entries.removeAll(where: { $0 == key }) } else { entries.append(key) }
                SGSimpleSettings.shared.archiveExcludedPeerIds = entries
                self?.refresh()
            })
        ]), in: .window(.root))
    }

    private func editSelection() {
        let accountPrefix = "\(context.account.peerId.toInt64()):"
        let selected = SGSimpleSettings.shared.archiveExcludedPeerIds.filter { $0.hasPrefix(accountPrefix) }.map { String($0.dropFirst(accountPrefix.count)) }
        let alert = UIAlertController(title: ayuHistoryText(russian, "Chat IDs", "ID чатов"), message: ayuHistoryText(russian, "Comma-separated internal chat IDs. Open an archive entry to see its ID or set its rule directly. This list applies only to the current account.", "Внутренние ID чатов через запятую. ID и правило чата доступны в записи архива. Список действует только для текущего аккаунта."), preferredStyle: .alert)
        alert.addTextField { field in
            field.text = selected.joined(separator: ", ")
            field.placeholder = "123456789, 858993459200001"
            field.keyboardType = .numbersAndPunctuation
        }
        alert.addAction(UIAlertAction(title: ayuHistoryText(russian, "Cancel", "Отмена"), style: .cancel))
        alert.addAction(UIAlertAction(title: ayuHistoryText(russian, "Save", "Сохранить"), style: .default, handler: { [weak self, weak alert] _ in
            guard let self = self, let value = alert?.textFields?.first?.text else { return }
            let pieces = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard pieces.allSatisfy({ Int64($0) != nil }) else {
                DispatchQueue.main.async { self.message("AyuGram", ayuHistoryText(self.russian, "Every ID must be a whole number.", "Каждый ID должен быть целым числом.")) }
                return
            }
            var entries = SGSimpleSettings.shared.archiveExcludedPeerIds.filter { !$0.hasPrefix(accountPrefix) }
            entries.append(contentsOf: Set(pieces.compactMap(Int64.init)).map { accountPrefix + String($0) })
            SGSimpleSettings.shared.archiveExcludedPeerIds = entries
            self.refresh()
        }))
        controller?.present(alert, animated: true)
    }

    private func exportJSON() {
        let selected = records.filter { $0.matches(query: currentState.query) }
        do {
            let data = try AyuHistoryBackup(records: selected).encoded()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("AyuGram-history-\(UUID().uuidString).json")
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            share([url], completion: { try? FileManager.default.removeItem(at: url) })
        } catch {
            message("AyuGram", error.localizedDescription)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let accountId = context.account.peerId.toInt64()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= AyuHistoryBackup.maximumBytes else { throw AyuHistoryBackupError.tooLarge }
                let backup = try AyuHistoryBackup.decoded(Data(contentsOf: url), accountId: accountId)
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.controller?.present(textAlertController(context: self.context, title: ayuHistoryText(self.russian, "Import history", "Импорт истории"), text: ayuHistoryText(self.russian, "Merge \(backup.records.count) records? Duplicates are skipped. JSON backups do not contain attachment files.", "Объединить записи (\(backup.records.count)) с архивом? Дубликаты пропускаются. JSON-копии не содержат файлов вложений."), actions: [
                        TextAlertAction(type: .genericAction, title: ayuHistoryText(self.russian, "Cancel", "Отмена"), action: {}),
                        TextAlertAction(type: .defaultAction, title: ayuHistoryText(self.russian, "Import", "Импортировать"), action: { [weak self] in
                            guard let self = self else { return }
                            self.operation.set((AyuHistoryStore.merge(postbox: self.context.account.postbox, accountId: accountId, backup: backup) |> deliverOnMainQueue).start(next: { [weak self] count in
                                guard let self = self else { return }
                                self.message("AyuGram", ayuHistoryText(self.russian, "Imported \(count) records.", "Импортировано записей: \(count)."))
                            }))
                        })
                    ]), in: .window(.root))
                }
            } catch {
                DispatchQueue.main.async { self?.message("AyuGram", error.localizedDescription) }
            }
        }
    }
}

public func ayuHistoryController(context: AccountContext, messageId: MessageId? = nil, peerId: PeerId? = nil) -> ViewController {
    let actions = AyuHistoryActions(context: context)
    let arguments = SGItemListArguments<AyuHistoryToggle, AnyHashable, AnyHashable, AnyHashable, AyuHistoryAction>(context: context, setBoolValue: { setting, value in
        switch setting {
        case .saveEdits: SGSimpleSettings.shared.saveEditHistory = value
        case .saveMedia: SGSimpleSettings.shared.saveHistoryMedia = value
        case .onlySelected: SGSimpleSettings.shared.archiveOnlySelected = value
        }
        actions.refresh()
    }, action: { actions.perform($0) }, searchInput: { query in
        actions.currentState.query = query
        actions.currentState.count = 100
        actions.state.set(actions.currentState)
    })

    let signal = combineLatest(AyuHistoryStore.records(postbox: context.account.postbox), actions.state.get(), context.sharedContext.presentationData)
    |> deliverOnMainQueue
    |> map { records, state, presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let russian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let settings = SGSimpleSettings.shared
        actions.records = records.filter { record in
            guard record.accountId == context.account.peerId.toInt64() else { return false }
            if let messageId = messageId {
                return record.peerId == messageId.peerId.toInt64() && record.namespace == messageId.namespace && record.messageId == messageId.id
            }
            if let peerId = peerId { return record.peerId == peerId.toInt64() }
            return true
        }
        let matching = actions.records.filter { $0.matches(query: state.query) }
        var entries: [AyuHistoryEntry] = []
        let id = SGItemListCounter()
        entries.append(.header(id: id.count, section: .options, text: ayuHistoryText(russian, "MESSAGE ARCHIVE", "АРХИВ СООБЩЕНИЙ"), badge: nil))
        entries.append(.toggle(id: id.count, section: .options, settingName: .saveEdits, value: settings.saveEditHistory, text: ayuHistoryText(russian, "Save edit history", "Сохранять историю правок"), enabled: true))
        entries.append(.toggle(id: id.count, section: .options, settingName: .saveMedia, value: settings.saveHistoryMedia, text: ayuHistoryText(russian, "Retain downloaded attachments", "Сохранять загруженные вложения"), enabled: true))
        entries.append(.toggle(id: id.count, section: .options, settingName: .onlySelected, value: settings.archiveOnlySelected, text: ayuHistoryText(russian, "Save only selected chats", "Сохранять только выбранные чаты"), enabled: true))
        entries.append(.action(id: id.count, section: .options, actionType: .editSelection, text: settings.archiveOnlySelected ? ayuHistoryText(russian, "Selected chats", "Выбранные чаты") : ayuHistoryText(russian, "Excluded chats", "Исключённые чаты"), kind: .generic))
        entries.append(.action(id: id.count, section: .options, actionType: .chatTypes, text: ayuHistoryText(russian, "Chat types and bots", "Типы чатов и боты"), kind: .generic))
        entries.append(.action(id: id.count, section: .options, actionType: .mediaLimit, text: ayuHistoryText(russian, "Attachment limit: ", "Лимит вложений: ") + (settings.archiveMediaLimitMB == 0 ? ayuHistoryText(russian, "none", "нет") : "\(settings.archiveMediaLimitMB) MB"), kind: .generic))
        entries.append(.notice(id: id.count, section: .options, text: ayuHistoryText(russian, "This archive survives Telegram media-cache clearing. Only messages observed by this device can be saved. Attachments must already be downloaded; secret chats and timed messages are excluded. JSON export contains text and metadata, not attachment files.", "Архив сохраняется после очистки медиакэша Telegram. Можно сохранить только сообщения, полученные этим устройством. Вложения должны быть уже загружены; секретные чаты и сообщения с таймером исключены. JSON-экспорт содержит текст и метаданные, без файлов вложений.")))
        if settings.archiveOnlySelected && !settings.archiveExcludedPeerIds.contains(where: { $0.hasPrefix("\(context.account.peerId.toInt64()):") }) {
            entries.append(.notice(id: id.count, section: .options, text: ayuHistoryText(russian, "Nothing will be saved until you add a chat to the selected list.", "Ничего не сохраняется, пока вы не добавите чат в список выбранных.")))
        }
        entries.append(.searchInput(id: id.count, section: .search, title: NSAttributedString(string: ""), text: state.query, placeholder: ayuHistoryText(russian, "Text, sender, chat or ID", "Текст, автор, чат или ID")))
        entries.append(.header(id: id.count, section: .records, text: ayuHistoryText(russian, "RECORDS: \(matching.count)", "ЗАПИСЕЙ: \(matching.count)"), badge: nil))
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        for record in matching.prefix(state.count) {
            let kind = record.kind == .edited ? ayuHistoryText(russian, "Edit", "Правка") : ayuHistoryText(russian, "Deleted", "Удалено")
            let preview = record.text.isEmpty ? ayuHistoryText(russian, "Attachment", "Вложение") : String(record.text.replacingOccurrences(of: "\n", with: " ").prefix(100))
            let title = "\(kind) · \(record.peerName) · \(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(record.capturedAt))))\n\(preview)"
            entries.append(.action(id: id.count, section: .records, actionType: .record(record.id), text: title, kind: .generic))
        }
        if matching.isEmpty {
            entries.append(.notice(id: id.count, section: .records, text: ayuHistoryText(russian, "No matching archived messages yet.", "Подходящих записей в архиве пока нет.")))
        } else if matching.count > state.count {
            entries.append(.action(id: id.count, section: .records, actionType: .loadMore, text: ayuHistoryText(russian, "Show 100 more", "Показать ещё 100"), kind: .generic))
        }
        entries.append(.action(id: id.count, section: .actions, actionType: .exportJSON, text: ayuHistoryText(russian, "Export matching records (JSON)", "Экспорт найденных записей (JSON)"), kind: .generic))
        entries.append(.action(id: id.count, section: .actions, actionType: .importJSON, text: ayuHistoryText(russian, "Import JSON history", "Импорт истории из JSON"), kind: .generic))
        entries.append(.action(id: id.count, section: .actions, actionType: .clear, text: ayuHistoryText(russian, "Clear matching archive records", "Удалить найденные записи архива"), kind: .destructive))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ayuHistoryText(russian, "Message Archive", "Архив сообщений")), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    actions.controller = controller
    return controller
}

private enum AyuHistoryDetailEntry: ItemListNodeEntry {
    case text(Int, String)
    case action(Int, String)

    var stableId: Int {
        switch self { case let .text(id, _), let .action(id, _): return id }
    }

    var section: ItemListSectionId { return stableId < 100 ? 0 : 1 }

    static func < (lhs: Self, rhs: Self) -> Bool { return lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .text(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        case let .action(id, title):
            let action = arguments as! (Int) -> Void
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: { action(id) })
        }
    }
}

private func ayuHistoryDetailController(context: AccountContext, record: AyuHistoryRecord, action: @escaping (Int, ViewController) -> Void) -> ViewController {
    weak var controller: ViewController?
    let handler: (Int) -> Void = { id in
        if let controller = controller { action(id, controller) }
    }
    let signal = context.sharedContext.presentationData |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let russian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let date = DateFormatter.localizedString(from: Date(timeIntervalSince1970: TimeInterval(record.capturedAt)), dateStyle: .medium, timeStyle: .medium)
        let originalDate = DateFormatter.localizedString(from: Date(timeIntervalSince1970: TimeInterval(record.originalTimestamp)), dateStyle: .medium, timeStyle: .medium)
        let available = record.attachments.filter { AyuHistoryStore.attachmentURL(mediaBox: context.account.postbox.mediaBox, attachment: $0) != nil }.count
        var entries: [AyuHistoryDetailEntry] = [
            .text(1, "\(record.peerName)\n\(record.authorName)\n" + ayuHistoryText(russian, "Original: \(originalDate)\nSaved: \(date)", "Отправлено: \(originalDate)\nСохранено: \(date)")),
            .text(2, "ID: \(record.peerId) / \(record.namespace) / \(record.messageId)"),
            .text(3, record.text.isEmpty ? ayuHistoryText(russian, "Message without text", "Сообщение без текста") : record.text),
            .text(4, ayuHistoryText(russian, "Retained attachments: \(available) / \(record.attachments.count)", "Сохранённые вложения: \(available) / \(record.attachments.count)")),
            .action(100, ayuHistoryText(russian, "Copy text", "Копировать текст"))
        ]
        if available > 0 { entries.append(.action(101, ayuHistoryText(russian, "Open / share attachments", "Открыть / поделиться вложениями"))) }
        entries.append(.action(102, ayuHistoryText(russian, "Chat saving rule", "Правило сохранения чата")))
        let title = record.kind == .edited ? ayuHistoryText(russian, "Previous Revision", "Предыдущая версия") : ayuHistoryText(russian, "Deleted Message", "Удалённое сообщение")
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, handler))
    }
    let result = ItemListController(context: context, state: signal)
    controller = result
    return result
}

private enum AyuHistoryChatRuleToggle: Hashable {
    case messages(AyuHistoryChatCategory)
    case media(AyuHistoryChatCategory)
    case botDialogs
    case botMessages
}

private func ayuHistoryChatRulesController(context: AccountContext) -> ViewController {
    typealias Entry = SGItemListUIEntry<AyuHistorySection, AyuHistoryChatRuleToggle, AnyHashable, AnyHashable, AnyHashable, AnyHashable>
    let refresh = ValuePromise(0, ignoreRepeated: false)
    let accountId = context.account.peerId.toInt64()
    let arguments = SGItemListArguments<AyuHistoryChatRuleToggle, AnyHashable, AnyHashable, AnyHashable, AnyHashable>(context: context, setBoolValue: { toggle, value in
        AyuHistoryStore.updateChatRules(accountId: accountId) { rules in
            switch toggle {
            case let .messages(category):
                if value { rules.excludedMessageTypes.remove(category) } else { rules.excludedMessageTypes.insert(category) }
            case let .media(category):
                if value { rules.excludedMediaTypes.remove(category) } else { rules.excludedMediaTypes.insert(category) }
            case .botDialogs: rules.saveBotDialogs = value
            case .botMessages: rules.saveBotMessagesInGroups = value
            }
        }
        refresh.set(0)
    })
    let signal = combineLatest(refresh.get(), context.sharedContext.presentationData) |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let russian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let rules = AyuHistoryStore.chatRules(accountId: accountId)
        let categories: [(AyuHistoryChatCategory, String)] = [
            (.privateChat, ayuHistoryText(russian, "Private chats", "Личные чаты")),
            (.publicChannel, ayuHistoryText(russian, "Public channels", "Публичные каналы")),
            (.privateChannel, ayuHistoryText(russian, "Private channels", "Приватные каналы")),
            (.publicGroup, ayuHistoryText(russian, "Public groups", "Публичные группы")),
            (.privateGroup, ayuHistoryText(russian, "Private groups", "Приватные группы"))
        ]
        let id = SGItemListCounter()
        var entries: [Entry] = [.header(id: id.count, section: .options, text: ayuHistoryText(russian, "SAVE MESSAGE HISTORY", "СОХРАНЯТЬ ИСТОРИЮ СООБЩЕНИЙ"), badge: nil)]
        for (category, title) in categories {
            entries.append(.toggle(id: id.count, section: .options, settingName: .messages(category), value: !rules.excludedMessageTypes.contains(category), text: title, enabled: true))
        }
        entries.append(.header(id: id.count, section: .search, text: ayuHistoryText(russian, "RETAIN DOWNLOADED ATTACHMENTS", "СОХРАНЯТЬ ЗАГРУЖЕННЫЕ ВЛОЖЕНИЯ"), badge: nil))
        for (category, title) in categories {
            entries.append(.toggle(id: id.count, section: .search, settingName: .media(category), value: !rules.excludedMediaTypes.contains(category), text: title, enabled: true))
        }
        entries.append(.header(id: id.count, section: .records, text: ayuHistoryText(russian, "BOTS", "БОТЫ"), badge: nil))
        entries.append(.toggle(id: id.count, section: .records, settingName: .botDialogs, value: rules.saveBotDialogs, text: ayuHistoryText(russian, "Save bot dialogs", "Сохранять диалоги с ботами"), enabled: true))
        entries.append(.toggle(id: id.count, section: .records, settingName: .botMessages, value: rules.saveBotMessagesInGroups, text: ayuHistoryText(russian, "Save bot messages in groups", "Сохранять сообщения ботов в группах"), enabled: true))
        entries.append(.notice(id: id.count, section: .actions, text: ayuHistoryText(russian, "These rules apply to this account. The main saving switches and per-chat inclusion/exclusion list still apply.", "Правила действуют для текущего аккаунта. Основные переключатели сохранения и список включённых/исключённых чатов также учитываются.")))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ayuHistoryText(russian, "Chat Types and Bots", "Типы чатов и боты")), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }
    return ItemListController(context: context, state: signal)
}
