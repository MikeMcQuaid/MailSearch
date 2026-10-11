import Foundation
@testable import MailSearchData
import MailSearchDomain
import SwiftMail
import Testing

@Test(arguments: ["normal", "partial", "empty", "missing", "readwrite", "cap", "esearch", "oversized", "whitespace",
                  "icloud-readwrite", "icloud-flagged", "icloud-no-validity", "icloud-no-next"])
func `read only fixture`(mode: String) async throws {
    let fixture = try Fixture(mode: mode)
    let updates = Updates()
    let client = SwiftMailSearchClient(credentials: EmptyCredentials())
    let connection = ConnectionSettings(host: "127.0.0.1", port: fixture.port, username: "fixture", security: .tls)
    let outcome = try await client.search(
        server: IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText),
        account: MailAccount(id: "fixture", name: "Fixture", addresses: [], kind: .imap, connection: connection),
        username: "fixture", password: "fixture",
        query: SearchQuery(mode == "icloud-flagged" ? "" : "fixture", flaggedOnly: mode == "icloud-flagged"),
        iCloud: mode.hasPrefix("icloud"), receive: { await updates.add($0) },
    )
    let rows = await updates.rows
    let commands = try fixture.commands()
    #expect(commands
        .allSatisfy {
            ["CAPABILITY", "LOGIN", "LIST", "EXAMINE", "UID", "NAMESPACE", "SEARCH FLAGGED"].contains($0) || $0
                .hasPrefix("UID FETCH")
        })
    let fetches = commands.filter { $0.hasPrefix("UID FETCH") }
    #expect(fetches
        .allSatisfy {
            $0.replacingOccurrences(of: "\"", with: "")
                .hasSuffix("(UID INTERNALDATE FLAGS BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE MESSAGE-ID)])")
        })
    #expect(!commands.contains("SELECT"))
    switch mode {
    case "normal", "esearch", "oversized", "icloud-readwrite":
        #expect(outcome == .complete)
        #expect(rows.count == 240)
        #expect(fetches.count == 6)
        #expect(rows.allSatisfy { $0.isFlagged == ($0.id.uid % 2 == 0) })
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
        #expect(!commands.contains("EXAMINE"))
        #expect(rows.isEmpty)
    case "readwrite", "icloud-no-validity", "icloud-no-next":
        #expect(outcome == .incomplete)
        #expect(fetches.isEmpty)
        let failure = ["icloud-no-validity": SearchFailure.uidValidity, "icloud-no-next": .uidNext][mode] ?? .readOnly
        #expect(await updates.values.contains(.notice("INBOX: \(failure.rawValue)")))
    case "cap":
        #expect(outcome == .incomplete)
        #expect(rows.count == SearchLimits.resultsPerAccount)
    default: Issue.record("Unknown fixture mode")
    }
    #expect(await updates.values.filter { update in
        guard case let .notice(text) = update else { return false }
        return text.contains("iCloud reports read-write")
    }.isEmpty)
}

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
            username: "fixture", password: "fixture", query: SearchQuery("fixture"), receive: { _ in },
        )
        Issue.record("Fixture should fail")
    } catch {
        #expect(error as? SearchFailure ==
            (mode == "auth" ? .authentication : mode == "timeout" ? .timeout : .connection))
    }
}

@MainActor @Test func `automation scripts compile without accessing mail`() {
    unsafe #expect(NSAppleScript(source: MailAutomation.discoveryScript)?.compileAndReturnError(nil) == true)
}

@Test func `saved STARTTLS is rejected before reading credentials or connecting`() async throws {
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

@Test func `cancelling search stops further metadata requests`() async throws {
    let fixture = try Fixture(mode: "normal")
    let gate = BatchGate()
    let client = SwiftMailSearchClient(credentials: EmptyCredentials())
    let server = IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText)
    let connection = ConnectionSettings(host: "127.0.0.1", port: fixture.port, username: "fixture", security: .tls)
    let task = Task {
        try await client.search(
            server: server,
            account: MailAccount(id: "fixture", name: "Fixture", addresses: [], kind: .imap, connection: connection),
            username: "fixture", password: "fixture", query: SearchQuery("fixture"),
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
        #expect(try fixture.commands().filter { $0.hasPrefix("UID FETCH") }.count == 1)
    }
}

@Test(arguments: ["", "fixture"])
func `flagged only is searched on the server`(text: String) async throws {
    let fixture = try Fixture(mode: "flaggedsearch")
    let updates = Updates()
    let connection = ConnectionSettings(host: "127.0.0.1", port: fixture.port, username: "fixture", security: .tls)
    let outcome = try await SwiftMailSearchClient(credentials: EmptyCredentials()).search(
        server: IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText),
        account: MailAccount(id: "fixture", name: "Fixture", addresses: [], kind: .imap, connection: connection),
        username: "fixture", password: "fixture", query: SearchQuery(text, flaggedOnly: true),
        receive: { await updates.add($0) },
    )
    #expect(outcome == .complete)
    #expect(await updates.rows.count == 120)
    #expect(await updates.rows.allSatisfy(\.isFlagged))
    #expect(try fixture.commands().contains("SEARCH FLAGGED"))
}

