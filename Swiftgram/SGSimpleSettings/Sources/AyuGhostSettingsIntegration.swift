import Foundation

public extension SGSimpleSettings {
    private var ayuLegacyGhostConfiguration: AyuGhostConfiguration {
        var configuration = AyuGhostConfiguration()
        configuration.hideReadReceipts = ghostHideReadReceipts
        configuration.hideOnline = ghostHideOnline
        configuration.hideTyping = ghostHideTyping
        configuration.hideStories = storyStealthMode
        return configuration
    }

    func ayuGhostSettings(accountPath: String) -> AyuGhostConfiguration {
        return AyuGhostPreferences.shared.configuration(accountPath: accountPath, fallback: ayuLegacyGhostConfiguration)
    }

    func updateAyuGhostSettings(accountPath: String, _ update: (inout AyuGhostConfiguration) -> Void) {
        AyuGhostPreferences.shared.update(accountPath: accountPath, fallback: ayuLegacyGhostConfiguration, update)
    }
}
