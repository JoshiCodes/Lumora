import AppKit
import Combine
import Sparkle

/// Checks GitHub releases for new versions through Sparkle.
@MainActor
final class Updater: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    /// False when an administrator turned updates off; the MDM delivers new versions instead.
    let isAvailable: Bool
    private var controller: SPUStandardUpdaterController?

    override init() {
        isAvailable = !ManagedSettings.updatesDisabled
        super.init()
        guard isAvailable else { return }

        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var lastCheck: Date? {
        controller?.updater.lastUpdateCheckDate
    }

    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    // Lumora lives in the menu bar, so let Sparkle show scheduled updates without stealing focus.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                               forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        Task { @MainActor in NSApp.activate() }
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
}
