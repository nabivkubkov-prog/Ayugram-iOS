import Foundation

public enum AyuHistoryKind: String, Codable, Equatable {
    case deleted
    case edited
}

public enum AyuHistoryChatCategory: String, Codable, CaseIterable {
    case privateChat
    case publicChannel
    case privateChannel
    case publicGroup
    case privateGroup
}

public struct AyuHistoryChatRules: Codable, Equatable {
    public var excludedMessageTypes: Set<AyuHistoryChatCategory> = []
    public var excludedMediaTypes: Set<AyuHistoryChatCategory> = []
    public var saveBotDialogs = true
    public var saveBotMessagesInGroups = true

    public init() {}

    public func allowsMessages(category: AyuHistoryChatCategory, isBotDialog: Bool, isBotAuthor: Bool) -> Bool {
        guard !excludedMessageTypes.contains(category) else { return false }
        if isBotDialog && !saveBotDialogs { return false }
        if (category == .publicGroup || category == .privateGroup) && isBotAuthor && !saveBotMessagesInGroups { return false }
        return true
    }

    public func allowsMedia(category: AyuHistoryChatCategory) -> Bool {
        return !excludedMediaTypes.contains(category)
    }
}

public struct AyuHistoryForwardInfo: Codable, Equatable {
    public let authorId: Int64?
    public let sourceId: Int64?
    public let sourceMessagePeerId: Int64?
    public let sourceMessageNamespace: Int32?
    public let sourceMessageId: Int32?
    public let date: Int32
    public let authorSignature: String?
    public let psaType: String?
    public let flags: Int32
}

public struct AyuHistoryAttachment: Codable, Equatable {
    public let resourceId: String
    public let originalName: String
    public let mimeType: String
    public let size: Int64
    /// A generated basename in the account's archive directory, never an external path.
    public var retainedFileName: String?
}

public struct AyuHistoryRecord: Codable, Equatable {
    public let id: String
    public let accountId: Int64
    public let peerId: Int64
    public let namespace: Int32
    public let messageId: Int32
    public let kind: AyuHistoryKind
    public let originalTimestamp: Int32
    public let capturedAt: Int32
    public let threadId: Int64?
    public let groupingKey: Int64?
    public let authorId: Int64?
    public let authorName: String
    public let peerName: String
    public let text: String
    public let originalEditTimestamp: Int32?
    public let globallyUniqueId: Int64?
    public let messageFlags: UInt32?
    public let forwardInfo: AyuHistoryForwardInfo?
    /// Retained for lossless storage. Imported binary snapshots are never executed or decoded by the browser.
    public let attributes: [Data]
    public let media: [Data]
    public var attachments: [AyuHistoryAttachment]

    public func matches(query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || text.localizedCaseInsensitiveContains(query)
            || authorName.localizedCaseInsensitiveContains(query)
            || peerName.localizedCaseInsensitiveContains(query)
            || String(messageId) == query || String(peerId) == query
    }
}

public enum AyuHistoryBackupError: Error, LocalizedError {
    case tooLarge
    case unsupportedVersion
    case wrongAccount
    case invalidRecord

    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "The JSON history backup exceeds the 32 MB or 50,000 record limit."
        case .unsupportedVersion: return "This history backup version is not supported."
        case .wrongAccount: return "This history backup belongs to a different Telegram account."
        case .invalidRecord: return "The history backup contains invalid records."
        }
    }
}

/// Versioned metadata backup. Retained attachment files are intentionally not part of this JSON format.
public struct AyuHistoryBackup: Codable {
    public static let maximumBytes = 32 * 1024 * 1024
    public let version: Int
    public let records: [AyuHistoryRecord]

    public init(records: [AyuHistoryRecord]) {
        self.version = 1
        self.records = records
    }

    public func encoded() throws -> Data {
        guard records.count <= 50_000 else { throw AyuHistoryBackupError.tooLarge }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Device-local attachment paths must not masquerade as portable backup files.
        let portable = records.map { record -> AyuHistoryRecord in
            var record = record
            record.attachments = record.attachments.map { attachment in
                var attachment = attachment
                attachment.retainedFileName = nil
                return attachment
            }
            return record
        }
        let data = try encoder.encode(AyuHistoryBackup(records: portable))
        guard data.count <= Self.maximumBytes else { throw AyuHistoryBackupError.tooLarge }
        return data
    }

    public static func decoded(_ data: Data, accountId: Int64) throws -> AyuHistoryBackup {
        guard data.count <= maximumBytes else { throw AyuHistoryBackupError.tooLarge }
        let backup = try JSONDecoder().decode(AyuHistoryBackup.self, from: data)
        guard backup.version == 1 else { throw AyuHistoryBackupError.unsupportedVersion }
        guard backup.records.count <= 50_000 else { throw AyuHistoryBackupError.tooLarge }
        var seen = Set<String>()
        var records: [AyuHistoryRecord] = []
        for var record in backup.records {
            guard record.accountId == accountId else { throw AyuHistoryBackupError.wrongAccount }
            guard !record.id.isEmpty, record.id.utf8.count <= 200,
                  record.text.utf8.count <= 1_000_000,
                  record.authorName.utf8.count <= 16_384, record.peerName.utf8.count <= 16_384,
                  record.attributes.count <= 256, record.media.count <= 256,
                  record.attachments.count <= 256,
                  record.attributes.allSatisfy({ $0.count <= 2_000_000 }),
                  record.media.allSatisfy({ $0.count <= 2_000_000 }),
                  record.attachments.allSatisfy({ $0.size >= 0 && $0.resourceId.utf8.count <= 1024 && $0.originalName.utf8.count <= 4096 && $0.mimeType.utf8.count <= 256 }),
                  seen.insert(record.id).inserted else {
                throw AyuHistoryBackupError.invalidRecord
            }
            // Never follow paths supplied by an imported document, even when they look local.
            record.attachments = record.attachments.map { attachment in
                var attachment = attachment
                attachment.retainedFileName = nil
                return attachment
            }
            records.append(record)
        }
        return AyuHistoryBackup(records: records)
    }
}

public enum AyuHistoryPolicy {
    public static func includes(accountId: Int64, peerId: Int64, selectedPeerIds: [String], onlySelected: Bool) -> Bool {
        let selected = selectedPeerIds.contains("\(accountId):\(peerId)")
        return onlySelected ? selected : !selected
    }

    public static func safeAttachmentName(_ name: String) -> Bool {
        guard name.count > 36, name.count <= 50, name.dropFirst(36).first == ".",
              UUID(uuidString: String(name.prefix(36))) != nil else { return false }
        let suffix = name.dropFirst(37)
        return !suffix.isEmpty && suffix.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
    }
}
