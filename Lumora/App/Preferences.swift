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
    private enum Key {
        static let scaling = "scaling"
        static let pauseOnBattery = "pauseOnBattery"
        static let pauseInLowPowerMode = "pauseInLowPowerMode"
        static let pauseWhenCovered = "pauseWhenCovered"
        static let matchDesktopPicture = "matchDesktopPicture"
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.pauseOnBattery: false,
            Key.pauseInLowPowerMode: true,
            Key.pauseWhenCovered: true,
            Key.matchDesktopPicture: true,
        ])
        scaling = Scaling(rawValue: defaults.string(forKey: Key.scaling) ?? "") ?? .fill
        pauseOnBattery = defaults.bool(forKey: Key.pauseOnBattery)
        pauseInLowPowerMode = defaults.bool(forKey: Key.pauseInLowPowerMode)
        pauseWhenCovered = defaults.bool(forKey: Key.pauseWhenCovered)
        matchDesktopPicture = defaults.bool(forKey: Key.matchDesktopPicture)
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
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