@Test(arguments: [
    "flagnormal", "flagseen", "flagalready", "flagreadonly", "flagvalidity", "flagmissing",
    "flagdenied", "flagdisconnect", "flagvanished", "flagunsupported", "flagemptypersistent", "flagnopersistent",
    "flagremove", "flagremove-seen", "flagremove-noop", "flagremove-disconnect", "flagremove-expunge",
])
func `explicit flagging changes only one UID and preserves other flags`(mode: String) async throws {
    let fixture = try Fixture(mode: mode)
    let client = SwiftMailSearchClient(credentials: EmptyCredentials())
    var failure: SearchFailure?
    do {
        try await client.setFlag(
            !mode.hasPrefix("flagremove"),
            for: MessageLocation(accountID: "fixture", mailbox: "INBOX", uidValidity: 71, uid: 7),
            server: IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText),
            username: "fixture",
            password: "fixture",
        )
    } catch { failure = error as? SearchFailure; #expect(failure != nil) }
    let commands = try fixture.commands()
    let stores = commands.filter { $0.hasPrefix("UID STORE") }
    #expect(commands.allSatisfy {
        ["CAPABILITY", "LOGIN", "SELECT"].contains($0)
            || $0 == "UID FETCH 7 (UID FLAGS)" || $0 == "UID STORE 7 +FLAGS (\\Flagged)" || $0 == "UID STORE 7 -FLAGS (\\Flagged)"
    })
    switch mode {
    case "flagnormal", "flagseen", "flagremove", "flagremove-seen", "flagremove-expunge":
        #expect(failure == nil)
        #expect(stores.count == 1)
        #expect(commands.filter { $0.hasPrefix("UID FETCH") }.count == 2)
    case "flagalready", "flagremove-noop":
        #expect(failure == nil)
        #expect(stores.isEmpty)
    case "flagreadonly", "flagunsupported", "flagemptypersistent", "flagnopersistent":
        #expect(failure == .flagUnavailable)
        #expect(stores.isEmpty)
    case "flagvalidity", "flagmissing":
        #expect(failure == .staleMessage)
        #expect(stores.isEmpty)
    default:
        #expect(failure == .flagUnconfirmed)
        #expect(stores.count == 1)
    }
}

@Test(arguments: [
    "gmail", "gmail-quoted", "gmail-backslash", "gmail-unicode", "gmail-limit", "gmail-flagged", "gmail-reject",
    "gmail-absent",
    "imap-phrase",
])
func `phrase search is translated per server and safely encoded`(mode: String) async throws {
    let fixture = try Fixture(mode: mode)
    let updates = Updates()
    let text = mode == "gmail-quoted" ? "subject:\"report\" \\ archive" : mode == "gmail-unicode" ? "Résumé" :
        mode == "gmail-backslash" ? "path\\archive" : mode == "gmail-limit" ? String(repeating: "x", count: 1024) : "something anything"
    let connection = ConnectionSettings(host: "127.0.0.1", port: fixture.port, username: "fixture", security: .tls)
    let outcome = try await SwiftMailSearchClient(credentials: EmptyCredentials()).search(
        server: IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText),
        account: MailAccount(id: "fixture", name: "Fixture", addresses: [], kind: .imap, connection: connection),
        username: "fixture", password: "fixture", query: SearchQuery(text, flaggedOnly: mode == "gmail-flagged"),
        receive: { await updates.add($0) },
    )
    #expect(outcome == (mode == "gmail-reject" ? .incomplete : .complete))
    #expect(await updates.rows.count == (mode == "gmail-reject" ? 0 : mode == "gmail-flagged" ? 60 : 240))
    let commands = try fixture.commands()
    if mode == "gmail-flagged" {
        #expect(await Set(updates.rows.map(\.id.mailbox)) == ["[Gmail]/Suivis"])
        #expect(commands.filter { $0 == "EXAMINE" }.count == 1)
    }
    #expect(commands
        .contains("SEARCH X-GM-RAW") ==
        (!["gmail-absent", "gmail-quoted", "gmail-backslash", "imap-phrase"].contains(mode)))
    #expect(!commands.contains("SELECT"))
    #expect(!commands.contains(where: { $0.contains("STORE") }))
    #expect(await !updates.values.contains { update in
        guard case let .notice(text) = update else { return false }
        return text.contains("X-GM-RAW") || text.contains("Gmail operators") || text.contains("non-selectable")
    })
}

