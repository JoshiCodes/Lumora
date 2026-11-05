import Foundation
import ServiceManagement

/// Settings an administrator can push with a configuration profile (MDM, e.g. Intune).
/// macOS puts those values in front of the user's own, so they always win. Lumora also
/// greys out the matching controls, so it's clear they're set by the organization.
enum ManagedSettings {
    /// Turns off Sparkle completely. Use this when the MDM rolls out new versions.
    static let disableUpdatesKey = "DisableUpdates"
    /// Registers Lumora as a login item on every launch.
    static let launchAtLoginKey = "LaunchAtLogin"

    static var updatesDisabled: Bool {
        UserDefaults.standard.bool(forKey: disableUpdatesKey)
    }

    static func isForced(_ key: String) -> Bool {
        UserDefaults.standard.objectIsForced(forKey: key)
    }

    static var isLaunchAtLoginForced: Bool {
        isForced(launchAtLoginKey)
    }

    /// Applies a forced login item setting.
    @MainActor
    static func applyLaunchAtLogin() {
        guard isLaunchAtLoginForced else { return }
        let wanted = UserDefaults.standard.bool(forKey: launchAtLoginKey)
        let service = SMAppService.mainApp
        do {
            if wanted, service.status != .enabled {
                try service.register()
            } else if !wanted, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("Lumora: couldn't apply the managed login item setting: \(error.localizedDescription)")
        }
    }
}
