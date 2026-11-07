import Foundation
import UIKit
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import AccountContext
import SwiftSignalKit
import OverlayStatusController

public func ayuPresentForward(context: AccountContext, messages: [Message], controller: ViewController) {
    let russian = context.sharedContext.currentPresentationData.with { $0.strings.baseLanguageCode.hasPrefix("ru") }
    let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyWriteable, .excludeSecretChats, .doNotSearchMessages], title: "AyuForward"))
    picker.peerSelected = { [weak picker] peer, _ in
        guard let picker = picker else { return }
        let disposable = MetaDisposable()
        let progress = OverlayStatusController(style: .dark, type: .loading(cancelled: { disposable.dispose() }))
        picker.present(progress, in: .window(.root))
        disposable.set((ayuForwardMessages(account: context.account, messages: messages, to: peer.id)
        |> deliverOnMainQueue).start(next: { ids in
            progress.dismiss()
            let text = ids.contains(where: { $0 != nil })
                ? (russian ? "Копия добавлена в очередь отправки." : "The copy was added to the send queue.")
                : (russian ? "Не удалось добавить сообщения в очередь." : "Could not enqueue the messages.")
            picker.present(textAlertController(context: context, title: "AyuForward", text: text, actions: [TextAlertAction(type: .defaultAction, title: "OK", action: { picker.dismiss() })]), in: .window(.root))
        }, error: { error in
            progress.dismiss()
            let text: String
            switch error {
            case .unsupportedContent: text = russian ? "Этот тип содержимого пока не поддерживается. Поддерживаются текст, фото, видео, файлы, голосовые сообщения, контакты и геопозиции." : "This content type is not supported. Text, photos, videos, files, voice messages, contacts and locations are supported."
            case .downloadFailed: text = russian ? "Не удалось загрузить вложение. Проверь соединение и повтори." : "Could not download the attachment. Check the connection and retry."
            case .storageFailed: text = russian ? "Не удалось сохранить файл для повторной загрузки. Проверь свободное место." : "Could not prepare the upload file. Check available storage."
            }
            picker.present(textAlertController(context: context, title: "AyuForward", text: text, actions: [TextAlertAction(type: .defaultAction, title: "OK", action: {})]), in: .window(.root))
        }))
    }
    controller.push(picker)
}
