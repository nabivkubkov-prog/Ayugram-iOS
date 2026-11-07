import Foundation
import Postbox
import SGSimpleSettings
import SwiftSignalKit

/// Uses a durable Postbox collection belonging to a single account, not an evictable item cache.
public enum AyuHistoryStore {
    // "AyuH". Kept outside Telegram's small, sequential ordered-list namespace.
    public static let collectionId: Int32 = 0x41797548

    private static var capacityKey: ValueBoxKey {
        let key = ValueBoxKey(length: 8)
        key.setInt64(0, value: 0x4179754869737443)
        return key
    }

    private static func capacity(transaction: Transaction) -> AyuHistoryCapacity {
        if let stored = transaction.getPreferencesEntry(key: capacityKey)?.get(AyuHistoryCapacity.self) { return stored }
        let entries = transaction.getOrderedListItems(collectionId: collectionId)
        let value = AyuHistoryCapacity(records: entries.count, bytes: entries.reduce(0, { $0 + $1.contents.data.count }))
        setCapacity(transaction: transaction, value: value)
        return value
    }

    private static func setCapacity(transaction: Transaction, value: AyuHistoryCapacity) {
        transaction.updatePreferencesEntry(key: capacityKey, { _ in PreferencesEntry(value) })
    }

    public static func capacityWasReached(accountId: Int64) -> Bool {
        return UserDefaults.standard.bool(forKey: "ayugram.archive.full.\(accountId)")
    }

