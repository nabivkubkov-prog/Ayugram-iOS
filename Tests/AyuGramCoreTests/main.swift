import Foundation

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
    guard condition() else { fatalError(description) }
    checks += 1
}

var configuration = AyuGhostConfiguration()
expect(!configuration.isEnabled, "Fresh installs keep normal Telegram behavior")
configuration.lockedOptions = [.online]
configuration.setEnabled(true)
expect(!configuration.hideOnline && configuration.hideTyping && configuration.hideReadReceipts, "Locked online choice survives the master toggle")
configuration.setEnabled(false)
expect(!configuration.isEnabled, "Unlocked switches disable together")
configuration.setEnabled(true)
let receiptMethods = ["messages.readHistory", "messages.readEncryptedHistory", "channels.readHistory", "messages.readDiscussion", "messages.readSavedHistory", "messages.readMessageContents", "channels.readMessageContents", "messages.readMentions", "messages.readReactions", "stories.readStories", "stories.incrementStoryViews"]
for method in receiptMethods {
    expect(configuration.suppressesReceipt(function: method), "Receipt path escapes ghost policy: \(method)")
}
for method in ["messages.getHistory", "messages.sendMessage", "auth.signIn", "messages.sendMedia", "messages.getMessages", "upload.getFile"] {
    expect(!configuration.suppressesReceipt(function: method), "Ghost policy must not block content retrieval, login, or sending: \(method)")
}
configuration.readRules["17"] = .alwaysAllow
configuration.readRules["18"] = .alwaysHide
expect(!configuration.suppressesReceipt(function: "messages.readMessageContents", peerId: 17), "Explicit read exception covers voice/mention receipts")
expect(configuration.suppressesReceipt(function: "messages.readHistory", peerId: 18), "Never-read rule wins")
expect(configuration.suppressesReceipt(function: "messages.readHistory", peerId: 19), "Unknown peer inherits")
configuration.hideReadReceipts = false
expect(configuration.hidesReadReceipts(peerId: 18), "Never-read exception survives disabled master read option")
expect(!configuration.hidesReadReceipts(peerId: 19), "Unlisted peers retain ordinary behavior")
configuration.typingRules["17"] = .alwaysAllow
expect(!configuration.hidesTyping(peerId: 17), "Typing exception resolves separately")
expect(configuration.hideStories, "Read exceptions do not reveal story views")
let roundTrip = try JSONDecoder().decode(AyuGhostConfiguration.self, from: JSONEncoder().encode(configuration))
expect(roundTrip == configuration, "Policies, locks, and rules round-trip")

let suite = "AyuGramTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let preferences = AyuGhostPreferences(defaults: defaults)
preferences.update(accountPath: "/container/account-1", fallback: configuration) { $0.hideOnline = true }
preferences.update(accountPath: "/container/account-1", fallback: configuration) { $0.readRules["99"] = .alwaysAllow }
expect(preferences.configuration(accountPath: "/container/account-1", fallback: configuration).readRules["99"] == .alwaysAllow, "The account retains its chat exception")
expect(preferences.configuration(accountPath: "/container/account-2", fallback: configuration).readRules["99"] == nil, "Global switches do not leak another account's chat exceptions")
expect(preferences.configuration(accountPath: "/container/account-2", fallback: AyuGhostConfiguration()).hideOnline, "Global mode shares choices")
preferences.useGlobalSettings = false
preferences.update(accountPath: "/container/account-1", fallback: AyuGhostConfiguration()) { $0.hideOnline = false }
expect(!preferences.configuration(accountPath: "/container/account-1", fallback: configuration).hideOnline, "Account one can override global snapshot")
expect(preferences.configuration(accountPath: "/container/account-2", fallback: AyuGhostConfiguration()).hideOnline, "Account two remains isolated")
let restarted = AyuGhostPreferences(defaults: defaults)
expect(!restarted.configuration(accountPath: "/new-container/account-1", fallback: configuration).hideOnline, "Policy survives process/container-path change")
preferences.useGlobalSettings = true
expect(preferences.configuration(accountPath: "/container/account-1", fallback: configuration).hideOnline, "Returning to global settings restores the global policy")
defaults.set(Data("invalid json".utf8), forKey: "ayu.ghost.v1.all")
expect(preferences.configuration(accountPath: "/container/account-1", fallback: configuration).hideStories == configuration.hideStories, "Corrupt persisted data falls back to prior privacy choices")
expect(preferences.configuration(accountPath: "/container/account-1", fallback: configuration).readRules["99"] == .alwaysAllow, "Corrupt switch data does not erase per-account exceptions")
print("AyuGram ghost policy: \(checks) checks passed")
