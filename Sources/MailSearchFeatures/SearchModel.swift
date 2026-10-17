// swiftlint:disable file_length - One owner coordinates search state and cancellation.
import Foundation
import MailSearchDomain
import Observation

// swiftlint:disable type_body_length - One owner coordinates the bounded search lifecycle and cancellation.
/// Coordinates explicit account searches, previews and flag changes.
@preconcurrency
@MainActor
@Observable
public final class SearchModel {
    // MARK: Lifecycle

    /// Composes the model with injected adapters and saved account settings.
    public init(
        source: any MailAccountSource,
        client: any MailSearchClient,
        credentials: any CredentialStore,
        settings: any SettingsStore,
        flagger: any MailMessageFlagger,
        previewer: any MailMessagePreviewer,
    ) {
        self.source = source
        self.client = client
        self.previewer = previewer
        self.flagger = flagger
        self.credentials = credentials
        store = settings
        self.settings = settings.accounts
    }

    // MARK: Public

    /// Unsubmitted text in the search field.
    public var queryText = ""
    /// Whether the next submission searches flagged messages only.
    public var flaggedOnly = false
    /// Keyboard-selected message location.
    public var selection: MessageLocation?
    /// Accounts whose credential metadata indicates a saved password.
    public internal(set) var credentialAccounts: Set<String> = []
    /// Latest account discovery snapshot.
    public private(set) var accounts: [MailAccount] = []
    /// Per-account progress and the connection used by that search.
    public private(set) var statuses: [String: AccountStatus] = [:]
    /// Combined results in stable, newest-first order.
    public private(set) var results: ResultCollection = .init()
    /// Whether submitted accounts still have pending search work.
    public private(set) var isSearching = false
    /// Whether cancelled connections are still draining.
    public private(set) var isStopping = false
    /// Whether account discovery is in progress.
    public private(set) var isRefreshing = false
    /// Whether a preview request is active.
    public internal(set) var isPreviewing = false
    /// Bounded plain text for the expanded message.
    public internal(set) var preview: MessagePreview?
    /// Safe failure description for the expanded preview.
    public internal(set) var previewError: String?
    /// Message currently undergoing an explicit flag change.
    public private(set) var flagging: MessageLocation?
    /// Confirmation or failure of the latest flag change.
    public private(set) var flagNotice: String?
    /// Safe discovery or query validation error.
    public private(set) var error: String?
    /// Enabled accounts and connection overrides, without credentials.
    public internal(set) var settings: [String: AccountSettings]
    /// Message whose preview row is expanded.
    public internal(set) var expanded: MessageLocation?

    /// Whether a query has been submitted during this launch.
    public var hasSearched: Bool {
        submittedQuery != nil
    }

    /// Whether the account participates in submitted searches.
    public func isEnabled(_ account: MailAccount) -> Bool {
        account.exclusion == nil && (settings[account.id]?.enabled ?? true)
    }

    /// Returns the saved override or discovered connection for an account.
    public func connection(for account: MailAccount) -> ConnectionSettings {
        MailProvider(account: account).fixedEndpoint(
            settings[account.id]?.connection ?? MailProvider(account: account).suggestedConnection(for: account),
        )
    }

    /// Updates account selection and reconciles any active search.
    public func setEnabled(_ enabled: Bool, account: MailAccount) {
        guard enabled != isEnabled(account), account.exclusion == nil else {
            return
        }

        settings[account.id] = AccountSettings(enabled: enabled, connection: settings[account.id]?.connection)
        store.accounts = settings
        guard submittedQuery != nil else {
            return
        }

        if enabled {
            queue(account)
        } else {
            accountTokens[account.id] = nil
            searchTasks[account.id]?.cancel()
            pendingAccounts.removeAll { $0.id == account.id }
            statuses[account.id] = nil
            accountResults[account.id] = nil
            if selection?.accountID == account.id {
                selection = nil
                cancelPreview()
            }
        }
        publishResults()
        startPendingSearches()
    }

