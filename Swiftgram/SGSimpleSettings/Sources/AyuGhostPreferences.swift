import Foundation

public final class AyuGhostPreferences {
    public static let shared = AyuGhostPreferences(defaults: .standard)
    private let defaults: UserDefaults
    private let lock = NSRecursiveLock()
    private let prefix = "ayu.ghost.v1."
    private struct PeerRules: Codable {
        var read: [String: AyuPeerGhostRule]
        var typing: [String: AyuPeerGhostRule]
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var useGlobalSettings: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return defaults.object(forKey: prefix + "global") as? Bool ?? true
        }
        set {
            lock.lock()
            defaults.set(newValue, forKey: prefix + "global")
            lock.unlock()
            NotificationCenter.default.post(name: .ayuGhostSettingsChanged, object: nil)
        }
    }

    public func configuration(accountPath: String, fallback: AyuGhostConfiguration) -> AyuGhostConfiguration {
        lock.lock()
        defer { lock.unlock() }
        let accountKey = URL(fileURLWithPath: accountPath).lastPathComponent
        let key = prefix + (useGlobalSettings ? "all" : "account." + accountKey)
        var value: AyuGhostConfiguration
        if let data = defaults.data(forKey: key), let stored = try? JSONDecoder().decode(AyuGhostConfiguration.self, from: data) {
            value = stored
        } else if !useGlobalSettings, let data = defaults.data(forKey: prefix + "all"),
           let global = try? JSONDecoder().decode(AyuGhostConfiguration.self, from: data) {
            value = global
        } else {
            value = fallback
        }
        value.readRules = [:]
        value.typingRules = [:]
        if defaults.data(forKey: key) == nil, let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
        // Chat exceptions always belong to this account, even in global switch mode.
        if let data = defaults.data(forKey: prefix + "peers." + accountKey), let rules = try? JSONDecoder().decode(PeerRules.self, from: data) {
            value.readRules = rules.read
            value.typingRules = rules.typing
        }
        return value
    }

    public func update(accountPath: String, fallback: AyuGhostConfiguration, _ update: (inout AyuGhostConfiguration) -> Void) {
        lock.lock()
        var value = configuration(accountPath: accountPath, fallback: fallback)
        update(&value)
        let accountKey = URL(fileURLWithPath: accountPath).lastPathComponent
        let key = prefix + (useGlobalSettings ? "all" : "account." + accountKey)
        if let data = try? JSONEncoder().encode(PeerRules(read: value.readRules, typing: value.typingRules)) {
            defaults.set(data, forKey: prefix + "peers." + accountKey)
        }
        value.readRules = [:]
        value.typingRules = [:]
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
        lock.unlock()
        NotificationCenter.default.post(name: .ayuGhostSettingsChanged, object: nil)
    }
}
