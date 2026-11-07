import Foundation

public enum AyuGhostOption: String, Codable, CaseIterable {
    case readReceipts, online, typing, stories, uploadProgress
}

public enum AyuPeerGhostRule: String, Codable, CaseIterable {
    case inherit, alwaysHide, alwaysAllow
}

/// A value policy shared by the settings screen and the last outgoing RPC boundary.
/// Account identifiers are local account-directory names, never phone numbers.
public struct AyuGhostConfiguration: Codable, Equatable {
    public var hideReadReceipts = false
    public var hideOnline = false
    public var hideTyping = false
    public var hideStories = false
    public var hideUploadProgress = false
    public var readOnSend = false
    public var readOnReaction = false
    public var offlineAfterSend = true
    public var useScheduledMessages = false
    public var silentSendInGhostMode = false
    public var readOnPoll = false
    public var lockedOptions: Set<AyuGhostOption> = []
    public var readRules: [String: AyuPeerGhostRule] = [:]
    public var typingRules: [String: AyuPeerGhostRule] = [:]

    public init() {}

    public var isEnabled: Bool {
        return hideReadReceipts || hideOnline || hideTyping || hideStories || hideUploadProgress
    }

    public mutating func setEnabled(_ enabled: Bool) {
        if !lockedOptions.contains(.readReceipts) { hideReadReceipts = enabled }
        if !lockedOptions.contains(.online) { hideOnline = enabled }
        if !lockedOptions.contains(.typing) { hideTyping = enabled }
        if !lockedOptions.contains(.stories) { hideStories = enabled }
        if !lockedOptions.contains(.uploadProgress) { hideUploadProgress = enabled }
    }

    public func hidesReadReceipts(peerId: Int64? = nil) -> Bool {
        return resolve(hideReadReceipts, peerId: peerId, rules: readRules)
    }

    public func hidesTyping(peerId: Int64? = nil) -> Bool {
        return resolve(hideTyping, peerId: peerId, rules: typingRules)
    }

    private func resolve(_ fallback: Bool, peerId: Int64?, rules: [String: AyuPeerGhostRule]) -> Bool {
        guard let peerId = peerId, let rule = rules[String(peerId)] else { return fallback }
        switch rule {
        case .inherit: return fallback
        case .alwaysHide: return true
        case .alwaysAllow: return false
        }
    }

    public func suppressesReceipt(function: String, peerId: Int64? = nil) -> Bool {
        switch function {
        case "stories.readStories", "stories.incrementStoryViews":
            return hideStories
        case "messages.readHistory", "messages.readEncryptedHistory", "channels.readHistory", "messages.readDiscussion",
             "messages.readSavedHistory", "messages.readMessageContents", "channels.readMessageContents",
             "messages.readMentions", "messages.readReactions":
            return hidesReadReceipts(peerId: peerId)
        default:
            return false
        }
    }
}

public extension Notification.Name {
    static let ayuGhostSettingsChanged = Notification.Name("AyuGram.GhostSettingsChanged")
}
