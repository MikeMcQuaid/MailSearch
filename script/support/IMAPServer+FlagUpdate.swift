import NIOIMAPCore

public extension IMAPServer {
    /// Changes one flag and returns the server’s confirmed message metadata.
    func storeMessageFlag(_ flagged: Bool, uid: UID) async throws -> [MessageInfo] {
        try await executeCommand(MessageFlagCommand(flagged: flagged, uid: uid))
    }
}

// MARK: - MessageFlagCommand

private struct MessageFlagCommand: IMAPTaggedCommand {
    typealias ResultType = [MessageInfo]
    typealias HandlerType = FetchMessageInfoHandler

    let flagged: Bool
    let uid: UID
    let timeoutSeconds = 30

    func validate() throws {
        guard uid.value > 0 else {
            throw IMAPError.invalidArgument("Invalid UID")
        }
    }

    func toTaggedCommand(tag: String) -> TaggedCommand {
        StoreCommand(identifierSet: UIDSet([uid]), data: .flags([.flagged], flagged ? .add : .remove))
            .toTaggedCommand(tag: tag)
    }
}
