import Foundation
import MailSearchDomain
import SwiftMail
import SwiftSoup

extension SwiftMailSearchClient: MailMessagePreviewer {
    public func preview(_ location: MessageLocation, connection: ConnectionSettings) async throws -> MessagePreview {
        let (server, password) = try await session(accountID: location.accountID, connection: connection)
        return try await preview(
            location,
            server: server,
            username: connection.username,
            password: password,
            iCloud: MailProvider.isICloudHost(connection.host),
        )
    }

    // swiftlint:disable:next function_body_length - Sequential operation and cleanup.
    func preview(
        _ location: MessageLocation,
        server: IMAPServer,
        username: String,
        password: String,
        iCloud: Bool = false,
    ) async throws -> MessagePreview {
        do {
            try Self.validate(location)
            try await Self.authenticate(server, username: username, password: password)
            let selection = try await server.examineMailbox(location.mailbox)
            guard selection.uidValidity.value == location.uidValidity else {
                throw SearchFailure.staleMessage
            }
            guard selection.isReadOnly || iCloud else {
                throw SearchFailure.readOnly
            }

            try Task.checkCancellation()
            let metadata = try await server.fetchMessageInfosBulk(
                using: UIDSet([UID(location.uid)]),
                options: [.bodyStructure],
            )
            try Task.checkCancellation()
            guard let message = metadata.first(where: { $0.uid?.value == location.uid })
            else {
                throw SearchFailure.staleMessage
            }
            guard var part = Self.previewPart(message.parts) else {
                throw SearchFailure.previewUnavailable
            }

            let limit = 32_768
            var bytes = Data()
            let size = min(part.size ?? limit, limit)
            while bytes.count < size {
                try Task.checkCancellation()
                let chunkLimit = 4_096
                let count = min(chunkLimit, size - bytes.count)
                let chunk = try await server.fetchPart(
                    section: part.section,
                    of: UID(location.uid),
                    offset: bytes.count,
                    count: count,
                )
                try Task.checkCancellation()
                bytes.append(chunk)
                if chunk.count < count {
                    break
                }
            }
            part.data = bytes
            guard let text = part.textContent else {
                throw SearchFailure.previewUnavailable
            }

            let result = try Self.plainPreview(
                text,
                isHTML: part.contentType.lowercased().hasPrefix("text/html"),
                truncated: part.size.map { $0 > bytes.count } ?? (bytes.count == limit),
            )
            try? await server.disconnect()
            try Task.checkCancellation()
            return result
        } catch {
            try? await server.disconnect()
            if Task.isCancelled {
                throw CancellationError()
            }
            throw Self.failure(error)
        }
    }

    static func previewPart(_ parts: [MessagePart]) -> MessagePart? {
        let attachments = parts.filter { part in
            part.disposition?.lowercased() == "attachment" || part.filename != nil
                || part.contentType.lowercased().hasPrefix("message/")
        }
        let text = parts.filter { part in
            attachments.contains { part.section.components.starts(with: $0.section.components) } == false
                &&
                (part.contentType.lowercased().hasPrefix("text/plain") || part.contentType
                    .lowercased()
                    .hasPrefix("text/html"))
        }
        return text.first { $0.contentType.lowercased().hasPrefix("text/plain") } ?? text.first
    }

    static func plainPreview(_ text: String, isHTML: Bool, truncated: Bool) throws -> MessagePreview {
        guard isHTML else {
            return MessagePreview(text: text, isTruncated: truncated)
        }

        let document = try SwiftSoup.parse(text)
        try document.select("head, script, style, iframe, object, embed, form, template").remove()
        return try MessagePreview(text: document.text(), isTruncated: truncated)
    }
}
