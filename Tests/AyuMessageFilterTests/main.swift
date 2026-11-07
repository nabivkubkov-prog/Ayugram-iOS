import Foundation

var assertions = 0
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !value() { fatalError(message) }
}

func filter(_ rules: [AyuMessageFilterRule], sponsored: Bool = false, blocked: Bool = false) -> AyuMessageFilter {
    return AyuMessageFilter(preferences: AyuMessageFilterPreferences(enabled: true, hideSponsoredMessages: sponsored, hideBlockedAuthors: blocked, rules: rules))
}

let defaults = AyuMessageFilter(preferences: AyuMessageFilterPreferences())
expect(!defaults.shouldHide(text: "anything", isOutgoing: false, isService: false, isSponsored: true, isAuthorBlocked: true), "Filters must be opt in")
let literal = filter([AyuMessageFilterRule(pattern: "РЕКЛАМА")])
expect(literal.shouldHide(text: "😀 здесь реклама", isOutgoing: false, isService: false), "Case-insensitive Cyrillic should match after emoji")
expect(!literal.shouldHide(text: "РЕКЛАМА", isOutgoing: true, isService: false), "Own messages must remain visible")
expect(!literal.shouldHide(text: "РЕКЛАМА", isOutgoing: false, isService: true), "Service messages must remain visible")
expect(!literal.shouldHide(text: "", isOutgoing: false, isService: false), "Empty media captions must not match text rules")

let caseSensitive = filter([AyuMessageFilterRule(pattern: "Promo", caseSensitive: true)])
expect(caseSensitive.shouldHide(text: "Promo", isOutgoing: false, isService: false), "Exact case should match")
expect(!caseSensitive.shouldHide(text: "promo", isOutgoing: false, isService: false), "Case-sensitive rule must preserve different case")
let escaped = filter([AyuMessageFilterRule(pattern: "a+b")])
expect(escaped.shouldHide(text: "a+b", isOutgoing: false, isService: false), "Literal metacharacters must remain literal")
expect(!escaped.shouldHide(text: "aaab", isOutgoing: false, isService: false), "Literal rules must not become regex")

let regex = filter([AyuMessageFilterRule(pattern: "скидк[аи]\\s+[0-9]+%", isRegularExpression: true)])
expect(regex.shouldHide(text: "😀 СКИДКА 50%", isOutgoing: false, isService: false), "Regex must use UTF-16 ranges for Unicode text")
expect(!regex.shouldHide(text: "скидка завтра", isOutgoing: false, isService: false), "Regex nonmatch must remain visible")
let invalid = AyuMessageFilterRule(pattern: "[", isRegularExpression: true)
expect(invalid.validationError != nil, "Invalid regex must be rejected in the editor")
expect(!filter([invalid]).shouldHide(text: "[", isOutgoing: false, isService: false), "Corrupt stored regex must fail open")
expect(AyuMessageFilterRule(pattern: "   ").validationError != nil, "Empty rules must be rejected")
expect(AyuMessageFilterRule(pattern: String(repeating: "x", count: 2049)).validationError != nil, "Very long rules must be rejected")
expect(!filter([AyuMessageFilterRule(pattern: "promo", enabled: false)]).shouldHide(text: "promo", isOutgoing: false, isService: false), "Disabled rules must not hide messages")
expect(!filter([AyuMessageFilterRule(pattern: "^", isRegularExpression: true)]).shouldHide(text: "message", isOutgoing: false, isService: false), "Zero-length regex matches must not hide every message")

let metadata = filter([], sponsored: true, blocked: true)
expect(metadata.hidesSponsoredMessages, "Sponsored insertion must consult the enabled flag")
expect(metadata.shouldHide(text: "", isOutgoing: false, isService: false, isSponsored: true), "Sponsored media must be filterable")
expect(metadata.shouldHide(text: "", isOutgoing: false, isService: false, isAuthorBlocked: true), "Blocked authors' media must be filterable")
expect(!metadata.shouldHide(text: "hello", isOutgoing: true, isService: false, isAuthorBlocked: true), "Own messages override metadata filters")
expect(!metadata.shouldHide(text: "joined", isOutgoing: false, isService: true, isAuthorBlocked: true), "Service messages override metadata filters")
expect(!filter([]).shouldHide(text: "hello", isOutgoing: false, isService: false, isAuthorBlocked: true), "Blocked authors remain visible when their option is off")

let expensive = filter([AyuMessageFilterRule(pattern: "(a+)+$", isRegularExpression: true)])
let started = ProcessInfo.processInfo.systemUptime
expect(!expensive.shouldHide(text: String(repeating: "a", count: 4000) + "!", isOutgoing: false, isService: false), "Expensive nonmatch must fail open")
expect(ProcessInfo.processInfo.systemUptime - started < 1.0, "Regex progress budget must prevent UI stalls")

let suite = "ayu.filter.tests." + UUID().uuidString
let userDefaults = UserDefaults(suiteName: suite)!
defer { userDefaults.removePersistentDomain(forName: suite) }
let store = AyuMessageFilterStore(defaults: userDefaults)
expect(!store.preferences.enabled, "An empty store must preserve chat content")
store.update { settings in
    settings.enabled = true
    settings.rules = [AyuMessageFilterRule(id: "test-rule", pattern: "тест", isRegularExpression: true)]
}
let restarted = AyuMessageFilterStore(defaults: userDefaults)
expect(restarted.preferences.enabled, "Enabled state must survive reload")
expect(restarted.preferences.rules.first?.pattern == "тест", "Unicode patterns must survive reload")
restarted.update { $0.rules.removeAll() }
expect(store.preferences.rules.isEmpty, "Deleting rules must persist")
userDefaults.set(Data("invalid JSON".utf8), forKey: AyuMessageFilterStore.storageKey)
expect(!store.preferences.enabled, "Corrupt settings must preserve messages")
print("AyuMessageFilter: \(assertions) assertions passed")
