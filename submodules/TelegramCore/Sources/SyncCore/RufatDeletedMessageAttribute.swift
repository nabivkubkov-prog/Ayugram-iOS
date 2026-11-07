import Foundation
import Postbox
import SGSimpleSettings

// MARK: RufatGram
/// Marks a message that was deleted on the server while the
/// "keep deleted messages" option was enabled. The message stays in the
/// local database only; nothing is sent back to the server.
public final class RufatDeletedMessageAttribute: MessageAttribute {
    public let deletedAt: Int32

    public init(deletedAt: Int32) {
        self.deletedAt = deletedAt
    }

    public init(decoder: PostboxDecoder) {
        self.deletedAt = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.deletedAt, forKey: "d")
    }
}

public extension Message {
    var rufatIsDeleted: Bool {
        return self.attributes.contains(where: { $0 is RufatDeletedMessageAttribute })
    }
}

/// Splits server-deleted message ids into ones that may be kept locally and
/// ones that must still be removed. Secret chats and messages with a
/// self-destruct timer are never kept.
func rufatPartitionDeletedMessages(transaction: Transaction, accountPeerId: PeerId, ids: [MessageId]) -> (keep: [MessageId], remove: [MessageId]) {
    guard SGSimpleSettings.shared.keepDeletedMessages else {
        return ([], ids)
    }
    var keep: [MessageId] = []
    var remove: [MessageId] = []
    for id in ids {
        guard let message = transaction.getMessage(id), AyuHistoryStore.shouldCapture(message, accountPeerId: accountPeerId) else {
            remove.append(id)
            continue
        }
        // Replayed server deletions must not erase a previously retained message.
        keep.append(id)
    }
    return (keep, remove)
}

func rufatMarkMessagesDeleted(transaction: Transaction, accountPeerId: PeerId, mediaBox: MediaBox, ids: [MessageId]) {
    let timestamp = Int32(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970)
    for id in ids {
        if let message = transaction.getMessage(id) {
            AyuHistoryStore.captureDeleted(transaction: transaction, accountPeerId: accountPeerId, mediaBox: mediaBox, message: message)
            if message.rufatIsDeleted {
                continue
            }
        }
        transaction.updateMessage(id, update: { currentMessage in
            var attributes = currentMessage.attributes
            attributes.append(RufatDeletedMessageAttribute(deletedAt: timestamp))
            let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
        })
    }
}
