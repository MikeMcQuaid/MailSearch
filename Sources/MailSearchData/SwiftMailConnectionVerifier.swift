import MailSearchDomain
import SwiftMail

extension SwiftMailSearchClient {
    /// Checks TLS and authentication without selecting a mailbox.
    public func verify(connection: ConnectionSettings, password: String) async throws {
        try Task.checkCancellation()
        try await verify(server: Self.server(connection: connection), username: connection.username, password: password)
    }

    func verify(server: IMAPServer, username: String, password: String) async throws {
        do {
            try await Self.authenticate(server, username: username, password: password)
            try? await server.disconnect()
            try Task.checkCancellation()
        } catch {
            try? await server.disconnect()
            if Task.isCancelled {
                throw CancellationError()
            }
            throw Self.failure(error)
        }
    }

    static func authenticate(
        _ server: IMAPServer,
        username: String,
        password: String,
        receive: @Sendable (SearchUpdate) async -> Void = { _ in },
    ) async throws {
        try Task.checkCancellation()
        await receive(.progress("Connecting securely…"))
        try await server.connect()
        try Task.checkCancellation()
        await receive(.progress("Authenticating…"))
        try await server.loginWithPassword(username: username, password: password)
        try Task.checkCancellation()
    }
}
