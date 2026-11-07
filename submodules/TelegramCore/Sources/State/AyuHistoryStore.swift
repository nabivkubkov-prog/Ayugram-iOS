import Foundation
import Postbox
import SGSimpleSettings
import SwiftSignalKit

/// Uses a durable Postbox collection belonging to a single account, not an evictable item cache.
public enum AyuHistoryStore {
    // "AyuH". Kept outside Telegram's small, sequential ordered-list namespace.
    public static let collectionId: Int32 = 0x41797548

    public static func chatRules(accountId: Int64) -> AyuHistoryChatRules {
        guard let data = UserDefaults.standard.data(forKey: "ayugram.archive.chatRules.\(accountId)"),
              let value = try? JSONDecoder().decode(AyuHistoryChatRules.self, from: data) else { return AyuHistoryChatRules() }
        return value
    }

    public static func updateChatRules(accountId: Int64, _ update: (inout AyuHistoryChatRules) -> Void) {
        var value = chatRules(accountId: accountId)
        update(&value)
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: "ayugram.archive.chatRules.\(accountId)")
        }
    }

    private static func category(_ message: Message) -> AyuHistoryChatCategory {
        if let channel = message.peers[message.id.peerId] as? TelegramChannel {
            let isPublic = !(channel.addressName ?? "").isEmpty
            if case .broadcast = channel.info { return isPublic ? .publicChannel : .privateChannel }
            return isPublic ? .publicGroup : .privateGroup
        }
        return message.id.peerId.namespace == Namespaces.Peer.CloudUser ? .privateChat : .privateGroup
    }

    static func shouldCapture(_ message: Message, accountPeerId: PeerId) -> Bool {
        guard message.id.peerId.namespace != Namespaces.Peer.SecretChat,
              message.id.namespace == Namespaces.Message.Cloud,
              !message.attributes.contains(where: { $0 is AutoremoveTimeoutMessageAttribute || $0 is AutoclearTimeoutMessageAttribute }) else {
            return false
        }
        let settings = SGSimpleSettings.shared
        let isBotDialog = (message.peers[message.id.peerId] as? TelegramUser)?.botInfo != nil
        let isBotAuthor = (message.author as? TelegramUser)?.botInfo != nil
        return AyuHistoryPolicy.includes(accountId: accountPeerId.toInt64(), peerId: message.id.peerId.toInt64(), selectedPeerIds: settings.archiveExcludedPeerIds, onlySelected: settings.archiveOnlySelected)
            && chatRules(accountId: accountPeerId.toInt64()).allowsMessages(category: category(message), isBotDialog: isBotDialog, isBotAuthor: isBotAuthor)
    }

    static func captureEdit(transaction: Transaction, accountPeerId: PeerId, mediaBox: MediaBox, previous: Message, updated: StoreMessage) {
        guard SGSimpleSettings.shared.saveEditHistory, shouldCapture(previous, accountPeerId: accountPeerId) else { return }
        let oldEntities = previous.textEntitiesAttribute?.entities ?? []
        let newEntities = (updated.attributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute)?.entities ?? []
        let mediaChanged = previous.media.count != updated.media.count || zip(previous.media, updated.media).contains(where: { !$0.0.isEqual(to: $0.1) })
        guard previous.text != updated.text || oldEntities != newEntities || mediaChanged else { return }
        capture(transaction: transaction, accountPeerId: accountPeerId, mediaBox: mediaBox, message: previous, kind: .edited)
    }

    static func captureDeleted(transaction: Transaction, accountPeerId: PeerId, mediaBox: MediaBox, message: Message) {
        guard SGSimpleSettings.shared.keepDeletedMessages, shouldCapture(message, accountPeerId: accountPeerId) else { return }
        capture(transaction: transaction, accountPeerId: accountPeerId, mediaBox: mediaBox, message: message, kind: .deleted)
    }

    private static func recordKey(_ id: String) -> MemoryBuffer {
        return MemoryBuffer(data: Data(id.utf8))
    }

    private static func archiveDirectory(_ mediaBox: MediaBox) -> URL {
        return URL(fileURLWithPath: mediaBox.basePath, isDirectory: true).deletingLastPathComponent().appendingPathComponent("ayugram-history-media", isDirectory: true)
    }

    public static func attachmentURL(mediaBox: MediaBox, attachment: AyuHistoryAttachment) -> URL? {
        guard let name = attachment.retainedFileName, AyuHistoryPolicy.safeAttachmentName(name) else { return nil }
        let url = archiveDirectory(mediaBox).appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private static func encoded(_ value: PostboxCoding) -> Data {
        let encoder = PostboxEncoder()
        encoder.encodeRootObject(value)
        return encoder.makeData()
    }

    private static func capture(transaction: Transaction, accountPeerId: PeerId, mediaBox: MediaBox, message: Message, kind: AyuHistoryKind) {
        let id: String
        if kind == .deleted {
            id = "d:\(message.id.peerId.toInt64()):\(message.id.namespace):\(message.id.id)"
            guard transaction.getOrderedItemListItem(collectionId: collectionId, itemId: recordKey(id)) == nil else { return }
        } else {
            id = "e:\(UUID().uuidString)"
        }
        let record = AyuHistoryRecord(
            id: id, accountId: accountPeerId.toInt64(), peerId: message.id.peerId.toInt64(),
            namespace: message.id.namespace, messageId: message.id.id, kind: kind,
            originalTimestamp: message.timestamp, capturedAt: Int32(clamping: Int64(Date().timeIntervalSince1970)),
            threadId: message.threadId, groupingKey: message.groupingKey, authorId: message.author?.id.toInt64(),
            authorName: message.author?.debugDisplayTitle ?? "", peerName: message.peers[message.id.peerId]?.debugDisplayTitle ?? "",
            text: message.text, originalEditTimestamp: (message.attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute)?.date,
            globallyUniqueId: message.globallyUniqueId, messageFlags: message.flags.rawValue,
            forwardInfo: message.forwardInfo.map { info in
                AyuHistoryForwardInfo(authorId: info.author?.id.toInt64(), sourceId: info.source?.id.toInt64(), sourceMessagePeerId: info.sourceMessageId?.peerId.toInt64(), sourceMessageNamespace: info.sourceMessageId?.namespace, sourceMessageId: info.sourceMessageId?.id, date: info.date, authorSignature: info.authorSignature, psaType: info.psaType, flags: info.flags.rawValue)
            },
            attributes: message.attributes.filter { !($0 is RufatDeletedMessageAttribute) }.map { encoded($0) },
            media: message.media.map { encoded($0) }, attachments: retainAttachments(message: message, accountPeerId: accountPeerId, mediaBox: mediaBox)
        )
        if let entry = CodableEntry(record) {
            transaction.addOrMoveToFirstPositionOrderedItemListItem(collectionId: collectionId, item: OrderedItemListEntry(id: recordKey(record.id), contents: entry), removeTailIfCountExceeds: nil)
        }
    }

    private static func retainAttachments(message: Message, accountPeerId: PeerId, mediaBox: MediaBox) -> [AyuHistoryAttachment] {
        let retainFiles = SGSimpleSettings.shared.saveHistoryMedia && chatRules(accountId: accountPeerId.toInt64()).allowsMedia(category: category(message))
        var resources: [(MediaResource, String, String)] = []
        for media in message.media {
            if let file = media as? TelegramMediaFile {
                resources.append((file.resource, file.fileName ?? "attachment", file.mimeType))
            } else if let image = media as? TelegramMediaImage {
                // Preserve the best representation actually available, not just a remote resource reference.
                let representations = image.representations.sorted { Int64($0.dimensions.width) * Int64($0.dimensions.height) > Int64($1.dimensions.width) * Int64($1.dimensions.height) }
                if let representation = representations.first(where: { mediaBox.completedResourcePath($0.resource) != nil }) ?? representations.first {
                    resources.append((representation.resource, "photo.jpg", "image/jpeg"))
                }
            }
        }
        var seen = Set<String>()
        return resources.compactMap { resource, originalName, mimeType -> AyuHistoryAttachment? in
            guard seen.insert(resource.id.stringRepresentation).inserted else { return nil }
            var attachment = AyuHistoryAttachment(resourceId: resource.id.stringRepresentation, originalName: originalName, mimeType: mimeType, size: resource.size ?? 0, retainedFileName: nil)
            guard retainFiles, let source = mediaBox.completedResourcePath(resource) else { return attachment }
            let fileManager = FileManager.default
            do {
                let sourceAttributes = try fileManager.attributesOfItem(atPath: source)
                let sourceSize = (sourceAttributes[.size] as? NSNumber)?.int64Value ?? 0
                attachment = AyuHistoryAttachment(resourceId: resource.id.stringRepresentation, originalName: originalName, mimeType: mimeType, size: sourceSize, retainedFileName: nil)
                let directory = archiveDirectory(mediaBox)
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                guard try makeRoom(directory: directory, requiredBytes: sourceSize) else { return attachment }
                let originalExtension = URL(fileURLWithPath: originalName).pathExtension
                let suffix = !originalExtension.isEmpty && originalExtension.count <= 12 && originalExtension.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) ? originalExtension : "bin"
                let name = UUID().uuidString + "." + suffix
                let target = directory.appendingPathComponent(name)
                do {
                    // Completed MediaBox resources are immutable. A separate hard link survives cache eviction.
                    try fileManager.linkItem(atPath: source, toPath: target.path)
                } catch {
                    try fileManager.copyItem(atPath: source, toPath: target.path)
                }
                attachment.retainedFileName = name
            } catch {
                // The record remains readable and the browser explicitly marks its attachment unavailable.
            }
            return attachment
        }
    }

    private static func makeRoom(directory: URL, requiredBytes: Int64) throws -> Bool {
        let megabytes = Int64(max(0, SGSimpleSettings.shared.archiveMediaLimitMB))
        guard megabytes > 0 else { return true }
        let limit = megabytes * 1024 * 1024
        guard requiredBytes <= limit else { return false }
        let fileManager = FileManager.default
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey], options: [.skipsHiddenFiles])
        var files: [(URL, Int64, Date)] = []
        var used: Int64 = 0
        for url in urls where AyuHistoryPolicy.safeAttachmentName(url.lastPathComponent) {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let size = Int64(values.fileSize ?? 0)
            files.append((url, size, values.creationDate ?? .distantPast))
            used += size
        }
        for (url, size, _) in files.sorted(by: { $0.2 < $1.2 }) where used + requiredBytes > limit {
            try fileManager.removeItem(at: url)
            used -= size
        }
        return used + requiredBytes <= limit
    }

    public static func records(postbox: Postbox) -> Signal<[AyuHistoryRecord], NoError> {
        let key = PostboxViewKey.orderedItemList(id: collectionId)
        return postbox.combinedView(keys: [key]) |> map { view in
            guard let list = view.views[key] as? OrderedItemListView else { return [] }
            return list.items.compactMap { $0.contents.get(AyuHistoryRecord.self) }
        }
    }

    public static func remove(postbox: Postbox, recordIds: Set<String>) -> Signal<Bool, NoError> {
        return postbox.transaction { transaction -> Bool in
            var removedFiles = Set<String>()
            var referencedFiles = Set<String>()
            var selected: [(OrderedItemListEntry, AyuHistoryRecord)] = []
            for entry in transaction.getOrderedListItems(collectionId: collectionId) {
                guard let record = entry.contents.get(AyuHistoryRecord.self) else { continue }
                let files = record.attachments.compactMap(\.retainedFileName)
                if recordIds.contains(record.id) {
                    removedFiles.formUnion(files)
                    selected.append((entry, record))
                } else {
                    referencedFiles.formUnion(files)
                }
            }
            var failed = Set<String>()
            for name in removedFiles.subtracting(referencedFiles) where AyuHistoryPolicy.safeAttachmentName(name) {
                let url = archiveDirectory(postbox.mediaBox).appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    do { try FileManager.default.removeItem(at: url) } catch { failed.insert(name) }
                }
            }
            for (entry, record) in selected where Set(record.attachments.compactMap(\.retainedFileName)).isDisjoint(with: failed) {
                transaction.removeOrderedItemListItem(collectionId: collectionId, itemId: entry.id)
            }
            return failed.isEmpty
        }
    }

    public static func merge(postbox: Postbox, accountId: Int64, backup: AyuHistoryBackup) -> Signal<Int, NoError> {
        return postbox.transaction { transaction -> Int in
            var added = 0
            for var record in backup.records.sorted(by: { $0.capturedAt < $1.capturedAt }) where record.accountId == accountId {
                record.attachments = record.attachments.map { attachment in
                    var attachment = attachment
                    attachment.retainedFileName = nil
                    return attachment
                }
                let key = recordKey(record.id)
                guard transaction.getOrderedItemListItem(collectionId: collectionId, itemId: key) == nil, let entry = CodableEntry(record) else { continue }
                transaction.addOrMoveToFirstPositionOrderedItemListItem(collectionId: collectionId, item: OrderedItemListEntry(id: key, contents: entry), removeTailIfCountExceeds: nil)
                added += 1
            }
            return added
        }
    }
}
