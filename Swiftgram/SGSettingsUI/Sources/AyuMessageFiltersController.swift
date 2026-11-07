import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGItemListUI
import SGSimpleSettings

private enum AyuFilterSection: Int32, SGItemListSection {
    case general
    case editor
    case rules
}

private enum AyuFilterToggle: Hashable {
    case enabled
    case sponsored
    case blocked
    case regex
    case caseSensitive
    case rule(String)
}

private enum AyuFilterAction: Hashable {
    case save
    case cancelEdit
    case edit(String)
    case delete(String)
}

private typealias AyuFilterEntry = SGItemListUIEntry<AyuFilterSection, AyuFilterToggle, AnyHashable, AnyHashable, AnyHashable, AyuFilterAction>

public func ayuMessageFiltersController(context: AccountContext) -> ViewController {
    let store = AyuMessageFilterStore.shared
    let changes = ValuePromise(true, ignoreRepeated: false)
    var pattern = ""
    var regex = false
    var caseSensitive = false
    var editingId: String?
    var validationError: String?

    let arguments = SGItemListArguments<AyuFilterToggle, AnyHashable, AnyHashable, AnyHashable, AyuFilterAction>(
        context: context,
        setBoolValue: { setting, value in
            switch setting {
            case .enabled:
                store.update { $0.enabled = value }
            case .sponsored:
                store.update { $0.hideSponsoredMessages = value }
            case .blocked:
                store.update { $0.hideBlockedAuthors = value }
            case .regex:
                regex = value
            case .caseSensitive:
                caseSensitive = value
            case let .rule(id):
                store.update { preferences in
                    if let index = preferences.rules.firstIndex(where: { $0.id == id }) {
                        preferences.rules[index].enabled = value
                    }
                }
            }
            validationError = nil
            changes.set(true)
        },
        action: { action in
            switch action {
            case .save:
                let rule = AyuMessageFilterRule(id: editingId ?? UUID().uuidString, pattern: pattern, isRegularExpression: regex, caseSensitive: caseSensitive)
                if let error = rule.validationError {
                    validationError = error
                } else if editingId == nil && store.preferences.rules.count >= 200 {
                    validationError = "tooMany"
                } else {
                    store.update { preferences in
                        if let index = preferences.rules.firstIndex(where: { $0.id == rule.id }) {
                            var updatedRule = rule
                            updatedRule.enabled = preferences.rules[index].enabled
                            preferences.rules[index] = updatedRule
                        } else {
                            preferences.rules.append(rule)
                        }
                    }
                    pattern = ""
                    editingId = nil
                    validationError = nil
                }
            case .cancelEdit:
                editingId = nil
                pattern = ""
                validationError = nil
            case let .edit(id):
                if let rule = store.preferences.rules.first(where: { $0.id == id }) {
                    editingId = id
                    pattern = rule.pattern
                    regex = rule.isRegularExpression
                    caseSensitive = rule.caseSensitive
                    validationError = nil
                }
            case let .delete(id):
                store.update { $0.rules.removeAll(where: { $0.id == id }) }
                if editingId == id {
                    editingId = nil
                    pattern = ""
                }
            }
            changes.set(true)
        },
        searchInput: { value in
            pattern = value
            validationError = nil
        }
    )

    let signal = combineLatest(changes.get(), context.sharedContext.presentationData)
    |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let russian = presentationData.strings.baseLanguageCode == "ru"
        func text(_ en: String, _ ru: String) -> String { return russian ? ru : en }
        let preferences = store.preferences
        let id = SGItemListCounter()
        var entries: [AyuFilterEntry] = []
        entries.append(.header(id: id.count, section: .general, text: text("MESSAGE FILTERS", "ФИЛЬТРЫ СООБЩЕНИЙ"), badge: nil))
        entries.append(.toggle(id: id.count, section: .general, settingName: .enabled, value: preferences.enabled, text: text("Enable filters", "Включить фильтры"), enabled: true))
        entries.append(.toggle(id: id.count, section: .general, settingName: .sponsored, value: preferences.hideSponsoredMessages, text: text("Hide sponsored messages", "Скрывать рекламу Telegram"), enabled: preferences.enabled))
        entries.append(.toggle(id: id.count, section: .general, settingName: .blocked, value: preferences.hideBlockedAuthors, text: text("Hide blocked users' messages", "Скрывать сообщения заблокированных"), enabled: preferences.enabled))
        entries.append(.notice(id: id.count, section: .general, text: text("Matching incoming messages are hidden in chats. Your own messages and service messages stay visible. Turn filters off to see hidden messages again. Existing keyword dimming remains separate.", "Совпавшие входящие сообщения скрываются в чатах. Ваши и служебные сообщения остаются видимыми. Отключите фильтры, чтобы снова увидеть скрытое. Прежнее затемнение по ключевым словам работает отдельно.")))
        entries.append(.header(id: id.count, section: .editor, text: editingId == nil ? text("ADD RULE", "ДОБАВИТЬ ПРАВИЛО") : text("EDIT RULE", "ИЗМЕНИТЬ ПРАВИЛО"), badge: nil))
        entries.append(.searchInput(id: id.count, section: .editor, title: NSAttributedString(string: ""), text: pattern, placeholder: text("Text or regular expression", "Текст или регулярное выражение")))
        entries.append(.toggle(id: id.count, section: .editor, settingName: .regex, value: regex, text: text("Regular expression", "Регулярное выражение"), enabled: true))
        entries.append(.toggle(id: id.count, section: .editor, settingName: .caseSensitive, value: caseSensitive, text: text("Case sensitive", "Учитывать регистр"), enabled: true))
        if let error = validationError {
            let message: String
            switch error {
            case "empty": message = text("Enter a non-empty rule.", "Введите непустое правило.")
            case "tooLong": message = text("The rule is too long (maximum 2048 UTF-16 units).", "Правило слишком длинное (максимум 2048 единиц UTF-16).")
            case "tooMany": message = text("The limit is 200 rules. Remove a rule first.", "Достигнут предел в 200 правил. Сначала удалите одно из них.")
            default: message = text("Invalid regular expression. Check brackets and escapes.", "Некорректное регулярное выражение. Проверьте скобки и экранирование.")
            }
            entries.append(.notice(id: id.count, section: .editor, text: message))
        }
        entries.append(.action(id: id.count, section: .editor, actionType: .save, text: editingId == nil ? text("Add rule", "Добавить правило") : text("Save rule", "Сохранить правило"), kind: .generic))
        if editingId != nil {
            entries.append(.action(id: id.count, section: .editor, actionType: .cancelEdit, text: text("Cancel editing", "Отменить редактирование"), kind: .generic))
        }
        entries.append(.header(id: id.count, section: .rules, text: text("RULES", "ПРАВИЛА"), badge: nil))
        for rule in preferences.rules {
            let label = (rule.isRegularExpression ? "/\(rule.pattern)/" : rule.pattern)
            entries.append(.toggle(id: id.count, section: .rules, settingName: .rule(rule.id), value: rule.enabled, text: label, enabled: preferences.enabled))
            entries.append(.action(id: id.count, section: .rules, actionType: .edit(rule.id), text: text("Edit", "Изменить"), kind: .generic))
            entries.append(.action(id: id.count, section: .rules, actionType: .delete(rule.id), text: text("Delete", "Удалить"), kind: .destructive))
        }
        if preferences.rules.isEmpty {
            entries.append(.notice(id: id.count, section: .rules, text: text("No text filters yet.", "Текстовых фильтров пока нет.")))
        }
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(text("Message Filters", "Фильтры сообщений")), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let list = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (state, (list, arguments))
    }
    return ItemListController(context: context, state: signal)
}
