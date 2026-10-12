// MARK: - MailAccountSource

public protocol MailAccountSource: Sendable {
    func accounts() async throws -> [MailAccount]
}

// MARK: - MailSearchClient

public protocol MailSearchClient: Sendable {
    func verify(connection: ConnectionSettings, password: String) async throws
    func search(
        account: MailAccount,
        connection: ConnectionSettings,
        query: SearchQuery,
        receive: @escaping @Sendable (SearchUpdate) async -> Void,
    ) async throws -> AccountOutcome
}

// MARK: - MailMessageFlagger

public protocol MailMessageFlagger: Sendable {
    func setFlag(_ flagged: Bool, for location: MessageLocation, connection: ConnectionSettings) async throws
}

// MARK: - MessagePreview

public struct MessagePreview: Sendable, Equatable {
    // MARK: Lifecycle

    public init(text: String, isTruncated: Bool = false) {
        self.text = text
        self.isTruncated = isTruncated
    }

    // MARK: Public

    public let text: String
    public let isTruncated: Bool
}

// MARK: - MailMessagePreviewer

public protocol MailMessagePreviewer: Sendable {
    func preview(_ location: MessageLocation, connection: ConnectionSettings) async throws -> MessagePreview
}

// MARK: - CredentialStore

public protocol CredentialStore: Sendable {
    func contains(_ key: String) async throws -> Bool
    func authorise() async throws
    func password(for key: String) async throws -> String?
    func save(password: String, for key: String) async throws
}

// MARK: - SettingsStore

@preconcurrency
@MainActor
public protocol SettingsStore: AnyObject {
    var accounts: [String: AccountSettings] { get set }
}
