# Message archive implementation and limits

The archive is implemented in `AyuHistoryModel.swift`, `AyuHistoryStore.swift`, `AyuHistoryMediaBudget.swift`, and `AyuHistoryController.swift`. This document describes the implementation, not proof of device behavior. Follow [DEVICE_TEST_MATRIX.md](DEVICE_TEST_MATRIX.md) for runtime acceptance.

## Capture and identity

- The server update replay hooks capture old message versions before `.EditMessage` is applied and capture locally available messages before remote deletion is marked.
- `PendingMessages/RequestEditMessage.swift` has a separate capture hook because an outgoing edit response updates the local message before the general replay path.
- Account isolation comes from the account's own Postbox database, plus explicit account/peer/namespace/message IDs in each record.
- Deleted records use a deterministic identity, so repeated deletion updates do not duplicate or erase retained content. Edits use distinct revision IDs after comparing text, text entities, and media.
- Normal interactive deletion still uses Telegram's ordinary deletion path. The archive does not cancel the user's outgoing deletion or restore messages on the server.
- Secret chats, non-cloud namespaces and messages with autoremove/autoclear attributes remain excluded. Unreceived content cannot be captured.

## What is stored

Records include original and observed timestamps, original edit time, author/chat IDs and display names, message namespace and ID, grouping/thread IDs, global unique ID, flags, forward metadata, text, and independently serialized Postbox attributes/media. This preserves entities, reactions and media attributes in the snapshot even though the current archive browser renders plain text.

Attachment metadata includes resource ID, original name, MIME type, size, dimensions, duration, role and an optional retained filename. Retention covers the primary file, the best available image representation, downloaded previews, video covers/representations, downloaded alternatives, and already accessible full media inside paid-content/invoice wrappers. Locked previews are not treated as unlocked content. Traversal is bounded to four levels and 64 resource descriptors per message; the serialized media snapshot still contains the original metadata.

Only completed local resources are retained. The archive does not start a network download for a missing file. Generated MIME-based names make nameless voice/video attachments shareable with an appropriate extension. Missing files stay explicitly unavailable.

## Durability and capacity

- Metadata lives in durable Postbox ordered collection `0x41797548`, not Telegram's evictable item cache.
- Retained files live in `ayugram-history-media` beside the account's `media` directory. They survive MediaBox cache eviction. Account deletion/uninstallation may delete the account container; this is not an external backup.
- Completed MediaBox resources are linked into this directory when possible, otherwise copied. A link retains the file inode after the cache path is removed. Existing MediaBox move/copy paths were reviewed; device tests must still verify byte preservation for replaced media and cache cleaning.
- Media quota is configurable. A cached per-directory index avoids a full directory scan for every attachment in an update batch. The index rebuilds from disk after restart/invalidation; only generated archive filenames are eligible for eviction.
- Metadata capacity is explicitly bounded at **20,000 records or 64 MB of encoded metadata** because the present ordered-list browser materializes records. On exhaustion it stops accepting new snapshots and displays a capacity notice; it does not silently discard old text. A transactional preferences counter tracks count and encoded bytes.
- Before file retention, capture reserves metadata room; the final encoded size is checked again. Clearing records lowers the counters and clears the capacity notice.
- There is no claim that the current implementation meets performance targets at the maximum capacity. Instruments measurements at 1,000/10,000/20,000 records remain required. An indexed paginated archive would be needed for substantially larger datasets.

## Failure and crash behavior

- File retention failure leaves a readable text/metadata record with an unavailable file, rather than throwing out the Telegram update.
- File retention precedes the Postbox transaction commit. A crash in that interval can leave an orphan retained file. Opening the archive runs cleanup against committed record references on the account Postbox queue.
- Orphan cleanup stops if any archive record cannot be decoded: an unreadable record may still own a file. It only considers generated filenames inside the account archive directory.
- Clearing an archive entry first removes its unshared retained files. If removal fails, its record remains and the UI reports a retryable error. Other accounts and live Telegram messages are not modified.
- Media quota eviction can intentionally make an old attachment unavailable while retaining its metadata. Browser availability is checked against the actual file, not merely against a stored path.

## JSON interchange

The version-1 JSON format is this iOS implementation's metadata backup. It is **not** claimed compatible with AyuGram Android/Desktop SQLite databases. It contains message text, metadata and opaque attribute/media snapshots; it does not embed retained files. Files can be shared separately from a record.

Import is bounded to 32 MB of input, checks version/account identity/record IDs and field limits, rejects duplicate IDs within a document, and unconditionally drops imported filesystem references. Binary Postbox snapshots from imported documents are stored opaquely and are not decoded by the browser. Merge skips already present records and reports the actual number added, including when metadata capacity is reached. Input is read in bounded chunks to handle files that grow after the size check.

## Automated checks

Run the standalone model/filesystem checks with the same Swift toolchain as the app:

```sh
swiftc -warnings-as-errors \
  submodules/TelegramCore/Sources/State/AyuHistoryModel.swift \
  submodules/TelegramCore/Sources/State/AyuHistoryMediaBudget.swift \
  Tests/AyuHistoryTests/main.swift -o /tmp/ayu-history-tests
/tmp/ayu-history-tests
```

These cover Unicode and 64-bit identity round trips, metadata-only backups, media-only records, format/account/path/size rejection, include/exclude policy, chat/bot/media policies, metadata capacity arithmetic, retained-file survival after cache unlink, disk-index rebuild and safe media eviction. They do not compile the complete TelegramCore/UI modules and do not prove hook execution on an iPhone; the full build and device matrix are separate checks.