    private static func setCapacityReached(accountId: Int64, _ reached: Bool) {
        let key = "ayugram.archive.full.\(accountId)"
        if UserDefaults.standard.bool(forKey: key) != reached { UserDefaults.standard.set(reached, forKey: key) }
    }

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
        var record = AyuHistoryRecord(
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
            media: message.media.map { encoded($0) }, attachments: []
        )
        var usage = capacity(transaction: transaction)
        // Reserve room for attachment metadata before any retained files are created.
        guard let preliminary = CodableEntry(record), usage.canInsert(bytes: preliminary.data.count + 64 * 1024) else {
            setCapacityReached(accountId: accountPeerId.toInt64(), true)
            return
        }
        record.attachments = retainAttachments(message: message, accountPeerId: accountPeerId, mediaBox: mediaBox)
        if let entry = CodableEntry(record) {
            guard usage.canInsert(bytes: entry.data.count) else {
                for attachment in record.attachments {
                    if let url = attachmentURL(mediaBox: mediaBox, attachment: attachment) { try? FileManager.default.removeItem(at: url) }
                }
                AyuHistoryMediaBudget.shared.invalidate(directory: archiveDirectory(mediaBox))
                setCapacityReached(accountId: accountPeerId.toInt64(), true)
                return
            }
            transaction.addOrMoveToFirstPositionOrderedItemListItem(collectionId: collectionId, item: OrderedItemListEntry(id: recordKey(record.id), contents: entry), removeTailIfCountExceeds: nil)
            usage.records += 1
            usage.bytes += entry.data.count
            setCapacity(transaction: transaction, value: usage)
        }
    }

    private static func retainAttachments(message: Message, accountPeerId: PeerId, mediaBox: MediaBox) -> [AyuHistoryAttachment] {
        let retainFiles = SGSimpleSettings.shared.saveHistoryMedia && chatRules(accountId: accountPeerId.toInt64()).allowsMedia(category: category(message))
        var resources: [(resource: MediaResource, name: String, mimeType: String, role: String, width: Int32?, height: Int32?, duration: Double?)] = []
        func collect(_ media: Media, depth: Int = 0, role: String = "attachment") {
            guard depth < 4, resources.count < 64 else { return }
            if let file = media as? TelegramMediaFile {
                var width: Int32?
                var height: Int32?
                var duration: Double?
                for attribute in file.attributes {
                    switch attribute {
                    case let .Video(value, size, _, _, _, _): duration = value; width = size.width; height = size.height
                    case let .Audio(_, value, _, _, _): duration = Double(value)
                    case let .ImageSize(size): width = size.width; height = size.height
                    default: break
                    }
                }
                let names = ["video/mp4": "video.mp4", "video/webm": "video.webm", "audio/ogg": "voice.ogg", "audio/mp4": "audio.m4a", "audio/mpeg": "audio.mp3", "image/webp": "sticker.webp", "image/png": "image.png", "image/jpeg": "image.jpg", "application/x-tgsticker": "sticker.tgs"]
                resources.append((file.resource, file.fileName ?? names[file.mimeType] ?? "attachment.bin", file.mimeType, role, width, height, duration))
                for preview in file.previewRepresentations.prefix(8) where mediaBox.completedResourcePath(preview.resource) != nil {
                    resources.append((preview.resource, "preview.jpg", "image/jpeg", "preview", preview.dimensions.width, preview.dimensions.height, nil))
                }
                for preview in file.videoThumbnails.prefix(4) where mediaBox.completedResourcePath(preview.resource) != nil {
                    resources.append((preview.resource, "preview.mp4", "video/mp4", "videoPreview", preview.dimensions.width, preview.dimensions.height, nil))
                }
                if let cover = file.videoCover { collect(cover, depth: depth + 1, role: "cover") }
                for alternate in file.alternativeRepresentations.prefix(8) where mediaBox.completedResourcePath(alternate.resource) != nil {
                    collect(alternate, depth: depth + 1, role: "alternative")
                }
            } else if let image = media as? TelegramMediaImage {
                // Preserve the best representation actually available, not just a remote resource reference.
                let representations = image.representations.sorted { Int64($0.dimensions.width) * Int64($0.dimensions.height) > Int64($1.dimensions.width) * Int64($1.dimensions.height) }
                if let representation = representations.first(where: { mediaBox.completedResourcePath($0.resource) != nil }) ?? representations.first {
                    resources.append((representation.resource, "photo.jpg", "image/jpeg", role, representation.dimensions.width, representation.dimensions.height, nil))
                }
                for video in image.videoRepresentations.prefix(4) where mediaBox.completedResourcePath(video.resource) != nil {
                    resources.append((video.resource, "photo-video.mp4", "video/mp4", "videoRepresentation", video.dimensions.width, video.dimensions.height, nil))
                }
            } else if let paid = media as? TelegramMediaPaidContent {
                for extended in paid.extendedMedia.prefix(64) {
                    if case let .full(available) = extended { collect(available, depth: depth + 1) }
                }
            } else if let invoice = media as? TelegramMediaInvoice, let extended = invoice.extendedMedia, case let .full(available) = extended {
                collect(available, depth: depth + 1)
            }
        }
        for media in message.media { collect(media) }
        var seen = Set<String>()
        return resources.prefix(64).compactMap { candidate -> AyuHistoryAttachment? in
            let (resource, name, mimeType, role, rawWidth, rawHeight, rawDuration) = candidate
            let originalName = String(name.prefix(4096))
            let width = rawWidth.map { max(0, $0) }
            let height = rawHeight.map { max(0, $0) }
            let duration = rawDuration.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            guard seen.insert(resource.id.stringRepresentation).inserted else { return nil }
            var attachment = AyuHistoryAttachment(resourceId: resource.id.stringRepresentation, originalName: originalName, mimeType: mimeType, size: max(0, resource.size ?? 0), retainedFileName: nil, role: role, width: width, height: height, duration: duration)
            guard retainFiles, let source = mediaBox.completedResourcePath(resource) else { return attachment }
            let fileManager = FileManager.default
            do {
                let sourceAttributes = try fileManager.attributesOfItem(atPath: source)
                let sourceSize = (sourceAttributes[.size] as? NSNumber)?.int64Value ?? 0
                attachment = AyuHistoryAttachment(resourceId: resource.id.stringRepresentation, originalName: originalName, mimeType: mimeType, size: sourceSize, retainedFileName: nil, role: role, width: width, height: height, duration: duration)
                let directory = archiveDirectory(mediaBox)
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                let limitBytes = Int64(max(0, SGSimpleSettings.shared.archiveMediaLimitMB)) * 1024 * 1024
                guard try AyuHistoryMediaBudget.shared.makeRoom(directory: directory, requiredBytes: sourceSize, limitBytes: limitBytes) else { return attachment }
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
                AyuHistoryMediaBudget.shared.didRetain(url: target, bytes: sourceSize)
            } catch {
                // The record remains readable and the browser explicitly marks its attachment unavailable.
            }
            return attachment
        }
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
            var usage = capacity(transaction: transaction)
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
                usage.records = max(0, usage.records - 1)
                usage.bytes = max(0, usage.bytes - entry.contents.data.count)
                setCapacityReached(accountId: record.accountId, false)
            }
            setCapacity(transaction: transaction, value: usage)
            AyuHistoryMediaBudget.shared.invalidate(directory: archiveDirectory(postbox.mediaBox))
            return failed.isEmpty
        }
    }

    public static func merge(postbox: Postbox, accountId: Int64, backup: AyuHistoryBackup) -> Signal<Int, NoError> {
        return postbox.transaction { transaction -> Int in
            var added = 0
            var usage = capacity(transaction: transaction)
            for var record in backup.records.sorted(by: { $0.capturedAt < $1.capturedAt }) where record.accountId == accountId {
                record.attachments = record.attachments.map { attachment in
                    var attachment = attachment
                    attachment.retainedFileName = nil
                    return attachment
                }
                let key = recordKey(record.id)
                guard transaction.getOrderedItemListItem(collectionId: collectionId, itemId: key) == nil, let entry = CodableEntry(record) else { continue }
                guard usage.canInsert(bytes: entry.data.count) else {
                    setCapacityReached(accountId: accountId, true)
                    break
                }
                transaction.addOrMoveToFirstPositionOrderedItemListItem(collectionId: collectionId, item: OrderedItemListEntry(id: key, contents: entry), removeTailIfCountExceeds: nil)
                added += 1
                usage.records += 1
                usage.bytes += entry.data.count
            }
            setCapacity(transaction: transaction, value: usage)
            return added
        }
    }

    /// Reclaims files left between a successful file retain and a rolled-back/crashed database transaction.
    public static func repairOrphanedMedia(postbox: Postbox) -> Signal<Int, NoError> {
        return postbox.transaction { transaction -> Int in
            let entries = transaction.getOrderedListItems(collectionId: collectionId)
            let records = entries.compactMap { $0.contents.get(AyuHistoryRecord.self) }
            // An unreadable record may still own files. Preserve them for recovery rather than guessing.
            guard records.count == entries.count else { return 0 }
            let referenced = Set(records.flatMap { $0.attachments.compactMap(\.retainedFileName) })
            let directory = archiveDirectory(postbox.mediaBox)
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return 0 }
            var removed = 0
            for file in files where AyuHistoryPolicy.safeAttachmentName(file.lastPathComponent) && !referenced.contains(file.lastPathComponent) {
                do { try FileManager.default.removeItem(at: file); removed += 1 } catch { continue }
            }
            AyuHistoryMediaBudget.shared.invalidate(directory: directory)
            return removed
        }
    }
}
