import Foundation
import Postbox
import SwiftSignalKit

public enum AyuForwardError: Error {
    case unsupportedContent, downloadFailed, storageFailed
}

private func ayuForwardLocalResource(account: Account, message: Message, media: Media, resource: TelegramMediaResource) -> Signal<LocalFileMediaResource, AyuForwardError> {
    return Signal<LocalFileMediaResource, AyuForwardError> { subscriber in
        let disposables = DisposableSet()
        let reference = MediaResourceReference.media(media: .message(message: MessageReference(message), media: media), resource: resource)
        disposables.add(fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .peer(message.id.peerId), userContentType: .other, reference: reference).start(error: { _ in
            subscriber.putError(.downloadFailed)
        }))
        disposables.add((account.postbox.mediaBox.resourceData(resource)
        |> filter { $0.complete }
        |> take(1)).start(next: { data in
            let local = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max), size: data.size)
            account.postbox.mediaBox.copyResourceData(from: resource.id, to: local.id, synchronous: true)
            // A cache eviction or a full disk must not enqueue an empty upload.
            disposables.add((account.postbox.mediaBox.resourceData(local, attemptSynchronously: true) |> take(1)).start(next: { copied in
                guard copied.complete && copied.size == data.size else {
                    subscriber.putError(.storageFailed)
                    return
                }
                subscriber.putNext(local)
                subscriber.putCompletion()
            }))
        }))
        return disposables
    }
    |> timeout(600.0, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.downloadFailed))
}

private func ayuForwardMedia(account: Account, message: Message) -> Signal<AnyMediaReference?, AyuForwardError> {
    for media in message.media {
        if let image = media as? TelegramMediaImage, let largest = largestImageRepresentation(image.representations) {
            return ayuForwardLocalResource(account: account, message: message, media: image, resource: largest.resource)
            |> map { resource -> AnyMediaReference? in
                let copy = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min ... Int64.max)), representations: [TelegramMediaImageRepresentation(dimensions: largest.dimensions, resource: resource, progressiveSizes: [], immediateThumbnailData: largest.immediateThumbnailData)], immediateThumbnailData: image.immediateThumbnailData, reference: nil, partialReference: nil, flags: [])
                return .standalone(media: copy)
            }
        } else if let file = media as? TelegramMediaFile {
            return ayuForwardLocalResource(account: account, message: message, media: file, resource: file.resource)
            |> map { resource -> AnyMediaReference? in
                let copy = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: file.immediateThumbnailData, mimeType: file.mimeType, size: file.size, attributes: file.attributes, alternativeRepresentations: [])
                return .standalone(media: copy)
            }
        } else if let location = media as? TelegramMediaMap {
            // Copy the received position, never start a new live-location broadcast.
            let copy = TelegramMediaMap(latitude: location.latitude, longitude: location.longitude, heading: location.heading, accuracyRadius: location.accuracyRadius, venue: location.venue, address: location.address, liveBroadcastingTimeout: nil, liveProximityNotificationRadius: nil)
            return .single(.standalone(media: copy))
        } else if media is TelegramMediaContact {
            return .single(.standalone(media: media))
        } else if media is TelegramMediaWebpage {
            // The destination generates a new preview from the copied text.
            continue
        } else {
            return .fail(.unsupportedContent)
        }
    }
    return message.text.isEmpty ? .fail(.unsupportedContent) : .single(nil)
}

/// Copies received content as new messages, reuploading cloud files instead of
/// forwarding a protected message or reusing its protected cloud-media reference.
public func ayuForwardMessages(account: Account, messages: [Message], to peerId: PeerId, threadId: Int64? = nil) -> Signal<[MessageId?], AyuForwardError> {
    let messages = messages.sorted { $0.index < $1.index }
    guard !messages.isEmpty && messages.count <= 100 else { return .fail(.unsupportedContent) }
    var groupingKeys: [Int64: Int64] = [:]
    for message in messages {
        if let key = message.groupingKey, groupingKeys[key] == nil {
            groupingKeys[key] = Int64.random(in: Int64.min ... Int64.max)
        }
    }
    var prepared: Signal<[EnqueueMessage], AyuForwardError> = .single([])
    for message in messages {
        guard message.id.peerId.namespace != Namespaces.Peer.SecretChat,
              !message.attributes.contains(where: { $0 is AutoremoveTimeoutMessageAttribute || $0 is AutoclearTimeoutMessageAttribute }) else {
            return .fail(.unsupportedContent)
        }
        prepared = prepared |> mapToSignal { previous in
            return ayuForwardMedia(account: account, message: message) |> map { media in
                var attributes: [MessageAttribute] = []
                if let entities = message.textEntitiesAttribute { attributes.append(entities) }
                if message.attributes.contains(where: { $0 is MediaSpoilerMessageAttribute }) { attributes.append(MediaSpoilerMessageAttribute()) }
                let copy = EnqueueMessage.message(text: message.text, attributes: attributes, inlineStickers: [:], mediaReference: media, threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: message.groupingKey.flatMap { groupingKeys[$0] }, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                return previous + [copy]
            }
        }
    }
    return prepared |> mapToSignal { copies in
        return enqueueMessages(account: account, peerId: peerId, messages: copies) |> castError(AyuForwardError.self)
    }
}
