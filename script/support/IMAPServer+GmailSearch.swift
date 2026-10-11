import Foundation
import NIOCore
import NIOIMAPCore

public extension IMAPServer {
    func searchGmail(_ query: String, in range: ClosedRange<UInt32>, flaggedOnly: Bool) async throws -> UIDSet {
        try await ensurePrimaryConnectionAuthenticated()
        guard supportsGmailExtensions else { throw IMAPError.commandNotSupported("X-GM-EXT-1") }
        return try await executeCommand(GmailSearchCommand(query: query, range: range, flaggedOnly: flaggedOnly))
    }
}

private struct GmailSearchCommand: IMAPTaggedCommand, Sendable {
    typealias ResultType = UIDSet
    typealias HandlerType = SearchHandler<UID>

    let query: String
    let range: ClosedRange<UInt32>
    let flaggedOnly: Bool
    let timeoutSeconds = 60

    func validate() throws {
        guard range.lowerBound > 0, !query.isEmpty, query.utf8.count <= 1026,
              !query.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            throw IMAPError.invalidArgument("Invalid Gmail search")
        }
    }

    func toTaggedCommand(tag: String) -> TaggedCommand {
        // Only typed numbers and fixed keywords are verbatim. NIO encodes the untrusted query as a string.
        let scope = "CHARSET UTF-8 UID \(range.lowerBound):\(range.upperBound) "
            + (flaggedOnly ? "FLAGGED " : "") + "X-GM-RAW "
        return TaggedCommand(tag: tag, command: .custom(name: "UID SEARCH", payloads: [
            .verbatim(ByteBuffer(string: scope)), .literal(ByteBuffer(string: query)),
        ]))
    }
}
