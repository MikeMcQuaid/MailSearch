import Foundation
@testable import MailSearchData
import MailSearchDomain
import SwiftMail
import Testing

@Test(arguments: ["", "fixture"])
func `flagged only is searched on the server`(text: String) async throws {
    let fixture = try Fixture(mode: "flaggedsearch")
    let updates = Updates()
    let connection = ConnectionSettings(host: "127.0.0.1", port: fixture.port, username: "fixture", security: .tls)
    let outcome = try await SwiftMailSearchClient(credentials: EmptyCredentials()).search(
        server: IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText),
        account: MailAccount(id: "fixture", name: "Fixture", addresses: [], kind: .imap, connection: connection),
        username: "fixture",
        password: "fixture",
        query: SearchQuery(text, flaggedOnly: true),
        receive: { await updates.add($0) },
    )
    #expect(outcome == .complete)
    #expect(await updates.rows.count == 120)
    #expect(await updates.rows.allSatisfy(\.isFlagged))
    #expect(try fixture.commands().contains("SEARCH FLAGGED"))
}

@Test(arguments: [
    "flagnormal",
    "flagseen",
    "flagalready",
    "flagreadonly",
    "flagvalidity",
    "flagmissing",
    "flagdenied",
    "flagdisconnect",
    "flagvanished",
    "flagunsupported",
    "flagemptypersistent",
    "flagnopersistent",
    "flagremove",
    "flagremove-seen",
    "flagremove-noop",
    "flagremove-disconnect",
    "flagremove-expunge",
])
func `explicit flagging changes only one UID and preserves other flags`(mode: String) async throws {
    let fixture = try Fixture(mode: mode)
    let client = SwiftMailSearchClient(credentials: EmptyCredentials())
    var failure: SearchFailure?
    do {
        try await client.setFlag(
            mode.hasPrefix("flagremove") == false,
            for: MessageLocation(accountID: "fixture", mailbox: "INBOX", uidValidity: 71, uid: 7),
            server: IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText),
            username: "fixture",
            password: "fixture",
        )
    } catch {
        failure = error as? SearchFailure; #expect(failure != nil)
    }
    let commands = try fixture.commands()
    let stores = commands.filter { $0.hasPrefix("UID STORE") }
    #expect(commands.allSatisfy { command in
        ["CAPABILITY", "LOGIN", "SELECT"].contains(command)
            || command == "UID FETCH 7 (UID FLAGS)"
            || command == "UID STORE 7 +FLAGS (\\Flagged)"
            || command == "UID STORE 7 -FLAGS (\\Flagged)"
    })
    switch mode {
    case "flagnormal",
         "flagremove",
         "flagremove-expunge",
         "flagremove-seen",
         "flagseen":
        #expect(failure == nil)
        #expect(stores.count == 1)
        #expect(commands.count(where: { $0.hasPrefix("UID FETCH") }) == 2)

    case "flagalready",
         "flagremove-noop":
        #expect(failure == nil)
        #expect(stores.isEmpty)

    case "flagemptypersistent",
         "flagnopersistent",
         "flagreadonly",
         "flagunsupported":
        #expect(failure == .flagUnavailable)
        #expect(stores.isEmpty)

    case "flagmissing",
         "flagvalidity":
        #expect(failure == .staleMessage)
        #expect(stores.isEmpty)

    default:
        #expect(failure == .flagUnconfirmed)
        #expect(stores.count == 1)
    }
}

