import Foundation

public extension Notification.Name {
    static let ayuAppearanceChanged = Notification.Name("ayuAppearanceChanged")
}

/// Presentation-only preferences. These never change account flags or server limits.
public final class AyuAppearanceSettings {
    public static let shared = AyuAppearanceSettings(defaults: .standard)
    private let defaults: UserDefaults
    private let prefix = "ayu.appearance.v1."

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var localPremium: Bool {
        get { return defaults.bool(forKey: prefix + "localPremium") }
        set { set(newValue, key: "localPremium") }
    }

    public var streamerMode: Bool {
        get { return defaults.bool(forKey: prefix + "streamerMode") }
        set { set(newValue, key: "streamerMode") }
    }

    public var hideChatList: Bool {
        get { return defaults.bool(forKey: prefix + "hideChatList") }
        set { set(newValue, key: "hideChatList") }
    }

    public func localEmojiStatus(accountId: Int64, now: Int32 = Int32(Date().timeIntervalSince1970)) -> Int64? {
        guard localPremium else { return nil }
        let key = prefix + "emoji.\(accountId)"
        guard let status = defaults.dictionary(forKey: key), let rawId = status["fileId"] as? String,
              let fileId = Int64(rawId), fileId != 0 else { return nil }
        if let expiration = status["expiration"] as? Int, expiration <= Int(now) { return nil }
        return fileId
    }

    public func setLocalEmojiStatus(accountId: Int64, fileId: Int64?, expiration: Int32?) {
        let key = prefix + "emoji.\(accountId)"
        if let fileId, fileId != 0 {
            var status: [String: Any] = ["fileId": String(fileId)]
            if let expiration { status["expiration"] = Int(expiration) }
            defaults.set(status, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: .ayuAppearanceChanged, object: nil)
    }

    private func set(_ value: Bool, key: String) {
        defaults.set(value, forKey: prefix + key)
        NotificationCenter.default.post(name: .ayuAppearanceChanged, object: nil)
    }
}
