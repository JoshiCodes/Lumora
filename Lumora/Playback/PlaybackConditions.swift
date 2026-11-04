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
    @Published private(set) var isUserIdle = false
    @Published private(set) var isOverheating = false

    /// Seconds without keyboard or mouse input before the user counts as away. Zero turns it off.
    var idleThreshold: TimeInterval = 0 {
        didSet { checkIdle() }
    }

    private var tokens: [NSObjectProtocol] = []
    private var idleTimer: Timer?

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
        observe(.default, ProcessInfo.thermalStateDidChangeNotification) { $0.refreshThermalState() }
        watchPowerSource()
        refreshThermalState()
    }

    private func refreshThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        isOverheating = state == .serious || state == .critical
    }

    /// Polls the time since the last input event. While the user is away it checks every second,
    /// so playback resumes right when they're back. Otherwise every ten seconds is plenty.
    private func checkIdle() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard idleThreshold > 0 else {
            isUserIdle = false
            return
        }

        let anyInput = CGEventType(rawValue: ~0)!
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        let idle = seconds >= idleThreshold
        if idle != isUserIdle { isUserIdle = idle }

        let delay = idle ? 1 : max(1, min(10, idleThreshold - seconds))
        idleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdle() }
        }
        idleTimer?.tolerance = idle ? 0.2 : 2
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
