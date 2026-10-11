import Foundation
import MailSearchDomain

@MainActor
public final class DefaultsSettings: SettingsStore {
    private let defaults: UserDefaults
    public var accounts: [String: AccountSettings] {
        didSet {
            guard accounts != oldValue, let data = try? JSONEncoder().encode(accounts) else { return }
            defaults.set(data, forKey: "accounts")
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accounts = defaults.data(forKey: "accounts")
            .flatMap { try? JSONDecoder().decode([String: AccountSettings].self, from: $0) } ?? [:]
    }
}
