import MailSearchDomain

let testConnection: ConnectionSettings = .init(host: "imap.example.test", port: 993, username: "alice", security: .tls)

func account(_ id: String) -> MailAccount {
    MailAccount(id: id, name: id, addresses: [], kind: .imap, connection: testConnection)
}

// MARK: - Accounts

actor Accounts: MailAccountSource {
    // MARK: Lifecycle

    init(_ values: [MailAccount]) {
        self.values = values
    }

    // MARK: Internal

    let values: [MailAccount]

    func accounts() -> [MailAccount] {
        values
    }
}

// MARK: - Credentials

actor Credentials: CredentialStore {
    var values: [String: String] = [:]
    var passwordReads = 0

    func authorise() {
        // In-memory fixture credentials need no authorisation.
    }

    func contains(_ key: String) -> Bool {
        values[key] != nil
    }

    func password(for key: String) -> String? {
        passwordReads += 1
        return values[key]
    }

    func save(password: String, for key: String) {
        values[key] = password
    }
}

// MARK: - Previewer

actor Previewer: MailMessagePreviewer {
    // MARK: Lifecycle

    init(held: Bool = false, text: String? = nil) {
        self.held = held
        self.text = text
    }

    // MARK: Internal

    let held: Bool
    let text: String?
    var calls: [MessageLocation] = []
    var continuation: CheckedContinuation<Void, Never>?
    var waiter: CheckedContinuation<Void, Never>?

    func preview(_ location: MessageLocation, connection _: ConnectionSettings) async -> MessagePreview {
        calls.append(location)
        if held, calls.count == 1 {
            await withCheckedContinuation { pending in
                continuation = pending
                waiter?.resume(); waiter = nil
            }
        }
        return MessagePreview(text: text ?? location.accountID)
    }

    func wait() async {
        if continuation == nil {
            await withCheckedContinuation { waiter = $0 }
        }
    }

    func resume() {
        continuation?.resume(); continuation = nil
    }
}

// MARK: - Flagger

actor Flagger: MailMessageFlagger {
    // MARK: Lifecycle

    init(failure: SearchFailure? = nil, held: Bool = false) {
        self.failure = failure
        self.held = held
    }

    // MARK: Internal

    let failure: SearchFailure?
    let held: Bool
    var calls: [(MessageLocation, ConnectionSettings)] = []
    var flagValues: [Bool] = []
    var continuation: CheckedContinuation<Void, Never>?
    var waiter: CheckedContinuation<Void, Never>?

    func setFlag(_ flagged: Bool, for location: MessageLocation, connection: ConnectionSettings) async throws {
        calls.append((location, connection))
        flagValues.append(flagged)
        if held {
            await withCheckedContinuation { pending in
                continuation = pending
                waiter?.resume()
                waiter = nil
            }
        }
        if let failure {
            throw failure
        }
    }

    func wait() async {
        if continuation != nil {
            return
        }
        await withCheckedContinuation { waiter = $0 }
    }

    func resume() {
        continuation?.resume(); continuation = nil
    }
}

// MARK: - Settings

@MainActor
final class Settings: SettingsStore {
    var accounts: [String: AccountSettings] = [:]
}

// MARK: - Client

actor Client: MailSearchClient {
    // MARK: Lifecycle

    init(held: Bool = false, holdAfterBatch: Bool = false) {
        self.held = held
        self.holdAfterBatch = holdAfterBatch
    }

    // MARK: Internal

    var verifiedConnection: ConnectionSettings?
    var verifiedPassword: String?

    let held: Bool
    let holdAfterBatch: Bool
    var started: Set<String> = []
    var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    var releases: [String: CheckedContinuation<Void, Never>] = [:]
    var active = 0
    var maximum = 0
    var calls: [String] = []
    var cancelled: Set<String> = []
    var fail = false
    var receivers: [String: @Sendable (SearchUpdate) async -> Void] = [:]
    var empty = false

    func verify(connection: ConnectionSettings, password: String) async throws {
        if held {
            await pause("verification")
        }
        try Task.checkCancellation()
        verifiedConnection = connection
        verifiedPassword = password
        if password == "rejected" {
            throw SearchFailure.authentication
        }
    }

    func addResults(_ rows: [SearchResult], accountID: String) async {
        await receivers[accountID]?(.batch(rows))
    }

    func failSearch() {
        fail = true
    }

    func setEmpty() {
        empty = true
    }

    func waitFor(_ key: String) async {
        if started.contains(key) {
            return
        }
        await withCheckedContinuation { waiters[key] = $0 }
    }

    func release(_ key: String) {
        started.remove(key)
        releases.removeValue(forKey: key)?.resume()
    }

    func search(
        account: MailAccount,
        connection _: ConnectionSettings,
        query: SearchQuery,
        receive: @escaping @Sendable (SearchUpdate) async -> Void,
    ) async throws -> AccountOutcome {
        active += 1
        maximum = max(active, maximum)
        receivers[account.id] = receive
        defer { active -= 1; receivers[account.id] = nil }
        let key = query.text + account.id
        calls.append(key)
        if held {
            await pause(key)
        }
        if fail || account.id == "failed" {
            throw SearchFailure.authentication
        }
        if account.id == "keychain" {
            throw SearchFailure.keychainAccess
        }
        if empty == false {
            await receive(.batch([
                SearchResult(
                    id: MessageLocation(accountID: account.id, mailbox: "Archive", uidValidity: 2, uid: 1),
                    accountName: account.name,
                    subject: query.text,
                    sender: "Fixture",
                    date: nil,
                    messageID: "<a@example.test>",
                ),
            ]))
        }
        if holdAfterBatch {
            await pause(key)
        }
        if Task.isCancelled {
            cancelled.insert(account.id)
        }
        return .complete
    }

    func pause(_ key: String) async {
        await withCheckedContinuation { continuation in
            releases[key] = continuation
            started.insert(key)
            waiters.removeValue(forKey: key)?.resume()
        }
    }
}
