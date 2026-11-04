import Foundation

/// Provider API keys entered by the user. They never leave this Mac.
@MainActor
final class APIKeys: ObservableObject {
    @Published private var keys: [ProviderID: String] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for provider in ProviderID.allCases {
            if let value = defaults.string(forKey: Self.defaultsKey(provider)), !value.isEmpty {
                keys[provider] = value
            }
        }
    }

    func key(for provider: ProviderID) -> String? {
        keys[provider]
    }

    func setKey(_ value: String, for provider: ProviderID) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        keys[provider] = trimmed.isEmpty ? nil : trimmed
        defaults.set(trimmed, forKey: Self.defaultsKey(provider))
    }

    private static func defaultsKey(_ provider: ProviderID) -> String {
        "apiKey.\(provider.rawValue)"
    }
}
