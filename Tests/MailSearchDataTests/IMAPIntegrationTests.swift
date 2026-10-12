import Foundation
@testable import MailSearchData
import MailSearchDomain
import SwiftMail
import Testing

// swiftlint:disable function_body_length - The fixture verifies the complete ordered protocol or UI lifecycle.
@Test(arguments: [
    "normal",
    "partial",
    "empty",
    "missing",
    "readwrite",
    "cap",
    "esearch",
    "oversized",
    "whitespace",
    "icloud-readwrite",
    "icloud-flagged",
    "icloud-no-validity",
    "icloud-no-next",
])
func `read only fixture`(mode: String) async throws {
    let fixture = try Fixture(mode: mode)
    let updates = Updates()
    let client = SwiftMailSearchClient(credentials: EmptyCredentials())
    let connection = ConnectionSettings(host: "127.0.0.1", port: fixture.port, username: "fixture", security: .tls)
    let outcome = try await client.search(
        server: IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText),
        account: MailAccount(id: "fixture", name: "Fixture", addresses: [], kind: .imap, connection: connection),
        username: "fixture",
        password: "fixture",
        query: SearchQuery(mode == "icloud-flagged" ? "" : "fixture", flaggedOnly: mode == "icloud-flagged"),
        iCloud: mode.hasPrefix("icloud"),
        receive: { await updates.add($0) },
    )
    let rows = await updates.rows
    let commands = try fixture.commands()
    #expect(commands
        .allSatisfy { command in
            ["CAPABILITY", "LOGIN", "LIST", "EXAMINE", "UID", "NAMESPACE", "SEARCH FLAGGED"]
                .contains(command) || command
                .hasPrefix("UID FETCH")
        })
    let fetches = commands.filter { $0.hasPrefix("UID FETCH") }
    #expect(fetches
        .allSatisfy { command in
            command.replacing("\"", with: "")
                .hasSuffix("(UID INTERNALDATE FLAGS BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE MESSAGE-ID)])")
        })
    #expect(commands.contains("SELECT") == false)
    switch mode {
    case "esearch",
         "icloud-readwrite",
         "normal",
         "oversized":
        #expect(outcome == .complete)
        #expect(rows.count == 240)
        #expect(fetches.count == 6)
        #expect(rows.allSatisfy { $0.isFlagged == ($0.id.uid.isMultiple(of: 2)) })
        #expect(Set(rows.map(\.id.mailbox)) == ["INBOX", "Archive"])
        #expect(rows.allSatisfy { $0.id.uidValidity == 71 && $0.messageID != nil && $0.subject == "Résumé" })

    case "partial":
        #expect(outcome == .incomplete)
        #expect(rows.count == 120)

    case "icloud-flagged":
        #expect(outcome == .complete)
        #expect(rows.count == 120 && rows.allSatisfy(\.isFlagged))
        #expect(commands.contains("SEARCH FLAGGED"))

    case "empty":
        #expect(outcome == .complete)
        #expect(rows.isEmpty)

    case "missing":
        #expect(outcome == .incomplete)
        #expect(rows.count == 238)

    case "whitespace":
        #expect(outcome == .incomplete)
        #expect(commands.contains("EXAMINE") == false)
        #expect(rows.isEmpty)

    case "icloud-no-next",
         "icloud-no-validity",
         "readwrite":
        #expect(outcome == .incomplete)
        #expect(fetches.isEmpty)
        let failure = ["icloud-no-validity": SearchFailure.uidValidity, "icloud-no-next": .uidNext][mode] ?? .readOnly
        #expect(await updates.values.contains(.notice("INBOX: \(failure.rawValue)")))

    case "cap":
        #expect(outcome == .incomplete)
        #expect(rows.count == SearchLimits.resultsPerAccount)

    default:
        Issue.record("Unknown fixture mode")
    }
    #expect(await updates.values.contains(where: { update in
        guard case let .notice(text) = update else {
            return false
        }

        return text.contains("iCloud reports read-write")
    }) == false)
}

// swiftlint:enable function_body_length

@Test(arguments: ["auth", "disconnect", "timeout"])
func `fixture failures are typed`(mode: String) async throws {
    let fixture = try Fixture(mode: mode)
    let client = SwiftMailSearchClient(credentials: EmptyCredentials())
    do {
        _ = try await client.search(
            server: IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText),
            account: MailAccount(
                id: "fixture",
                name: "Fixture",
                addresses: [],
                kind: .imap,
                connection: ConnectionSettings(
                    host: "127.0.0.1",
                    port: fixture.port,
                    username: "fixture",
                    security: .tls,
                ),
            ),
            username: "fixture",
            password: "fixture",
            query: SearchQuery("fixture"),
            receive: { _ in },
        )
        Issue.record("Fixture should fail")
    } catch {
        #expect(error as? SearchFailure ==
            (mode == "auth" ? .authentication : mode == "timeout" ? .timeout : .connection))
    }
}

@MainActor
@Test
func `automation scripts compile without accessing mail`() {
    unsafe #expect(NSAppleScript(source: MailAutomation.discoveryScript)?.compileAndReturnError(nil) == true)
}

@Test
func `saved STARTTLS is rejected before reading credentials or connecting`() async throws {
    let connection = try JSONDecoder().decode(ConnectionSettings.self, from: Data(
        #"{"host":"127.0.0.1","port":143,"username":"fixture","security":"STARTTLS"}"#.utf8,
    ))
    let credentials = EmptyCredentials()
    let client = SwiftMailSearchClient(credentials: credentials)
    await #expect(throws: SearchFailure.unsupportedTransport) {
        _ = try await client.session(accountID: "fixture", connection: connection)
    }
    #expect(await credentials.passwordReads == 0)
    await #expect(throws: SearchFailure.unsupportedTransport) {
        try await client.verify(connection: connection, password: "fixture")
    }
}

@Test
func `cancelling search stops further metadata requests`() async throws {
    let fixture = try Fixture(mode: "normal")
    let gate = BatchGate()
    let client = SwiftMailSearchClient(credentials: EmptyCredentials())
    let server = IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText)
    let connection = ConnectionSettings(host: "127.0.0.1", port: fixture.port, username: "fixture", security: .tls)
    let task = Task {
        try await client.search(
            server: server,
            account: MailAccount(id: "fixture", name: "Fixture", addresses: [], kind: .imap, connection: connection),
            username: "fixture",
            password: "fixture",
            query: SearchQuery("fixture"),
            receive: { await gate.receive($0) },
        )
    }
    await gate.wait()
    task.cancel()
    await gate.resume()
    do {
        _ = try await task.value
        Issue.record("Cancellation must propagate")
    } catch {
        #expect(error is CancellationError)
        #expect(try fixture.commands().count(where: { $0.hasPrefix("UID FETCH") }) == 1)
    }
}
