import Foundation

/// Caches directory usage so a deletion batch does not rescan all retained files per message.
/// Callers serialize retention operations on the account's Postbox queue.
final class AyuHistoryMediaBudget {
    static let shared = AyuHistoryMediaBudget()

    private struct Entry {
        let url: URL
        let bytes: Int64
        let created: Date
    }

    private struct Directory {
        var files: [String: Entry]
        var used: Int64
    }

    private let lock = NSLock()
    private var directories: [String: Directory] = [:]

    func invalidate(directory: URL) {
        lock.lock()
        defer { lock.unlock() }
        directories.removeValue(forKey: directory.path)
    }

    func didRetain(url: URL, bytes: Int64) {
        lock.lock()
        defer { lock.unlock() }
        let path = url.deletingLastPathComponent().path
        guard var directory = directories[path] else { return }
        if let previous = directory.files[url.lastPathComponent] { directory.used -= previous.bytes }
        directory.files[url.lastPathComponent] = Entry(url: url, bytes: bytes, created: Date())
        directory.used += bytes
        directories[path] = directory
    }

    func makeRoom(directory: URL, requiredBytes: Int64, limitBytes: Int64) throws -> Bool {
        guard requiredBytes >= 0 else { return false }
        guard limitBytes > 0 else { return true }
        guard requiredBytes <= limitBytes else { return false }
        lock.lock()
        defer { lock.unlock() }
        let fileManager = FileManager.default
        var state: Directory
        if let cached = directories[directory.path] {
            state = cached
        } else {
            let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey], options: [.skipsHiddenFiles])
            state = Directory(files: [:], used: 0)
            for url in urls where AyuHistoryPolicy.safeAttachmentName(url.lastPathComponent) {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                let bytes = Int64(values.fileSize ?? 0)
                state.files[url.lastPathComponent] = Entry(url: url, bytes: bytes, created: values.creationDate ?? .distantPast)
                state.used += bytes
            }
        }
        if state.used > limitBytes - requiredBytes {
            for entry in state.files.values.sorted(by: { $0.created < $1.created }) where state.used > limitBytes - requiredBytes {
                do {
                    if fileManager.fileExists(atPath: entry.url.path) { try fileManager.removeItem(at: entry.url) }
                    state.files.removeValue(forKey: entry.url.lastPathComponent)
                    state.used -= entry.bytes
                } catch {
                    // Persist successful removals even when a later file is temporarily inaccessible.
                    directories[directory.path] = state
                    throw error
                }
            }
        }
        directories[directory.path] = state
        return state.used <= limitBytes - requiredBytes
    }
}
