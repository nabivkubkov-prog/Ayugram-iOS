import Foundation

public struct AyuMessageFilterRule: Codable, Equatable {
    public var id: String
    public var pattern: String
    public var isRegularExpression: Bool
    public var caseSensitive: Bool
    public var enabled: Bool

    public init(id: String = UUID().uuidString, pattern: String, isRegularExpression: Bool = false, caseSensitive: Bool = false, enabled: Bool = true) {
        self.id = id
        self.pattern = pattern
        self.isRegularExpression = isRegularExpression
        self.caseSensitive = caseSensitive
        self.enabled = enabled
    }

    public var validationError: String? {
        if self.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "empty"
        }
        if self.pattern.utf16.count > 2048 {
            return "tooLong"
        }
        if self.isRegularExpression {
            do {
                _ = try NSRegularExpression(pattern: self.pattern, options: self.caseSensitive ? [] : [.caseInsensitive])
            } catch {
                return "invalidRegex"
            }
        }
        return nil
    }
}

public struct AyuMessageFilterPreferences: Codable, Equatable {
    public var enabled: Bool
    public var hideSponsoredMessages: Bool
    public var hideBlockedAuthors: Bool
    public var rules: [AyuMessageFilterRule]

    public init(enabled: Bool = false, hideSponsoredMessages: Bool = false, hideBlockedAuthors: Bool = false, rules: [AyuMessageFilterRule] = []) {
        self.enabled = enabled
        self.hideSponsoredMessages = hideSponsoredMessages
        self.hideBlockedAuthors = hideBlockedAuthors
        self.rules = rules
    }
}

public final class AyuMessageFilter {
    private struct CompiledRule {
        let rule: AyuMessageFilterRule
        let expression: NSRegularExpression?
    }

    public let preferences: AyuMessageFilterPreferences
    private let rules: [CompiledRule]

    public init(preferences: AyuMessageFilterPreferences) {
        self.preferences = preferences
        self.rules = preferences.rules.prefix(200).compactMap { rule in
            guard rule.enabled, rule.validationError == nil else {
                return nil
            }
            let expression: NSRegularExpression?
            if rule.isRegularExpression {
                expression = try? NSRegularExpression(pattern: rule.pattern, options: rule.caseSensitive ? [] : [.caseInsensitive])
            } else {
                expression = nil
            }
            return CompiledRule(rule: rule, expression: expression)
        }
    }

    public var hidesSponsoredMessages: Bool {
        return self.preferences.enabled && self.preferences.hideSponsoredMessages
    }

    public func shouldHide(text: String, isOutgoing: Bool, isService: Bool, isSponsored: Bool = false, isAuthorBlocked: Bool = false) -> Bool {
        guard self.preferences.enabled, !isOutgoing, !isService else {
            return false
        }
        if self.preferences.hideSponsoredMessages && isSponsored {
            return true
        }
        if self.preferences.hideBlockedAuthors && isAuthorBlocked {
            return true
        }
        guard !text.isEmpty else {
            return false
        }
        // ICU reports progress for expensive expressions. Stop an expression
        // which exceeds the per-message budget rather than freezing the chat.
        let deadline = ProcessInfo.processInfo.systemUptime + 0.02
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        for compiled in self.rules {
            if ProcessInfo.processInfo.systemUptime >= deadline {
                return false
            }
            if let expression = compiled.expression {
                var found = false
                expression.enumerateMatches(in: text, options: [.reportProgress], range: range) { result, _, stop in
                    if let result = result, result.range.length > 0 {
                        found = true
                        stop.pointee = true
                    } else if ProcessInfo.processInfo.systemUptime >= deadline {
                        stop.pointee = true
                    }
                }
                if found {
                    return true
                }
            } else {
                let options: String.CompareOptions = compiled.rule.caseSensitive ? [] : [.caseInsensitive]
                if text.range(of: compiled.rule.pattern, options: options) != nil {
                    return true
                }
            }
        }
        return false
    }
}

public final class AyuMessageFilterStore {
    public static let shared = AyuMessageFilterStore()
    public static let didChange = Notification.Name("ayu.messageFilters.changed")
    public static let storageKey = "ayu.messageFilters.v1"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var preferences: AyuMessageFilterPreferences {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.load()
    }

    private func load() -> AyuMessageFilterPreferences {
        if let data = self.defaults.data(forKey: Self.storageKey), let value = try? JSONDecoder().decode(AyuMessageFilterPreferences.self, from: data) {
            return value
        }
        return AyuMessageFilterPreferences()
    }

    public func update(_ transform: (inout AyuMessageFilterPreferences) -> Void) {
        self.lock.lock()
        var value = self.load()
        transform(&value)
        value.rules = Array(value.rules.prefix(200))
        if let data = try? JSONEncoder().encode(value) {
            self.defaults.set(data, forKey: Self.storageKey)
        }
        self.lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
