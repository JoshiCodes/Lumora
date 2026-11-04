import AppKit
import IOKit.ps

/// Tracks system state that should pause the wallpaper.
@MainActor
final class PlaybackConditions: ObservableObject {
    @Published private(set) var isOnBattery = false
    @Published private(set) var isLowPowerMode = false
    @Published private(set) var isAsleep = false
    @Published private(set) var isLocked = false
    @Published private(set) var isSessionInactive = false
    @Published private(set) var isScreenSaverRunning = false

    private var tokens: [NSObjectProtocol] = []

    init() {
        refreshPowerState()

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.isAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.isAsleep = false }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.isAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.isAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.isSessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.isSessionInactive = false }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.isLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.isLocked = false }
        observe(distributed, Notification.Name("com.apple.screensaver.didstart")) { $0.isScreenSaverRunning = true }
        observe(distributed, Notification.Name("com.apple.screensaver.didstop")) { $0.isScreenSaverRunning = false }

        observe(.default, .NSProcessInfoPowerStateDidChange) { $0.refreshPowerState() }
        watchPowerSource()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ update: @escaping (PlaybackConditions) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
            }
        }
        tokens.append(token)
    }

    private func watchPowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let conditions = Unmanaged<PlaybackConditions>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { conditions.refreshPowerState() }
        }, context)?.takeRetainedValue()

        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func refreshPowerState() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else {
            isOnBattery = false
            return
        }
        isOnBattery = (type as String) == kIOPMBatteryPowerKey
    }
}
