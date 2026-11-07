import Foundation
import UIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import SGSimpleSettings

struct AyuChatMessageFilterState {
    let filter: AyuMessageFilter
    let blockedPeerIds: Set<PeerId>
}

func ayuChatMessageFilterState(context: AccountContext) -> Signal<AyuChatMessageFilterState, NoError> {
    let preferences = Signal<AyuMessageFilterPreferences, NoError> { subscriber in
        let emit = {
            subscriber.putNext(AyuMessageFilterStore.shared.preferences)
        }
        let settingsObserver = NotificationCenter.default.addObserver(forName: AyuMessageFilterStore.didChange, object: nil, queue: .main) { _ in
            emit()
        }
        let foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            emit()
        }
        emit()
        return ActionDisposable {
            NotificationCenter.default.removeObserver(settingsObserver)
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }
    return (preferences
    |> deliverOnMainQueue
    |> mapToSignal { preferences -> Signal<AyuChatMessageFilterState, NoError> in
        let filter = AyuMessageFilter(preferences: preferences)
        guard preferences.enabled && preferences.hideBlockedAuthors else {
            return .single(AyuChatMessageFilterState(filter: filter, blockedPeerIds: Set()))
        }
        return Signal { subscriber in
            let blockedContext = BlockedPeersContext(account: context.account, subject: .blocked)
            var lastRequestedCount = -1
            let disposable = blockedContext.state.start(next: { [weak blockedContext] state in
                subscriber.putNext(AyuChatMessageFilterState(filter: filter, blockedPeerIds: Set(state.peers.map { $0.peerId })))
                // Exhaust the paginated block list, while guarding against a
                // server returning the same empty page repeatedly.
                if !state.isLoadingMore && state.canLoadMore && state.peers.count != lastRequestedCount {
                    lastRequestedCount = state.peers.count
                    Queue.mainQueue().async {
                        blockedContext?.loadMore()
                    }
                }
            })
            return ActionDisposable {
                disposable.dispose()
                withExtendedLifetime(blockedContext) {}
            }
        }
    })
    |> runOn(Queue.mainQueue())
}
