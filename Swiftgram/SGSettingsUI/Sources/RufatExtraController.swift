// MARK: RufatGram
import SGSimpleSettings

import SGItemListUI
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private enum RufatExtraSection: Int32, SGItemListSection {
    case ghost
    case stories
    case accounts
}

private enum RufatExtraSetting: String {
    case ghostHideReadReceipts
    case ghostHideOnline
    case ghostHideTyping
    case storyStealthMode
}

private typealias RufatExtraEntry = SGItemListUIEntry<RufatExtraSection, RufatExtraSetting, AnyHashable, AnyHashable, AnyHashable, AnyHashable>

private func rufatText(_ lang: String, _ en: String, _ ru: String) -> String {
    return lang == "ru" ? ru : en
}

private func rufatExtraEntries(presentationData: PresentationData) -> [RufatExtraEntry] {
    let lang = presentationData.strings.baseLanguageCode
    let settings = SGSimpleSettings.shared
    var entries: [RufatExtraEntry] = []
    let id = SGItemListCounter()

    entries.append(.header(id: id.count, section: .ghost, text: "GHOST MODE", badge: nil))
    entries.append(.toggle(id: id.count, section: .ghost, settingName: .ghostHideReadReceipts, value: settings.ghostHideReadReceipts, text: rufatText(lang, "Don't Send Read Receipts", "Не отправлять прочтение"), enabled: true))
    entries.append(.toggle(id: id.count, section: .ghost, settingName: .ghostHideOnline, value: settings.ghostHideOnline, text: rufatText(lang, "Don't Send Online Status", "Не показывать «в сети»"), enabled: true))
    entries.append(.toggle(id: id.count, section: .ghost, settingName: .ghostHideTyping, value: settings.ghostHideTyping, text: rufatText(lang, "Don't Send Typing Status", "Не показывать «печатает»"), enabled: true))
    entries.append(.notice(id: id.count, section: .ghost, text: rufatText(lang,
        "Read marks stay on this device only. Sending a message may still mark the chat as read for the sender. Another device of the same account can show you online.",
        "Отметки о прочтении остаются только на этом устройстве. Отправка сообщения может отметить чат прочитанным у собеседника. Другое устройство этого аккаунта может показывать вас «в сети».")))

    entries.append(.header(id: id.count, section: .stories, text: rufatText(lang, "STORIES", "ИСТОРИИ"), badge: nil))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .storyStealthMode, value: settings.storyStealthMode, text: rufatText(lang, "Anonymous Story Viewing", "Анонимный просмотр историй"), enabled: true))
    entries.append(.notice(id: id.count, section: .stories, text: rufatText(lang,
        "The app does not send the \"viewed\" mark for stories.",
        "Приложение не отправляет отметку «просмотрено» для историй.")))

    entries.append(.header(id: id.count, section: .accounts, text: rufatText(lang, "ACCOUNTS", "АККАУНТЫ"), badge: nil))
    entries.append(.notice(id: id.count, section: .accounts, text: rufatText(lang,
        "There is no limit on the number of accounts: add them in Settings → Add Account.",
        "Ограничения на число аккаунтов нет: добавляйте их в Настройки → Добавить аккаунт.")))

    return entries
}

public func rufatExtraController(context: AccountContext) -> ViewController {
    // SGSimpleSettings is UserDefaults-backed and not observable, so changes re-trigger the list manually.
    let simplePromise = ValuePromise(true, ignoreRepeated: false)

    let arguments = SGItemListArguments<RufatExtraSetting, AnyHashable, AnyHashable, AnyHashable, AnyHashable>(
        context: context,
        setBoolValue: { setting, value in
            let settings = SGSimpleSettings.shared
            switch setting {
            case .ghostHideReadReceipts:
                settings.ghostHideReadReceipts = value
            case .ghostHideOnline:
                settings.ghostHideOnline = value
            case .ghostHideTyping:
                settings.ghostHideTyping = value
            case .storyStealthMode:
                settings.storyStealthMode = value
            }
            simplePromise.set(true)
        }
    )

    let signal = combineLatest(simplePromise.get(), context.sharedContext.presentationData)
    |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Rufat Extra"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: rufatExtraEntries(presentationData: presentationData), style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
