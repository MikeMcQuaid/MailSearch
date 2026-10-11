import Foundation

public protocol MailAccountSource: Sendable {
    func accounts() async throws -> [MailAccount]
}

public protocol MailSearchClient: Sendable {
    func verify(connection: ConnectionSettings, password: String) async throws
    func search(
        account: MailAccount, connection: ConnectionSettings, query: SearchQuery,
        receive: @escaping @Sendable (SearchUpdate) async -> Void,
    ) async throws -> AccountOutcome
}

public protocol MailMessageFlagger: Sendable {
    func setFlag(_ flagged: Bool, for location: MessageLocation, connection: ConnectionSettings) async throws
}

public struct MessagePreview: Sendable, Equatable {
    public let text: String
    public let isTruncated: Bool

    public init(text: String, isTruncated: Bool = false) {
        self.text = text
        self.isTruncated = isTruncated
    }
}

public protocol MailMessagePreviewer: Sendable {
    func preview(_ location: MessageLocation, connection: ConnectionSettings) async throws -> MessagePreview
}

public protocol CredentialStore: Sendable {
    func contains(_ key: String) async throws -> Bool
    func authorise() async throws
    func password(for key: String) async throws -> String?
    func save(password: String, for key: String) async throws
}

@MainActor
public protocol SettingsStore: AnyObject {
    var accounts: [String: AccountSettings] { get set }
}
