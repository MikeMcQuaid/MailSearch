import Foundation
import MailSearchDomain

@preconcurrency
@MainActor
public final class DefaultsSettings: SettingsStore {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accounts = defaults.data(forKey: "accounts")
            .flatMap { try? JSONDecoder().decode([String: AccountSettings].self, from: $0) } ?? [:]
    }

    // MARK: Public

    public var accounts: [String: AccountSettings] {
        didSet {
            guard accounts != oldValue, let data = try? JSONEncoder().encode(accounts) else {
                return
            }

            defaults.set(data, forKey: "accounts")
        }
    }

    // MARK: Private

    private let defaults: UserDefaults
}
