import Foundation
import UIKit
import Display
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils

public func ayuShareMessageImage(view: UIView, controller: ViewController) {
    guard view.bounds.width > 0.0 && view.bounds.height > 0.0 else { return }
    let format = UIGraphicsImageRendererFormat()
    format.scale = min(UIScreen.main.scale, 3.0)
    let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
        view.layer.render(in: context.cgContext)
    }
    let share = UIActivityViewController(activityItems: [image], applicationActivities: nil)
    share.popoverPresentationController?.sourceView = controller.view
    share.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1.0, height: 1.0)
    controller.present(share, animated: true)
}

public func ayuPresentMessageDetails(context: AccountContext, message: Message, controller: ViewController) {
    let russian = context.sharedContext.currentPresentationData.with { $0.strings.baseLanguageCode.hasPrefix("ru") }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    func date(_ timestamp: Int32) -> String { return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp))) }
    var lines = [
        "Message ID: \(message.id.id)",
        "Chat ID: \(message.id.peerId.toInt64())",
        "Namespace: \(message.id.namespace)",
        (russian ? "Дата: " : "Sent: ") + date(message.timestamp)
    ]
    if let author = message.author { lines.append((russian ? "Автор: " : "Author: ") + "\(author.debugDisplayTitle) (\(author.id.toInt64()))") }
    if let edited = message.attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute { lines.append((russian ? "Изменено: " : "Edited: ") + date(edited.date)) }
    if let forward = message.forwardInfo { lines.append((russian ? "Переслано: " : "Forward date: ") + date(forward.date)) }
    if let threadId = message.threadId { lines.append("Thread ID: \(threadId)") }
    if let groupingKey = message.groupingKey { lines.append("Album ID: \(groupingKey)") }
    for media in message.media {
        if let file = media as? TelegramMediaFile {
            lines.append("MIME: \(file.mimeType)")
            if let size = file.size { lines.append((russian ? "Размер: " : "Size: ") + ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        }
    }
    let text = lines.joined(separator: "\n")
    controller.present(textAlertController(context: context, title: russian ? "Сведения о сообщении" : "Message Details", text: text, actions: [
        TextAlertAction(type: .genericAction, title: russian ? "Копировать" : "Copy", action: { UIPasteboard.general.string = text }),
        TextAlertAction(type: .defaultAction, title: "OK", action: {})
    ]), in: .window(.root))
}
