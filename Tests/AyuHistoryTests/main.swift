import Foundation

private var checks = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() {
        fatalError("AyuHistory test failed: \(message)")
    }
}

private func expectFailure(_ message: String, _ operation: () throws -> Void) {
    checks += 1
    do {
        try operation()
        fatalError("AyuHistory test failed: expected rejection for \(message)")
    } catch {}
}

private func record(id: String = "d:858993459200042:0:7", accountId: Int64 = 9_007_199_254_740_999, text: String = "Привет 👋\n**raw text**", kind: AyuHistoryKind = .deleted, fileName: String? = "123E4567-E89B-12D3-A456-426614174000.jpg") -> AyuHistoryRecord {
    return AyuHistoryRecord(
        id: id, accountId: accountId, peerId: 858_993_459_200_042, namespace: 0, messageId: 7,
        kind: kind, originalTimestamp: 1_700_000_000, capturedAt: 1_700_000_042,
        threadId: 19, groupingKey: 123, authorId: 321, authorName: "Тестовый автор", peerName: "Test group",
        text: text, originalEditTimestamp: nil, globallyUniqueId: nil, messageFlags: 4, forwardInfo: nil,
        attributes: [Data([0, 1, 2, 255])], media: [Data([3, 4, 5])],
        attachments: [AyuHistoryAttachment(resourceId: "resource-1", originalName: "фото.jpg", mimeType: "image/jpeg", size: 1024, retainedFileName: fileName)]
    )
}

let original = record()
let backup = AyuHistoryBackup(records: [original])
let encoded = try backup.encoded()
let restored = try AyuHistoryBackup.decoded(encoded, accountId: original.accountId)
expect(restored.records.count == 1, "one record round-trips")
expect(restored.records[0].text == original.text, "Unicode, newlines and literal markup survive")
expect(restored.records[0].accountId == original.accountId, "64-bit IDs remain exact above JavaScript's safe integer range")
expect(restored.records[0].peerId == original.peerId, "peer namespace bits remain intact")
expect(restored.records[0].threadId == 19 && restored.records[0].groupingKey == 123, "forum and album identity survive")
expect(restored.records[0].attributes == original.attributes && restored.records[0].media == original.media, "opaque snapshots round-trip without decoding")
expect(restored.records[0].attachments[0].retainedFileName == nil, "JSON backup cannot claim a retained attachment is portable")
expect(restored.records[0].attachments[0].size == 1024, "missing attachment still retains metadata")

expectFailure("cross-account import") {
    _ = try AyuHistoryBackup.decoded(encoded, accountId: 222)
}
expectFailure("unsupported format") {
    var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    object["version"] = 999
    _ = try AyuHistoryBackup.decoded(JSONSerialization.data(withJSONObject: object), accountId: original.accountId)
}
expectFailure("duplicate record IDs") {
    let duplicateData = try JSONEncoder().encode(AyuHistoryBackup(records: [original, original]))
    _ = try AyuHistoryBackup.decoded(duplicateData, accountId: original.accountId)
}
expectFailure("truncated document") {
    _ = try AyuHistoryBackup.decoded(encoded.prefix(encoded.count / 2), accountId: original.accountId)
}
expectFailure("oversized input") {
    _ = try AyuHistoryBackup.decoded(Data(repeating: 0x20, count: AyuHistoryBackup.maximumBytes + 1), accountId: original.accountId)
}
expectFailure("oversized text field") {
    let oversized = record(text: String(repeating: "x", count: 1_000_001))
    _ = try AyuHistoryBackup.decoded(JSONEncoder().encode(AyuHistoryBackup(records: [oversized])), accountId: original.accountId)
}
let maliciousPath = record(fileName: "../../../../other-account/secret")
let sanitized = try AyuHistoryBackup.decoded(JSONEncoder().encode(AyuHistoryBackup(records: [maliciousPath])), accountId: original.accountId)
expect(sanitized.records[0].attachments[0].retainedFileName == nil, "import drops every supplied attachment path")

let imageOnly = record(id: "photo-only", text: "", kind: .edited)
let imageRoundTrip = try AyuHistoryBackup.decoded(AyuHistoryBackup(records: [imageOnly]).encoded(), accountId: original.accountId)
expect(imageRoundTrip.records[0].text.isEmpty && !imageRoundTrip.records[0].attachments.isEmpty, "media-only message is not discarded")
expect(imageRoundTrip.records[0].kind == .edited, "edit and deletion events remain distinguishable")

expect(original.matches(query: "ПРИВЕТ"), "Unicode case-insensitive text search")
expect(original.matches(query: "test GROUP"), "chat title search")
expect(original.matches(query: "автор"), "author search")
expect(original.matches(query: "  7  "), "trimmed message ID search")
expect(!original.matches(query: "missing value"), "nonmatching text is excluded")

expect(AyuHistoryPolicy.includes(accountId: 1, peerId: 2, selectedPeerIds: [], onlySelected: false), "default mode saves unlisted chats")
expect(!AyuHistoryPolicy.includes(accountId: 1, peerId: 2, selectedPeerIds: [], onlySelected: true), "empty allow-list saves nothing")
expect(!AyuHistoryPolicy.includes(accountId: 1, peerId: 2, selectedPeerIds: ["1:2"], onlySelected: false), "explicit deny-list excludes chat")
expect(AyuHistoryPolicy.includes(accountId: 1, peerId: 2, selectedPeerIds: ["1:2"], onlySelected: true), "explicit allow-list includes chat")
expect(AyuHistoryPolicy.includes(accountId: 3, peerId: 2, selectedPeerIds: ["1:2"], onlySelected: false), "one account's exclusion does not leak to another")