    /// Discovers account metadata and saved-credential presence.
    public func refresh() async {
        guard isRefreshing == false, isSearching == false, isStopping == false else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let discovered = try await source.accounts()
            if discovered != accounts {
                accounts = discovered
            }
            var saved = Set<String>()
            for account in discovered where account.exclusion == nil {
                if try await credentials
                    .contains(connection(for: account).credentialKey(accountID: account.id))
                {
                    saved.insert(account.id)
                }
            }
            if saved != credentialAccounts {
                credentialAccounts = saved
            }
            error = nil
        } catch {
            self.error = (error as? MailAutomationFailure)?.errorDescription ??
                (error as? SearchFailure ?? .automation).rawValue
        }
    }

    /// Clears the text and submits a flagged-only search.
    public func showFlagged() {
        queryText = ""
        flaggedOnly = true
        submit()
    }

    /// Switches the next submission to all mail.
    public func showAllMail() {
        cancel()
        resultGeneration = UUID()
        flagNotice = nil
        cancelPreview()
        queryText = ""
        flaggedOnly = false
        selection = nil
        results = ResultCollection()
        statuses = [:]
        accountResults = [:]
        submittedQuery = nil
        error = nil
    }

    /// Snapshots the query and starts searches for enabled accounts.
    public func submit() {
        let query: SearchQuery
        do {
            query = try SearchQuery(queryText, flaggedOnly: flaggedOnly)
        } catch {
            self.error = SearchFailure.invalidQuery.rawValue
            return
        }
        let selected = accounts.filter(isEnabled)
        guard selected.isEmpty == false else {
            error = "Refresh Accounts, then enable at least one available IMAP account."
            return
        }

        cancel()
        resultGeneration = UUID()
        submittedQuery = query
        selection = nil
        cancelPreview()
        accountResults = [:]
        results = ResultCollection()
        statuses = [:]
        error = nil
        flagNotice = nil
        for account in selected {
            queue(account)
        }
        publishResults()
        startPendingSearches()
    }

    /// Cancels submitted work while its connections drain.
    public func cancel() {
        for task in searchTasks.values {
            task.cancel()
        }
        pendingAccounts = []
        accountTokens = [:]
        for id in statuses.keys where statuses[id]?.outcome == nil {
            statuses[id]?.outcome = .cancelled
        }
        isSearching = false
        isStopping = searchTasks.isEmpty == false
    }

    /// Changes the selected message’s flag using its original search connection.
    public func toggleFlag(_ id: MessageLocation?) async {
        guard flagging == nil, let id, let result = results.rows.first(where: { $0.id == id }),
              let connection = statuses[id.accountID]?.connection
        else {
            return
        }

        let flagged = result.isFlagged == false
        let token = resultGeneration
        flagging = id
        flagNotice = nil
        let task = Task {
            try await flagger.setFlag(flagged, for: id, connection: connection)
        }
        flagTask = task
        defer { flagging = nil; flagTask = nil }
        do {
            try await task.value
            clearCaches()
            guard resultGeneration == token, statuses[id.accountID]?.connection == connection,
                  settings[id.accountID]?.enabled != false
            else {
                return
            }

            results.setFlag(flagged, for: id)
            accountResults[id.accountID]?.setFlag(flagged, for: id)
            flagNotice = flagged ? "Flag saved. Mail will show it after synchronising."
                : "Flag removed. Mail will update after synchronising."
            error = nil
        } catch {
            clearCaches()
            guard resultGeneration == token else {
                return
            }

            self.error = error is CancellationError
                ? "Flagging cancelled before the write."
                : (error as? SearchFailure ?? .flagUnconfirmed).rawValue
        }
    }

    /// Cancels outstanding work when the app closes.
    public func close() {
        clearCaches()
        cancelPreview()
        cancel()
        flagTask?.cancel()
        verificationTask?.cancel()
    }

    // MARK: Internal

    @ObservationIgnored let client: any MailSearchClient
    @ObservationIgnored let previewer: any MailMessagePreviewer
    @ObservationIgnored let credentials: any CredentialStore
    @ObservationIgnored let store: any SettingsStore
    @ObservationIgnored var previewCache: MemoryCache<MailCacheKey, MessagePreview> = .init()
    @ObservationIgnored var cacheGeneration: UUID = .init()
    @ObservationIgnored var previewTask: Task<Void, Never>?
    @ObservationIgnored var previewGeneration: UUID = .init()
    @ObservationIgnored var verificationTask: Task<Void, any Error>?

    func clearCaches() {
        cacheGeneration = UUID()
        searchCache.removeAll()
        previewCache.removeAll()
    }

    func waitForSearch() async {
        while let task = searchTasks.values.first {
            await task.value
        }
    }

    // MARK: Private

    @ObservationIgnored private let source: any MailAccountSource
    @ObservationIgnored private let flagger: any MailMessageFlagger
    @ObservationIgnored private var searchTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var accountTokens: [String: UUID] = [:]
    @ObservationIgnored private var pendingAccounts: [MailAccount] = []
    private var submittedQuery: SearchQuery?
    @ObservationIgnored private var accountResults: [String: ResultCollection] = [:]
    @ObservationIgnored private var searchCache: MemoryCache<MailCacheKey, [SearchResult]> = .init()
    @ObservationIgnored private var resultGeneration: UUID = .init()
    @ObservationIgnored private var flagTask: Task<Void, any Error>?

    private func queue(_ account: MailAccount) {
        guard let query = submittedQuery else {
            return
        }

        let connection = connection(for: account)
        var status = AccountStatus(connection: connection)
        var rows = ResultCollection()
        if let cached = searchCache.value(for: MailCacheKey.search(
            connectionKey: connection.credentialKey(accountID: account.id),
            query: query,
        )) {
            rows.append(cached)
            status.isCached = true
            status.resultCount = rows.rows.count
        }
        accountResults[account.id] = rows
        statuses[account.id] = status
        pendingAccounts.append(account)
    }

    private func startPendingSearches() {
        while searchTasks.count < SearchLimits.concurrentAccounts, let query = submittedQuery,
              let next = pendingAccounts.firstIndex(where: { searchTasks[$0.id] == nil })
        {
            let account = pendingAccounts.remove(at: next)
            guard let connection = statuses[account.id]?.connection else {
                preconditionFailure("Every queued account must have a connection snapshot")
            }

            let token = UUID()
            accountTokens[account.id] = token
            searchTasks[account.id] = Task {
                await search(account, connection: connection, query: query, token: token)
                searchTasks[account.id] = nil
                if accountTokens[account.id] == token {
                    accountTokens[account.id] = nil
                }
                startPendingSearches()
            }
        }
        isSearching = accountTokens.isEmpty == false || pendingAccounts.isEmpty == false
        isStopping = searchTasks.count > accountTokens.count
    }

    private func search(_ account: MailAccount, connection: ConnectionSettings, query: SearchQuery, token: UUID) async {
        guard Task.isCancelled == false, accountTokens[account.id] == token else {
            return
        }

        let cacheToken = cacheGeneration
        let outcome: AccountOutcome
        do {
            outcome = try await client.search(account: account, connection: connection, query: query) { update in
                await self.receive(update, accountID: account.id, token: token)
            }
        } catch {
            var failure = error as? SearchFailure ?? .server
            if failure == .authentication {
                if MailProvider.isICloudHost(connection.host) {
                    failure = .iCloudAuthentication
                }
                if MailProvider.isGoogleHost(connection.host) {
                    failure = .gmailAuthentication
                }
            }
            outcome = Task.isCancelled ? .cancelled : .failed(failure)
        }
        guard Task.isCancelled == false, accountTokens[account.id] == token else {
            return
        }

        if outcome == .complete {
            if statuses[account.id]?.isCached == true {
                accountResults[account.id] = ResultCollection()
                statuses[account.id]?.resultCount = 0
                statuses[account.id]?.isCached = false
                publishResults()
            }
            let rows = accountResults[account.id]?.rows ?? []
            if cacheGeneration == cacheToken {
                searchCache.insert(
                    rows,
                    for: MailCacheKey.search(
                        connectionKey: connection.credentialKey(accountID: account.id),
                        query: query,
                    ),
                    bytes: rows.reduce(0) { bytes, row in
                        bytes + row.subject.utf8.count + row.sender.utf8.count + (row.messageID?.utf8.count ?? 0)
                            // swiftlint:disable:next no_magic_numbers - Message identity overhead.
                            + row.accountName.utf8.count + row.id.mailbox.utf8.count + row.id.accountID.utf8.count + 256
                    },
                )
            }
        }
        statuses[account.id]?.outcome = outcome
    }

    private func receive(_ update: SearchUpdate, accountID: String, token: UUID) {
        guard accountTokens[accountID] == token, Task.isCancelled == false else {
            return
        }

        switch update {
        case let .progress(value):
            if statuses[accountID]?.progress != value {
                statuses[accountID]?.progress = value
            }

        case let .notice(value):
            if statuses[accountID]?.notices.contains(value) == false {
                statuses[accountID]?.notices.append(value)
            }

        case let .batch(batch):
            if statuses[accountID]?.isCached == true {
                accountResults[accountID] = ResultCollection()
                statuses[accountID]?.isCached = false
            }
            accountResults[accountID]?.append(batch)
            statuses[accountID]?.resultCount = accountResults[accountID]?.rows.count ?? 0
            publishResults()
        }
    }

    private func publishResults() {
        var next = ResultCollection()
        next.append(accountResults.values.flatMap(\.rows))
        if results != next {
            results = next
        }
    }
}

// swiftlint:enable type_body_length

// swiftlint:enable file_length
