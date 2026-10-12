import Foundation
import Logging
import MailSearchDomain
import SwiftMail

// swiftlint:disable:next type_body_length - One owner coordinates the bounded search lifecycle and cancellation.
public struct SwiftMailSearchClient: MailSearchClient {
    // MARK: Lifecycle

    public init(credentials: any CredentialStore) {
        _ = Self.silenceLogs
        self.credentials = credentials
    }

    // MARK: Public

    @preconcurrency
    public func search(
        account: MailAccount,
        connection: ConnectionSettings,
        query: SearchQuery,
        receive: @escaping @Sendable (SearchUpdate) async -> Void,
    ) async throws -> AccountOutcome {
        await receive(.progress("Reading the saved password…"))
        let (server, password) = try await session(accountID: account.id, connection: connection)
        return try await search(
            server: server,
            account: account,
            username: connection.username,
            password: password,
            query: query,
            iCloud: MailProvider.isICloudHost(connection.host),
            receive: receive,
        )
    }

    // MARK: Internal

    // swiftlint:disable no_magic_numbers - Explicit response, body, attribute and literal byte budgets.
    static func server(connection: ConnectionSettings) throws -> IMAPServer {
        guard connection.isValid else {
            throw SearchFailure.settings
        }
        guard connection.security == .tls else {
            throw SearchFailure.unsupportedTransport
        }

        return IMAPServer(
            host: connection.host,
            port: connection.port,
            transportSecurity: .implicitTLS,
            responseBufferLimit: 1_048_576,
            parserLimits: IMAPParserLimits(bodySizeLimit: 65_536, messageAttributeLimit: 32, literalSizeLimit: 4_096),
        )
    }

    // swiftlint:enable no_magic_numbers

    static func validate(_ location: MessageLocation) throws {
        guard location.uid > 0, location.uidValidity > 0,
              location.mailbox.isEmpty == false,
              location.mailbox == location.mailbox.trimmingCharacters(in: .whitespacesAndNewlines),
              location.mailbox.contains("\u{FFFD}") == false
        else {
            throw SearchFailure.staleMessage
        }
    }

    static func failure(_ error: any Error) -> SearchFailure {
        if let failure = error as? SearchFailure {
            return failure
        }
        guard let imapError = error as? IMAPError else {
            return .connection
        }

        switch imapError {
        case .authFailed,
             .loginFailed,
             .unsupportedAuthMechanism:
            return .authentication

        case .timeout:
            return .timeout

        case .connectionFailed,
             .greetingFailed:
            return .connection

        case .searchCharsetNotSupported:
            return .charset

        default:
            return .server
        }
    }

    func session(accountID: String, connection: ConnectionSettings) async throws -> (IMAPServer, String) {
        guard connection.isValid else {
            throw SearchFailure.settings
        }
        guard connection.security == .tls else {
            throw SearchFailure.unsupportedTransport
        }
        guard let password = try await credentials.password(for: connection.credentialKey(accountID: accountID)) else {
            throw SearchFailure.credentials
        }

        try Task.checkCancellation()
        return try (Self.server(connection: connection), password)
    }

    // swiftlint:disable:next function_parameter_count - Internal seam for the loopback fixture.
    func search(
        server: IMAPServer,
        account: MailAccount,
        username: String,
        password: String,
        query: SearchQuery,
        iCloud: Bool = false,
        receive: @escaping @Sendable (SearchUpdate) async -> Void,
    ) async throws -> AccountOutcome {
        do {
            try await Self.authenticate(server, username: username, password: password, receive: receive)
            let outcome = try await searchMailboxes(
                server: server,
                account: account,
                query: query,
                iCloud: iCloud,
                receive: receive,
            )
            try? await server.disconnect()
            try Task.checkCancellation()
            return outcome
        } catch {
            // Disconnect drains the library's current command, bounded by its deadline.
            try? await server.disconnect()
            if Task.isCancelled {
                throw CancellationError()
            }
            throw Self.failure(error)
        }
    }

    // MARK: Private

    private static let silenceLogs: Void = LoggingSystem.bootstrap { _ in SwiftLogNoOpLogHandler() }

    private let credentials: any CredentialStore