@Test(arguments: ["gmail-starred", "gmail-no-starred"])
func `Gmail flagged view works without text and falls back when Starred is absent`(mode: String) async throws {
    let fixture = try Fixture(mode: mode)
    let updates = Updates()
    let connection = ConnectionSettings(host: "127.0.0.1", port: fixture.port, username: "fixture", security: .tls)
    let outcome = try await SwiftMailSearchClient(credentials: EmptyCredentials()).search(
        server: IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText),
        account: MailAccount(id: "fixture", name: "Fixture", addresses: [], kind: .imap, connection: connection),
        username: "fixture", password: "fixture", query: SearchQuery("", flaggedOnly: true),
        receive: { await updates.add($0) },
    )
    #expect(outcome == .complete)
    #expect(await updates.rows.count == (mode == "gmail-starred" ? 60 : 120))
    #expect(await updates.rows.allSatisfy(\.isFlagged))
    #expect(try fixture.commands().contains("SEARCH FLAGGED"))
    #expect(await !updates.values.contains { update in
        guard case let .notice(text) = update else { return false }
        return text.contains("Starred")
    })
}

@Test(arguments: ["plain", "plain-ir", "plain-disabled", "plain-reject", "auth-disabled"])
func `password authentication follows advertised mechanisms without retrying rejected credentials`(
    mode: String,
) async throws {
    let fixture = try Fixture(mode: mode)
    let connection = ConnectionSettings(host: "127.0.0.1", port: fixture.port, username: "fixture", security: .tls)
    var failure: SearchFailure?
    do {
        _ = try await SwiftMailSearchClient(credentials: EmptyCredentials()).search(
            server: IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText),
            account: MailAccount(id: "fixture", name: "Fixture", addresses: [], kind: .imap, connection: connection),
            username: "fixture", password: "fixture", query: SearchQuery("fixture"), receive: { _ in },
        )
    } catch {
        failure = error as? SearchFailure
        #expect(failure != nil)
    }
    let commands = try fixture.commands()
    #expect(!commands.contains("LOGIN"))
    #expect(commands.filter { $0 == "AUTHENTICATE" }.count == (mode == "auth-disabled" ? 0 : 1))
    if mode == "plain-reject" || mode == "auth-disabled" {
        #expect(failure == .authentication)
        #expect(!commands.contains("LIST"))
    } else {
        #expect(failure == nil)
        #expect(commands.contains("LIST"))
    }
}

@Test(arguments: ["order-icloud", "order-icloud-name", "order-gmail", "order-gmail-name", "order-other"])
func `large provider mailboxes are searched last without losing locations`(mode: String) async throws {
    let fixture = try Fixture(mode: mode)
    let updates = Updates()
    let connection = ConnectionSettings(host: "127.0.0.1", port: fixture.port, username: "fixture", security: .tls)
    let outcome = try await SwiftMailSearchClient(credentials: EmptyCredentials()).search(
        server: IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText),
        account: MailAccount(id: "fixture", name: "Fixture", addresses: [], kind: .imap, connection: connection),
        username: "fixture", password: "fixture", query: SearchQuery("fixture"),
        iCloud: mode.hasPrefix("order-icloud"), receive: { await updates.add($0) },
    )
    let deferred = mode.contains("gmail") ?
        (mode.hasSuffix("-name") ? "[Google Mail]/All Mail" : "[Gmail]/Tous les messages") :
        (mode.hasSuffix("-name") ? "Archive" : "Archives")
    let names = mode == "order-other" ? [deferred, "INBOX", "Projects/Archive", "Sent"] :
        ["INBOX", "Projects/Archive", "Sent", deferred]
    #expect(await updates.values.compactMap { update -> String? in
        guard case let .progress(text) = update, text.hasPrefix("Mailbox ") else { return nil }
        return text
    } == names.enumerated().map { "Mailbox \($0.offset + 1) of 4: \(mailboxDisplayName($0.element))" })
    #expect(outcome == .complete)
    #expect(await Set(updates.rows.map(\.id.mailbox)) == Set(names))
    #expect(try fixture.commands().filter { $0 == "EXAMINE" }.count == 4)
    #expect(try !fixture.commands().contains("SELECT"))
}