var chatRules = AyuHistoryChatRules()
chatRules.excludedMessageTypes.insert(.publicChannel)
chatRules.excludedMediaTypes.insert(.publicGroup)
chatRules.saveBotDialogs = false
chatRules.saveBotMessagesInGroups = false
expect(!chatRules.allowsMessages(category: .publicChannel, isBotDialog: false, isBotAuthor: false), "excluded channel type blocks snapshots")
expect(chatRules.allowsMessages(category: .privateChannel, isBotDialog: false, isBotAuthor: false), "private and public channels have independent policies")
expect(!chatRules.allowsMedia(category: .publicGroup), "media exclusion does not imply message exclusion")
expect(chatRules.allowsMessages(category: .publicGroup, isBotDialog: false, isBotAuthor: false), "group text remains allowed when media is excluded")
expect(!chatRules.allowsMessages(category: .privateChat, isBotDialog: true, isBotAuthor: true), "bot dialog exclusion")
expect(!chatRules.allowsMessages(category: .privateGroup, isBotDialog: false, isBotAuthor: true), "bot author exclusion inside group")
expect(chatRules.allowsMessages(category: .privateChat, isBotDialog: false, isBotAuthor: false), "human private chat remains allowed")
let restoredRules = try JSONDecoder().decode(AyuHistoryChatRules.self, from: JSONEncoder().encode(chatRules))
expect(restoredRules == chatRules, "chat policies round-trip")

expect(AyuHistoryCapacity().canInsert(bytes: 1024), "new archive has capacity")
expect(!AyuHistoryCapacity(records: AyuHistoryCapacity.maximumRecords, bytes: 0).canInsert(bytes: 1), "record cap stops insertion without evicting existing history")
expect(!AyuHistoryCapacity(records: 1, bytes: AyuHistoryCapacity.maximumBytes).canInsert(bytes: 1), "metadata byte cap")
expect(!AyuHistoryCapacity().canInsert(bytes: -1), "invalid negative byte count rejected")
expect(!AyuHistoryCapacity().canInsert(bytes: Int.max), "oversized record cannot overflow capacity arithmetic")

expect(AyuHistoryPolicy.safeAttachmentName("123E4567-E89B-12D3-A456-426614174000.jpg"), "generated attachment basename accepted")
for unsafe in ["../file.jpg", "/tmp/file.jpg", "C:\\private\\file.jpg", "123E4567-E89B-12D3-A456-426614174000../jpg", "123E4567-E89B-12D3-A456-426614174000.jpg/../file", "123E4567-E89B-12D3-A456-426614174000."] {
    expect(!AyuHistoryPolicy.safeAttachmentName(unsafe), "unsafe filename rejected: \(unsafe)")
}

let fileManager = FileManager.default
let testDirectory = fileManager.temporaryDirectory.appendingPathComponent("AyuHistoryTests-\(UUID().uuidString)", isDirectory: true)
try fileManager.createDirectory(at: testDirectory, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: testDirectory) }
let attachmentDirectory = testDirectory.appendingPathComponent("attachments", isDirectory: true)
try fileManager.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
let source = testDirectory.appendingPathComponent("source.bin")
let bytes = Data(repeating: 42, count: 80)
try bytes.write(to: source)
let retained = attachmentDirectory.appendingPathComponent(UUID().uuidString + ".bin")
let firstRoom = try AyuHistoryMediaBudget.shared.makeRoom(directory: attachmentDirectory, requiredBytes: 80, limitBytes: 100)
expect(firstRoom, "empty media directory has room")
try fileManager.linkItem(at: source, to: retained)
AyuHistoryMediaBudget.shared.didRetain(url: retained, bytes: 80)
try fileManager.removeItem(at: source)
let retainedBytes = try Data(contentsOf: retained)
expect(retainedBytes == bytes, "retained hard link survives deletion of the cache path")
let replacementRoom = try AyuHistoryMediaBudget.shared.makeRoom(directory: attachmentDirectory, requiredBytes: 80, limitBytes: 100)
expect(replacementRoom, "old files are evicted to make room")
expect(!fileManager.fileExists(atPath: retained.path), "old retained file actually removed")
let tooBig = try AyuHistoryMediaBudget.shared.makeRoom(directory: attachmentDirectory, requiredBytes: 101, limitBytes: 100)
expect(!tooBig, "single oversized attachment is rejected")

let second = attachmentDirectory.appendingPathComponent(UUID().uuidString + ".bin")
try bytes.write(to: second)
AyuHistoryMediaBudget.shared.didRetain(url: second, bytes: 80)
let unmanaged = attachmentDirectory.appendingPathComponent("do-not-touch.txt")
try Data(repeating: 1, count: 500).write(to: unmanaged)
AyuHistoryMediaBudget.shared.invalidate(directory: attachmentDirectory)
let rebuiltRoom = try AyuHistoryMediaBudget.shared.makeRoom(directory: attachmentDirectory, requiredBytes: 80, limitBytes: 100)
expect(rebuiltRoom, "usage index rebuilds from disk after restart/invalidation")
expect(!fileManager.fileExists(atPath: second.path), "rebuilt index respects existing retained files")
expect(fileManager.fileExists(atPath: unmanaged.path), "budget never deletes files outside its generated-name namespace")
let unlimited = try AyuHistoryMediaBudget.shared.makeRoom(directory: attachmentDirectory, requiredBytes: Int64.max, limitBytes: 0)
expect(unlimited, "explicit unlimited media policy has no artificial size cap")
AyuHistoryMediaBudget.shared.invalidate(directory: attachmentDirectory)

print("AyuHistory: \(checks) checks passed")