    // swiftlint:disable:next cyclomatic_complexity function_body_length - Sequential mailbox protocol and cleanup.
    private func searchMailboxes(
        server: IMAPServer,
        account: MailAccount,
        query: SearchQuery,
        iCloud: Bool,
        receive: @Sendable (SearchUpdate) async -> Void,
    ) async throws -> AccountOutcome {
        await receive(.progress("Listing mailboxes…"))
        let gmail = await server.supportsGmailExtensions
        let mailboxes = try await server.listMailboxes()
        try Task.checkCancellation()
        var incomplete = false
        var resultCount = 0
        var windows = 0
        var selectable = mailboxes.filter(\.isSelectable)
        if gmail, query.flaggedOnly {
            let starred = selectable.filter { $0.attributes.contains(.flagged) }
            if starred.isEmpty == false {
                selectable = starred
            }
        }
        let ordered = Dictionary(grouping: selectable) { mailbox in
            (iCloud && (mailbox.attributes.contains(.archive) || mailbox.name.lowercased() == "archive")) ||
                (gmail &&
                    (mailbox.attributes.contains(.all) || mailboxDisplayName(mailbox.name).lowercased() == "all mail"))
        }
        selectable = ordered[false, default: []] + ordered[true, default: []]
        if selectable.count > SearchLimits.mailboxesPerAccount {
            incomplete = true
            await receive(.notice("Incomplete: only the first 500 selectable mailboxes can be searched."))
        }
        if selectable.isEmpty {
            await receive(.notice("No selectable server mailboxes are available."))
        }
        for (index, mailbox) in selectable.prefix(SearchLimits.mailboxesPerAccount).enumerated() {
            try Task.checkCancellation()
            if resultCount >= SearchLimits.resultsPerAccount || windows >= SearchLimits.windowsPerAccount {
                await receive(
                    .notice("Incomplete: the account search limit was reached. Use more specific search text."),
                )
                return .incomplete
            }
            await receive(.progress("Mailbox \(index + 1) of \(selectable.count): \(mailboxDisplayName(mailbox.name))"))
            do {
                guard mailbox.name == mailbox.name.trimmingCharacters(in: .whitespacesAndNewlines),
                      mailbox.name.contains("\u{FFFD}") == false
                else {
                    incomplete = true
                    await receive(
                        .notice(
                            """
                            Excluded ‘\(mailboxDisplayName(mailbox.name))’: the IMAP library cannot \
                            preserve this mailbox name exactly.
                            """,
                        ),
                    )
                    continue
                }

                let selection = try await server.examineMailbox(mailbox.name)
                try Task.checkCancellation()
                guard selection.uidValidity.value > 0 else {
                    throw SearchFailure.uidValidity
                }
                guard selection.uidNext.value > 0 else {
                    throw SearchFailure.uidNext
                }

                if selection.isReadOnly == false {
                    guard iCloud else {
                        throw SearchFailure.readOnly
                    }
                }
                var start: UInt32 = 1
                while let range = SearchLimits.window(start: start, uidNext: selection.uidNext.value) {
                    try Task.checkCancellation()
                    guard resultCount < SearchLimits.resultsPerAccount, windows < SearchLimits.windowsPerAccount else {
                        await receive(
                            .notice("Incomplete: the account search limit was reached. Use more specific search text."),
                        )
                        return .incomplete
                    }

                    windows += 1
                    let matches: UIDSet?
                    if gmail, let phrase = query.gmailPhrase {
                        matches = try await server.searchGmail(phrase, in: range, flaggedOnly: query.flaggedOnly)
                    } else {
                        let response: ExtendedSearchResult<UID> = try await server.extendedSearch(
                            identifierSet: UIDSet(UID(range.lowerBound) ... UID(range.upperBound)),
                            criteria: (query.text.isEmpty ? [] : [.text(query.text)]) +
                                (query.flaggedOnly ? [.flagged] : []),
                        )
                        matches = response.all
                    }
                    try Task.checkCancellation()
                    // Intersect ranges before expanding: a hostile ESEARCH range must not allocate billions of UIDs.
                    let ids = (matches?.ranges ?? []).flatMap { bounds -> [UID] in
                        let lower = max(bounds.lowerBound, Int(range.lowerBound))
                        let upper = min(bounds.upperBound, Int(range.upperBound))
                        return lower <= upper ? (lower ... upper).map { UID($0) } : []
                    }
                    for offset in stride(from: 0, to: ids.count, by: SearchLimits.metadataBatch) {
                        try Task.checkCancellation()
                        let count = min(SearchLimits.metadataBatch, SearchLimits.resultsPerAccount - resultCount)
                        guard count > 0 else {
                            await receive(.notice("Incomplete: showing the first 2,000 matches for this account."))
                            return .incomplete
                        }

                        let requested = Array(ids.dropFirst(offset).prefix(count))
                        let metadata = try await server.fetchMessageInfosBulk(
                            using: UIDSet(requested),
                            options: [.internalDate, .flags],
                            headerFields: ["SUBJECT", "FROM", "DATE", "MESSAGE-ID"],
                        )
                        try Task.checkCancellation()
                        let requestedIDs = Set(requested)
                        let batch = metadata.compactMap { info -> SearchResult? in
                            guard let uid = info.uid, requestedIDs.contains(uid) else {
                                return nil
                            }

                            return SearchResult(
                                id: MessageLocation(
                                    accountID: account.id,
                                    mailbox: mailbox.name,
                                    uidValidity: selection.uidValidity.value,
                                    uid: uid.value,
                                ),
                                accountName: account.name,
                                subject: info.subject ?? "(No subject)",
                                sender: info.from ?? "(Unknown sender)",
                                date: info.date ?? info.internalDate,
                                // swiftformat:disable:next acronyms
                                messageID: info.messageId?.description,
                                isFlagged: info.flags.contains(.flagged),
                            )
                        }
                        if Set(batch.map(\.id.uid)).count != requested.count {
                            incomplete = true
                            await receive(
                                .notice(
                                    """
                                    \(mailboxDisplayName(mailbox.name)): some matching messages \
                                    disappeared or returned no metadata.
                                    """,
                                ),
                            )
                        }
                        resultCount += batch.count
                        if batch.isEmpty == false {
                            await receive(.batch(batch))
                        }
                        if count < min(SearchLimits.metadataBatch, ids.count - offset) {
                            await receive(.notice("Incomplete: showing the first 2,000 matches for this account."))
                            return .incomplete
                        }
                    }
                    start = range.upperBound + 1
                }
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                let failure = Self.failure(error)
                if failure == .authentication || failure == .connection || failure == .timeout {
                    throw failure
                }
                incomplete = true
                await receive(.notice("\(mailboxDisplayName(mailbox.name)): \(failure.rawValue)"))
            }
        }
        return incomplete ? .incomplete : .complete
    }
}
