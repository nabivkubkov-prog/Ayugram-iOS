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

private enum RufatCustomizationSection: Int32, SGItemListSection {
    case appearance
    case chatList
    case tabs
    case messages
    case stickers
    case colors
}

private enum RufatCustomizationToggle: String {
    case compactChatList
    case compactFolderNames
    case hideTabBar
    case showTabNames
    case secondsInMessages
    case wideChannelPosts
    case hideReactions
    case snapDeletionEffect
    case stickerTimestamp
}

private enum RufatCustomizationSlider: String {
    case stickerSize
    case accountColorsSaturation
}

private enum RufatCustomizationLink: String {
    case themesAndWallpapers
}

private typealias RufatCustomizationEntry = SGItemListUIEntry<RufatCustomizationSection, RufatCustomizationToggle, RufatCustomizationSlider, AnyHashable, RufatCustomizationLink, AnyHashable>

private func rufatText(_ lang: String, _ en: String, _ ru: String) -> String {
    return lang == "ru" ? ru : en
}

private func rufatCustomizationEntries(presentationData: PresentationData) -> [RufatCustomizationEntry] {
    let lang = presentationData.strings.baseLanguageCode
    let settings = SGSimpleSettings.shared
    var entries: [RufatCustomizationEntry] = []
    let id = SGItemListCounter()

    entries.append(.header(id: id.count, section: .appearance, text: rufatText(lang, "APPEARANCE", "ОФОРМЛЕНИЕ"), badge: nil))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .themesAndWallpapers, text: rufatText(lang, "Themes, Wallpapers and Text Size", "Темы, обои и размер текста")))

    entries.append(.header(id: id.count, section: .chatList, text: rufatText(lang, "CHAT LIST", "СПИСОК ЧАТОВ"), badge: nil))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .compactChatList, value: settings.compactChatList, text: rufatText(lang, "Compact Chat List", "Компактный список чатов"), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .compactFolderNames, value: settings.compactFolderNames, text: rufatText(lang, "Compact Folder Names", "Компактные названия папок"), enabled: true))

    entries.append(.header(id: id.count, section: .tabs, text: rufatText(lang, "TAB BAR", "ПАНЕЛЬ ВКЛАДОК"), badge: nil))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .hideTabBar, value: settings.hideTabBar, text: rufatText(lang, "Hide Tab Bar", "Скрыть панель вкладок"), enabled: true))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .showTabNames, value: settings.showTabNames, text: rufatText(lang, "Show Tab Names", "Подписи вкладок"), enabled: !settings.hideTabBar))
    entries.append(.notice(id: id.count, section: .tabs, text: rufatText(lang, "Chat list and tab bar changes apply after restarting the app.", "Изменения списка чатов и вкладок применяются после перезапуска приложения.")))

    entries.append(.header(id: id.count, section: .messages, text: rufatText(lang, "MESSAGES", "СООБЩЕНИЯ"), badge: nil))
    entries.append(.toggle(id: id.count, section: .messages, settingName: .secondsInMessages, value: settings.secondsInMessages, text: rufatText(lang, "Seconds in Message Time", "Секунды во времени сообщений"), enabled: true))
    entries.append(.toggle(id: id.count, section: .messages, settingName: .wideChannelPosts, value: settings.wideChannelPosts, text: rufatText(lang, "Wide Channel Posts", "Широкие посты в каналах"), enabled: true))
    entries.append(.toggle(id: id.count, section: .messages, settingName: .hideReactions, value: settings.hideReactions, text: rufatText(lang, "Hide Reactions", "Скрыть реакции"), enabled: true))
    entries.append(.toggle(id: id.count, section: .messages, settingName: .snapDeletionEffect, value: !settings.disableSnapDeletionEffect, text: rufatText(lang, "Dust Effect on Delete", "Эффект «пыли» при удалении"), enabled: true))

    entries.append(.header(id: id.count, section: .stickers, text: rufatText(lang, "STICKER SIZE", "РАЗМЕР СТИКЕРОВ"), badge: nil))
    entries.append(.percentageSlider(id: id.count, section: .stickers, settingName: .stickerSize, value: settings.stickerSize))
    entries.append(.toggle(id: id.count, section: .stickers, settingName: .stickerTimestamp, value: settings.stickerTimestamp, text: rufatText(lang, "Time on Stickers", "Время на стикерах"), enabled: true))

    entries.append(.header(id: id.count, section: .colors, text: rufatText(lang, "NAME COLOR SATURATION", "НАСЫЩЕННОСТЬ ЦВЕТОВ ИМЁН"), badge: nil))
    entries.append(.percentageSlider(id: id.count, section: .colors, settingName: .accountColorsSaturation, value: settings.accountColorsSaturation))

    return entries
}

public func rufatCustomizationController(context: AccountContext, openThemesAndWallpapers: @escaping () -> Void) -> ViewController {
    // SGSimpleSettings is UserDefaults-backed and not observable, so changes re-trigger the list manually.
    let simplePromise = ValuePromise(true, ignoreRepeated: false)

    let arguments = SGItemListArguments<RufatCustomizationToggle, RufatCustomizationSlider, AnyHashable, RufatCustomizationLink, AnyHashable>(
        context: context,
        setBoolValue: { setting, value in
            let settings = SGSimpleSettings.shared
            switch setting {
            case .compactChatList:
                settings.compactChatList = value
            case .compactFolderNames:
                settings.compactFolderNames = value
            case .hideTabBar:
                settings.hideTabBar = value
            case .showTabNames:
                settings.showTabNames = value
            case .secondsInMessages:
                settings.secondsInMessages = value
            case .wideChannelPosts:
                settings.wideChannelPosts = value
            case .hideReactions:
                settings.hideReactions = value
            case .snapDeletionEffect:
                settings.disableSnapDeletionEffect = !value
            case .stickerTimestamp:
                settings.stickerTimestamp = value
            }
            simplePromise.set(true)
        },
        updateSliderValue: { setting, value in
            let settings = SGSimpleSettings.shared
            switch setting {
            case .stickerSize:
                if settings.stickerSize != value {
                    settings.stickerSize = value
                    simplePromise.set(true)
                }
            case .accountColorsSaturation:
                if settings.accountColorsSaturation != value {
                    settings.accountColorsSaturation = value
                    simplePromise.set(true)
                }
            }
        },
        openDisclosureLink: { link in
            switch link {
            case .themesAndWallpapers:
                openThemesAndWallpapers()
            }
        }
    )

    let signal = combineLatest(simplePromise.get(), context.sharedContext.presentationData)
    |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let title = presentationData.strings.baseLanguageCode == "ru" ? "Кастомизация" : "Customization"
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: rufatCustomizationEntries(presentationData: presentationData), style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
