import Foundation
@testable import MailSearchData
import MailSearchDomain
import SwiftMail
import Testing

@Test(arguments: [
    "previewplain",
    "previewbase64",
    "previewhtml",
    "previewlarge",
    "previewattachment",
    "previewvalidity",
    "previewmissing",
    "previewwronguid",
    "previewicloud",
])
func `preview fetches bounded text without changing flags`(mode: String) async throws {
    let fixture = try Fixture(mode: mode)
    var preview: MessagePreview?
    var failure: SearchFailure?
    do {
        preview = try await SwiftMailSearchClient(credentials: EmptyCredentials()).preview(
            MessageLocation(accountID: "fixture", mailbox: "INBOX", uidValidity: 71, uid: 7),
            server: IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText),
            username: "fixture",
            password: "fixture",
            iCloud: mode == "previewicloud",
        )
    } catch { failure = error as? SearchFailure; #expect(failure != nil) }
    let commands = try fixture.commands()
    #expect(commands.contains("SELECT") == false)
    #expect(commands.contains { $0.contains("STORE") } == false)
    let bodies = commands.filter { $0.contains("BODY.PEEK") }
    #expect(bodies.count <= 8)
    switch mode {
    case "previewmissing",
         "previewvalidity":
        #expect(failure == .staleMessage)
        #expect(bodies.isEmpty)

    case "previewwronguid":
        #expect(preview == nil)

    case "previewlarge":
        #expect(failure == nil)
        #expect(preview?.text.count == 32_768 && preview?.isTruncated == true)
        #expect(bodies.count == 8)

    case "previewhtml":
        #expect(failure == nil)
        #expect(preview?.text == "Hello world")

    default:
        #expect(failure == nil)
        #expect(preview?.text == "Hello, résumé.")
        #expect(preview?.isTruncated == false)
        #expect(bodies.count == 1)
    }
}

@Test
func `preview never chooses attached or embedded text`() {
    let parts = [
        MessagePart(sectionString: "1", contentType: "text/plain", disposition: "attachment"),
        MessagePart(sectionString: "2", contentType: "message/rfc822"),
        MessagePart(sectionString: "2.1", contentType: "text/plain"),
        MessagePart(sectionString: "3", contentType: "text/html"),
    ]
    #expect(SwiftMailSearchClient.previewPart(parts)?.section.description == "3")
    #expect(SwiftMailSearchClient.previewPart(Array(parts.prefix(3))) == nil)
}

@Test
func `IMAP preview completes while a search connection remains busy`() async throws {
    let searchFixture = try Fixture(mode: "normal")
    let previewFixture = try Fixture(mode: "previewplain")
    let gate = BatchGate()
    let client = SwiftMailSearchClient(credentials: EmptyCredentials())
    let port = searchFixture.port
    let task = Task {
        try await client.search(
            server: IMAPServer(host: "127.0.0.1", port: port, transportSecurity: .plainText),
            account: MailAccount(
                id: "fixture",
                name: "Fixture",
                addresses: [],
                kind: .imap,
                connection: ConnectionSettings(
                    host: "127.0.0.1",
                    port: port,
                    username: "fixture",
                    security: .tls,
                ),
            ),
            username: "fixture",
            password: "fixture",
            query: SearchQuery("fixture"),
            receive: { await gate.receive($0) },
        )
    }
    await gate.wait()
    do {
        let preview = try await client.preview(
            MessageLocation(accountID: "fixture", mailbox: "INBOX", uidValidity: 71, uid: 7),
            server: IMAPServer(host: "127.0.0.1", port: previewFixture.port, transportSecurity: .plainText),
            username: "fixture",
            password: "fixture",
        )
        #expect(preview.text == "Hello, résumé.")
        #expect(await gate.batches == 1)
        #expect(try searchFixture.commands().count(where: { $0.hasPrefix("UID FETCH") }) == 1)
        #expect(try previewFixture.commands().contains { $0.contains("BODY.PEEK") })
    } catch {
        Issue.record(error)
    }
    task.cancel()
    await gate.resume()
    await #expect(throws: CancellationError.self) { try await task.value }
}
