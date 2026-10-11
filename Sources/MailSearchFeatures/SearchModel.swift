import Foundation
import MailSearchDomain
import Observation

@MainActor @Observable
public final class SearchModel {
    public var queryText = ""
    public var flaggedOnly = false
    public var selection: MessageLocation?
    public internal(set) var credentialAccounts: Set<String> = []
    public private(set) var accounts: [MailAccount] = []
    public private(set) var statuses: [String: AccountStatus] = [:]
    public private(set) var results = ResultCollection()
    public private(set) var isSearching = false
    public private(set) var isStopping = false
    public private(set) var isRefreshing = false
    public internal(set) var isPreviewing = false
    public internal(set) var preview: MessagePreview?
    public internal(set) var previewError: String?
    public private(set) var flagging: MessageLocation?
    public private(set) var flagNotice: String?
    public var hasSearched: Bool {
        submittedQuery != nil
    }

    public private(set) var error: String?
    public internal(set) var settings: [String: AccountSettings]
    @ObservationIgnored private let source: any MailAccountSource
    @ObservationIgnored let client: any MailSearchClient
    @ObservationIgnored private let flagger: any MailMessageFlagger
    @ObservationIgnored let previewer: any MailMessagePreviewer
    @ObservationIgnored let credentials: any CredentialStore
    @ObservationIgnored let store: any SettingsStore
    @ObservationIgnored private var searchTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var accountTokens: [String: UUID] = [:]
    @ObservationIgnored private var pendingAccounts: [MailAccount] = []
    private var submittedQuery: SearchQuery?
    @ObservationIgnored private var accountResults: [String: ResultCollection] = [:]
    @ObservationIgnored private var searchCache = MemoryCache<MailCacheKey, [SearchResult]>()
    @ObservationIgnored var previewCache = MemoryCache<MailCacheKey, MessagePreview>()
    @ObservationIgnored var cacheGeneration = UUID()
    @ObservationIgnored private var resultGeneration = UUID()
    public internal(set) var expanded: MessageLocation?
    @ObservationIgnored var previewTask: Task<Void, Never>?
    @ObservationIgnored var previewGeneration = UUID()
    @ObservationIgnored private var flagTask: Task<Void, any Error>?
    @ObservationIgnored var verificationTask: Task<Void, any Error>?

    public init(
        source: any MailAccountSource, client: any MailSearchClient,
        credentials: any CredentialStore, settings: any SettingsStore, flagger: any MailMessageFlagger,
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

    public func isEnabled(_ account: MailAccount) -> Bool {
        account.exclusion == nil && (settings[account.id]?.enabled ?? true)
    }

    public func connection(for account: MailAccount) -> ConnectionSettings {
        MailProvider(account: account).fixedEndpoint(
            settings[account.id]?.connection ?? MailProvider(account: account).suggestedConnection(for: account),
        )
    }

    public func setEnabled(_ enabled: Bool, account: MailAccount) {
        guard enabled != isEnabled(account), account.exclusion == nil else { return }
        settings[account.id] = AccountSettings(enabled: enabled, connection: settings[account.id]?.connection)
        store.accounts = settings
        guard submittedQuery != nil else { return }
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

    public func refresh() async {
        guard !isRefreshing, !isSearching, !isStopping else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let discovered = try await source.accounts()
            if discovered != accounts {
                accounts = discovered
            }
            var saved: Set<String> = []
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

    public func showFlagged() {
        queryText = ""
        flaggedOnly = true
        submit()
    }

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

    public func submit() {
        let query: SearchQuery
        do { query = try SearchQuery(queryText, flaggedOnly: flaggedOnly) } catch {
            self.error = SearchFailure.invalidQuery.rawValue
            return
        }
        let selected = accounts.filter(isEnabled)
        guard !selected.isEmpty else {
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

    private func queue(_ account: MailAccount) {
        guard let query = submittedQuery else { return }
        let connection = connection(for: account)
        var status = AccountStatus(connection: connection)
        var rows = ResultCollection()
        if let cached = searchCache.value(for: MailCacheKey.search(
            connectionKey: connection.credentialKey(accountID: account.id),
            query: query,
        )) {
            rows.append(cached)
            status.isCached = true
            status.count = rows.rows.count
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
            let connection = statuses[account.id]!.connection
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
        isSearching = !accountTokens.isEmpty || !pendingAccounts.isEmpty
        isStopping = searchTasks.count > accountTokens.count
    }

    private func search(_ account: MailAccount, connection: ConnectionSettings, query: SearchQuery, token: UUID) async {
        guard !Task.isCancelled, accountTokens[account.id] == token else { return }
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
        guard !Task.isCancelled, accountTokens[account.id] == token else { return }
        if outcome == .complete {
            if statuses[account.id]?.isCached == true {
                accountResults[account.id] = ResultCollection()
                statuses[account.id]?.count = 0
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
                    bytes: rows.reduce(0) {
                        $0 + $1.subject.utf8.count + $1.sender.utf8.count + ($1.messageID?.utf8.count ?? 0)
                            + $1.accountName.utf8.count + $1.id.mailbox.utf8.count + $1.id.accountID.utf8.count + 256
                    },
                )
            }
        }
        statuses[account.id]?.outcome = outcome
    }

    private func receive(_ update: SearchUpdate, accountID: String, token: UUID) {
        guard accountTokens[accountID] == token, !Task.isCancelled else { return }
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
            statuses[accountID]?.count = accountResults[accountID]?.rows.count ?? 0
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
        isStopping = !searchTasks.isEmpty
    }

    public func toggleFlag(_ id: MessageLocation?) async {
        guard flagging == nil, let id, let result = results.rows.first(where: { $0.id == id }),
              let connection = statuses[id.accountID]?.connection else { return }
        let flagged = !result.isFlagged
        let token = resultGeneration
        flagging = id
        flagNotice = nil
        let task = Task { try await flagger.setFlag(flagged, for: id, connection: connection) }
        flagTask = task
        defer { flagging = nil; flagTask = nil }
        do {
            try await task.value
            clearCaches()
            guard resultGeneration == token else { return }
            guard statuses[id.accountID]?.connection == connection,
                  settings[id.accountID]?.enabled != false else { return }
            results.setFlag(flagged, for: id)
            accountResults[id.accountID]?.setFlag(flagged, for: id)
            flagNotice = flagged ? "Flag saved. Mail will show it after synchronising."
                : "Flag removed. Mail will update after synchronising."
            error = nil
        } catch {
            clearCaches()
            guard resultGeneration == token else { return }
            self.error = error is CancellationError
                ? "Flagging cancelled before the write."
                : (error as? SearchFailure ?? .flagUnconfirmed).rawValue
        }
    }

    public func close() {
        clearCaches()
        cancelPreview()
        cancel()
        flagTask?.cancel()
        verificationTask?.cancel()
    }

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
}
