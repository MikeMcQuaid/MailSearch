import Foundation
import MailSearchDomain

public extension SearchModel {
    func configure(_ account: MailAccount, connection: ConnectionSettings, password: String) async throws {
        guard verificationTask == nil else { throw SearchFailure.verificationInProgress }
        var connection = MailProvider(account: account).fixedEndpoint(connection)
        connection.username = connection.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard connection.isValid else { throw SearchFailure.settings }
        let previous = self.connection(for: account)
        let task = Task {
            var secret = connection.normalisedPassword(password)
            if password.isEmpty {
                guard connection.hasSameServer(as: previous) else { throw SearchFailure.credentials }
                try await credentials.authorise()
                secret = try await credentials.password(for: previous.credentialKey(accountID: account.id)) ?? ""
            }
            guard !secret.isEmpty else { throw SearchFailure.credentials }
            try Task.checkCancellation()
            try await client.verify(connection: connection, password: secret)
            try Task.checkCancellation()
            try await credentials.authorise()
            try await credentials.save(password: secret, for: connection.credentialKey(accountID: account.id))
            settings[account.id] = AccountSettings(
                enabled: settings[account.id]?.enabled ?? true,
                connection: connection,
            )
            store.accounts = settings
            credentialAccounts.insert(account.id)
            clearCaches()
        }
        verificationTask = task
        defer { verificationTask = nil }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }
}
