import MailSearchDomain
import SwiftMail

extension SwiftMailSearchClient: MailMessageFlagger {
    public func setFlag(_ flagged: Bool, for location: MessageLocation, connection: ConnectionSettings) async throws {
        let (server, password) = try await session(accountID: location.accountID, connection: connection)
        try await setFlag(flagged, for: location, server: server, username: connection.username, password: password)
    }

    func setFlag(
        _ flagged: Bool,
        for location: MessageLocation,
        server: IMAPServer,
        username: String,
        password: String,
    ) async throws {
        var attemptedStore = false
        do {
            try Self.validate(location)
            try await Self.authenticate(server, username: username, password: password)
            let selection = try await server.selectMailbox(location.mailbox)
            try Task.checkCancellation()
            guard selection.uidValidity.value == location.uidValidity else {
                throw SearchFailure.staleMessage
            }
            guard selection.isReadOnly == false, selection.permanentFlags.contains(.flagged) else {
                throw SearchFailure.flagUnavailable
            }

            let identifiers = UIDSet([UID(location.uid)])
            let before = try await server.fetchMessageInfosBulk(using: identifiers, options: .uidFlagsOnly)
            try Task.checkCancellation()
            guard let message = before.first(where: { $0.uid?.value == location.uid }) else {
                throw SearchFailure.staleMessage
            }

            if message.flags.contains(.flagged) != flagged {
                attemptedStore = true
                let reported = try await server.storeMessageFlag(flagged, uid: UID(location.uid))
                // Confirm an attempted write even if cancellation arrived while STORE was in flight.
                let after = try await server.fetchMessageInfosBulk(using: identifiers, options: .uidFlagsOnly)
                // Gmail removes unstarred messages from Starred before a read-back can find their UID.
                let removedFromFolder = flagged == false && after.isEmpty
                    && reported.contains { $0.uid?.value == location.uid && $0.flags.contains(.flagged) == false }
                guard removedFromFolder || after
                    .contains(where: { $0.uid?.value == location.uid && $0.flags.contains(.flagged) == flagged })
                else {
                    throw SearchFailure.flagUnconfirmed
                }
            }
            try? await server.disconnect()
        } catch {
            try? await server.disconnect()
            if attemptedStore {
                throw SearchFailure.flagUnconfirmed
            }
            if Task.isCancelled {
                throw CancellationError()
            }
            throw Self.failure(error)
        }
    }
}
