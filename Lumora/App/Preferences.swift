import AVFoundation
import Foundation
import ServiceManagement

enum Scaling: String, CaseIterable, Identifiable {
    case fill
    case fit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: "Fill Screen"
        case .fit: "Fit to Screen"
        }
    }

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill: .resizeAspectFill
        case .fit: .resizeAspect
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    /// Keys an administrator can lock with a configuration profile.
    func isManaged(_ keyPath: PartialKeyPath<Preferences>) -> Bool {
        let key: String? = switch keyPath {
        case \Preferences.scaling: Key.scaling
        case \Preferences.pauseOnBattery: Key.pauseOnBattery
        case \Preferences.pauseInLowPowerMode: Key.pauseInLowPowerMode
        case \Preferences.pauseWhenCovered: Key.pauseWhenCovered
        case \Preferences.matchDesktopPicture: Key.matchDesktopPicture
        case \Preferences.pauseWhenIdle: Key.pauseWhenIdle
        case \Preferences.idleMinutes: Key.idleMinutes
        case \Preferences.pauseWhenHot: Key.pauseWhenHot
        case \Preferences.optimizeNewClips: Key.optimizeNewClips
        case \Preferences.rotationMinutes: Key.rotationMinutes
        case \Preferences.rotationShuffle: Key.rotationShuffle
        case \Preferences.respectReduceMotion: Key.respectReduceMotion
        case \Preferences.launchAtLogin: ManagedSettings.launchAtLoginKey
        default: nil
        }
        return key.map { defaults.objectIsForced(forKey: $0) } ?? false
    }

    private enum Key {
        static let scaling = "scaling"
        static let pauseOnBattery = "pauseOnBattery"
        static let pauseInLowPowerMode = "pauseInLowPowerMode"
        static let pauseWhenCovered = "pauseWhenCovered"
        static let matchDesktopPicture = "matchDesktopPicture"
        static let pauseWhenIdle = "pauseWhenIdle"
        static let idleMinutes = "idleMinutes"
        static let pauseWhenHot = "pauseWhenHot"
        static let optimizeNewClips = "optimizeNewClips"
        static let rotationMinutes = "rotationMinutes"
        static let rotationShuffle = "rotationShuffle"
        static let respectReduceMotion = "respectReduceMotion"
    }

    private let defaults: UserDefaults

    @Published var scaling: Scaling {
        didSet { defaults.set(scaling.rawValue, forKey: Key.scaling) }
    }
    @Published var pauseOnBattery: Bool {
        didSet { defaults.set(pauseOnBattery, forKey: Key.pauseOnBattery) }
    }
    @Published var pauseInLowPowerMode: Bool {
        didSet { defaults.set(pauseInLowPowerMode, forKey: Key.pauseInLowPowerMode) }
    }
    @Published var pauseWhenCovered: Bool {
        didSet { defaults.set(pauseWhenCovered, forKey: Key.pauseWhenCovered) }
    }
    @Published var matchDesktopPicture: Bool {
        didSet { defaults.set(matchDesktopPicture, forKey: Key.matchDesktopPicture) }
    }

    @Published var pauseWhenIdle: Bool {
        didSet { defaults.set(pauseWhenIdle, forKey: Key.pauseWhenIdle) }
    }
    @Published var idleMinutes: Int {
        didSet { defaults.set(idleMinutes, forKey: Key.idleMinutes) }
    }
    @Published var pauseWhenHot: Bool {
        didSet { defaults.set(pauseWhenHot, forKey: Key.pauseWhenHot) }
    }
    @Published var optimizeNewClips: Bool {
        didSet { defaults.set(optimizeNewClips, forKey: Key.optimizeNewClips) }
    }

    /// Zero means the wallpaper never changes on its own.
    @Published var rotationMinutes: Int {
        didSet { defaults.set(rotationMinutes, forKey: Key.rotationMinutes) }
    }
    @Published var rotationShuffle: Bool {
        didSet { defaults.set(rotationShuffle, forKey: Key.rotationShuffle) }
    }
    @Published var respectReduceMotion: Bool {
        didSet { defaults.set(respectReduceMotion, forKey: Key.respectReduceMotion) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.pauseOnBattery: false,
            Key.pauseInLowPowerMode: true,
            Key.pauseWhenCovered: true,
            Key.matchDesktopPicture: true,
            Key.pauseWhenIdle: true,
            Key.idleMinutes: 5,
            Key.pauseWhenHot: true,
            Key.optimizeNewClips: true,
            Key.rotationMinutes: 0,
            Key.rotationShuffle: true,
            Key.respectReduceMotion: true,
        ])
        scaling = Scaling(rawValue: defaults.string(forKey: Key.scaling) ?? "") ?? .fill
        pauseOnBattery = defaults.bool(forKey: Key.pauseOnBattery)
        pauseInLowPowerMode = defaults.bool(forKey: Key.pauseInLowPowerMode)
        pauseWhenCovered = defaults.bool(forKey: Key.pauseWhenCovered)
        matchDesktopPicture = defaults.bool(forKey: Key.matchDesktopPicture)
        pauseWhenIdle = defaults.bool(forKey: Key.pauseWhenIdle)
        idleMinutes = max(1, defaults.integer(forKey: Key.idleMinutes))
        pauseWhenHot = defaults.bool(forKey: Key.pauseWhenHot)
        optimizeNewClips = defaults.bool(forKey: Key.optimizeNewClips)
        rotationMinutes = max(0, defaults.integer(forKey: Key.rotationMinutes))
        rotationShuffle = defaults.bool(forKey: Key.rotationShuffle)
        respectReduceMotion = defaults.bool(forKey: Key.respectReduceMotion)
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            guard !ManagedSettings.isLaunchAtLoginForced else { return }
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Lumora: couldn't update login item: \(error.localizedDescription)")
            }
        }
    }
}
