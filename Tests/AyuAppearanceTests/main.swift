import Foundation

private var checks = 0
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError(message) }
}

let suite = "AyuAppearanceTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let settings = AyuAppearanceSettings(defaults: defaults)
check(!settings.localPremium && !settings.streamerMode && !settings.hideChatList, "appearance is opt-in")
settings.setLocalEmojiStatus(accountId: 42, fileId: 9_876_543_210, expiration: 500)
check(settings.localEmojiStatus(accountId: 42, now: 400) == nil, "disabled local appearance must not change visible status")
settings.localPremium = true
check(settings.localEmojiStatus(accountId: 42, now: 400) == 9_876_543_210, "64-bit IDs survive UserDefaults")
check(settings.localEmojiStatus(accountId: 99, now: 400) == nil, "statuses belong to individual accounts")
check(settings.localEmojiStatus(accountId: 42, now: 500) == nil, "status expires at deadline")
settings.setLocalEmojiStatus(accountId: 99, fileId: -123, expiration: nil)
check(settings.localEmojiStatus(accountId: 99, now: 600) == -123, "signed Int64 media identifiers are retained")
settings.streamerMode = true
settings.hideChatList = true
let restored = AyuAppearanceSettings(defaults: defaults)
check(restored.streamerMode && restored.hideChatList && restored.localPremium, "privacy switches persist")
check(restored.localEmojiStatus(accountId: 99, now: 600) == -123, "per-account status persists")
settings.setLocalEmojiStatus(accountId: 99, fileId: nil, expiration: nil)
check(restored.localEmojiStatus(accountId: 99, now: 600) == nil, "reset removes local status")
defaults.set(["fileId": "invalid"], forKey: "ayu.appearance.v1.emoji.42")
check(settings.localEmojiStatus(accountId: 42, now: 600) == nil, "corrupt storage is ignored")
settings.setLocalEmojiStatus(accountId: 42, fileId: 0, expiration: nil)
check(defaults.object(forKey: "ayu.appearance.v1.emoji.42") == nil, "zero is not an emoji ID")
print("Passed \(checks) appearance persistence checks")
