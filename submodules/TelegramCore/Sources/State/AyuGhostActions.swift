import Foundation
import Postbox
import TelegramApi
import SwiftSignalKit
import MtProtoKit
import SGSimpleSettings

/// Explicit, one-shot server read. It never temporarily disables another account's policy.
public func ayuReadChatOnServer(account: Account, peerId: PeerId, through messageId: MessageId? = nil) -> Signal<Bool, NoError> {
    return account.postbox.transaction { transaction -> (Api.InputPeer, Int32)? in
        guard peerId.namespace != Namespaces.Peer.SecretChat,
              let peer = transaction.getPeer(peerId), let input = apiInputPeer(peer),
              let topId = messageId ?? transaction.getTopPeerMessageId(peerId: peerId, namespace: Namespaces.Message.Cloud),
              topId.peerId == peerId, topId.namespace == Namespaces.Message.Cloud else { return nil }
        return (input, topId.id)
    }
    |> mapToSignal { target -> Signal<Bool, NoError> in
        guard let (peer, maxId) = target else { return .single(false) }
        switch peer {
        case let .inputPeerChannel(channelId, accessHash):
            return account.network.request(Api.functions.channels.readHistory(channel: .inputChannel(channelId: channelId, accessHash: accessHash), maxId: maxId), ayuPeerId: peerId, ayuBypassReadSuppression: true)
            |> map { result -> Bool in if case .boolTrue = result { return true }; return false }
            |> `catch` { _ in .single(false) }
        default:
            return account.network.request(Api.functions.messages.readHistory(peer: peer, maxId: maxId), ayuPeerId: peerId, ayuBypassReadSuppression: true)
            |> map { result -> Bool in
                if case let .affectedMessages(pts, ptsCount) = result {
                    account.stateManager.addUpdateGroups([.updatePts(pts: pts, ptsCount: ptsCount)])
                }
                return true
            }
            |> `catch` { _ in .single(false) }
        }
    }
}

public func ayuReadChatLocally(account: Account, peerId: PeerId) -> Signal<Void, NoError> {
    return account.postbox.transaction { transaction -> Void in
        // The incoming (server-update) path changes local state without queuing a read RPC.
        if let index = transaction.getTopPeerMessageIndex(peerId: peerId, namespace: Namespaces.Message.Cloud) {
            transaction.applyIncomingReadMaxId(index.id)
        }
    }
}

enum AyuReadInteraction { case send, reaction, poll }

func ayuRestoreOfflineAfterSend(network: Network) {
    let settings = SGSimpleSettings.shared.ayuGhostSettings(accountPath: network.basePath)
    if settings.hideOnline && settings.offlineAfterSend {
        let _ = (network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        |> `catch` { _ -> Signal<Api.Bool, NoError> in .single(.boolFalse) }).startStandalone()
    }
}

func ayuReadAfterInteraction(account: Account, peerId: PeerId, interaction: AyuReadInteraction) {
    let settings = SGSimpleSettings.shared.ayuGhostSettings(accountPath: account.basePath)
    let enabled: Bool
    switch interaction {
    case .send: enabled = settings.readOnSend
    case .reaction: enabled = settings.readOnReaction
    case .poll: enabled = settings.readOnPoll
    }
    if enabled && settings.readRules[String(peerId.toInt64())] != .alwaysHide {
        let _ = ayuReadChatOnServer(account: account, peerId: peerId).startStandalone()
    }
}