@Test(arguments: [
    "gmail",
    "gmail-quoted",
    "gmail-backslash",
    "gmail-unicode",
    "gmail-limit",
    "gmail-flagged",
    "gmail-reject",
    "gmail-absent",
    "imap-phrase",
])
func `phrase search is translated per server and safely encoded`(mode: String) async throws {
    let fixture = try Fixture(mode: mode)
    let updates = Updates()
    let text =
        switch mode {
        case "gmail-quoted":
            "subject:\"report\" \\ archive"

        case "gmail-unicode":
            "Résumé"

        case "gmail-backslash":
            "path\\archive"

        case "gmail-limit":
            String(repeating: "x", count: 1_024)

        default:
            "something anything"
        }
    let connection = ConnectionSettings(host: "127.0.0.1", port: fixture.port, username: "fixture", security: .tls)
    let outcome = try await SwiftMailSearchClient(credentials: EmptyCredentials()).search(
        server: IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText),
        account: MailAccount(id: "fixture", name: "Fixture", addresses: [], kind: .imap, connection: connection),
        username: "fixture",
        password: "fixture",
        query: SearchQuery(text, flaggedOnly: mode == "gmail-flagged"),
        receive: { await updates.add($0) },
    )
    #expect(outcome == (mode == "gmail-reject" ? .incomplete : .complete))
    #expect(await updates.rows.count == (mode == "gmail-reject" ? 0 : mode == "gmail-flagged" ? 60 : 240))
    let commands = try fixture.commands()
    if mode == "gmail-flagged" {
        #expect(await Set(updates.rows.map(\.id.mailbox)) == ["[Gmail]/Suivis"])
        #expect(commands.count(where: { $0 == "EXAMINE" }) == 1)
    }
    #expect(commands
        .contains("SEARCH X-GM-RAW") ==
        (["gmail-absent", "gmail-quoted", "gmail-backslash", "imap-phrase"].contains(mode) == false))
    #expect(commands.contains("SELECT") == false)
    #expect(commands.contains(where: { $0.contains("STORE") }) == false)
    #expect(await updates.values.contains { update in
        guard case let .notice(text) = update else {
            return false
        }

        return text.contains("X-GM-RAW") || text.contains("Gmail operators") || text.contains("non-selectable")
    } == false)
}

@Test(arguments: ["gmail-starred", "gmail-no-starred"])
func `gmail flagged view works without text and falls back when Starred is absent`(mode: String) async throws {
    let fixture = try Fixture(mode: mode)
    let updates = Updates()
    let connection = ConnectionSettings(host: "127.0.0.1", port: fixture.port, username: "fixture", security: .tls)
    let outcome = try await SwiftMailSearchClient(credentials: EmptyCredentials()).search(
        server: IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText),
        account: MailAccount(id: "fixture", name: "Fixture", addresses: [], kind: .imap, connection: connection),
        username: "fixture",
        password: "fixture",
        query: SearchQuery("", flaggedOnly: true),
        receive: { await updates.add($0) },
    )
    #expect(outcome == .complete)
    #expect(await updates.rows.count == (mode == "gmail-starred" ? 60 : 120))
    #expect(await updates.rows.allSatisfy(\.isFlagged))
    #expect(try fixture.commands().contains("SEARCH FLAGGED"))
    #expect(await updates.values.contains { update in
        guard case let .notice(text) = update else {
            return false
        }

        return text.contains("Starred")
    } == false)
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
            username: "fixture",
            password: "fixture",
            query: SearchQuery("fixture"),
            receive: { _ in },
        )
    } catch {
        failure = error as? SearchFailure
        #expect(failure != nil)
    }
    let commands = try fixture.commands()
    #expect(commands.contains("LOGIN") == false)
    #expect(commands.count(where: { $0 == "AUTHENTICATE" }) == (mode == "auth-disabled" ? 0 : 1))
    if mode == "plain-reject" || mode == "auth-disabled" {
        #expect(failure == .authentication)
        #expect(commands.contains("LIST") == false)
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
        username: "fixture",
        password: "fixture",
        query: SearchQuery("fixture"),
        iCloud: mode.hasPrefix("order-icloud"),
        receive: { await updates.add($0) },
    )
    let deferred = mode.contains("gmail") ?
        (mode.hasSuffix("-name") ? "[Google Mail]/All Mail" : "[Gmail]/Tous les messages") :
        (mode.hasSuffix("-name") ? "Archive" : "Archives")
    let names = mode == "order-other" ? [deferred, "INBOX", "Projects/Archive", "Sent"] :
        ["INBOX", "Projects/Archive", "Sent", deferred]
    #expect(await updates.values.compactMap { update -> String? in
        guard case let .progress(text) = update, text.hasPrefix("Mailbox ") else {
            return nil
        }

        return text
    } == names.enumerated().map { "Mailbox \($0.offset + 1) of 4: \(mailboxDisplayName($0.element))" })
    #expect(outcome == .complete)
    #expect(await Set(updates.rows.map(\.id.mailbox)) == Set(names))
    #expect(try fixture.commands().count(where: { $0 == "EXAMINE" }) == 4)
    #expect(try fixture.commands().contains("SELECT") == false)
}
