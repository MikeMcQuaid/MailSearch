import Foundation
@testable import MailSearchData
import MailSearchDomain
import SwiftMail
import Testing

@Test(arguments: ["valid", "wrong-host", "expired", "untrusted"])
func `system TLS verifies certificate trust hostname and expiry before authentication`(
    certificate: String,
) async throws {
    let fixture = try Fixture(mode: "plain-ir", certificate: certificate == "untrusted" ? "valid" : certificate)
    let root = try Data(contentsOf: fixture.directory.appendingPathComponent("root.der"))
    let server = IMAPServer(
        host: "localhost", port: fixture.port, transportSecurity: .implicitTLS,
        certificateVerificationPolicy: certificate == "untrusted" ? .fullVerification : .trustRoots([root]),
    )
    let client = SwiftMailSearchClient(credentials: EmptyCredentials())
    if certificate == "valid" {
        try await client.verify(server: server, username: "fixture", password: "fixture")
        #expect(try fixture.commands() == ["AUTHENTICATE", "CAPABILITY"])
    } else {
        await #expect(throws: SearchFailure.connection) {
            try await client.verify(server: server, username: "fixture", password: "fixture")
        }
        #expect(try fixture.commands().isEmpty)
    }
}

@Test(arguments: ["gmail", "icloud-readwrite"])
func `provider searches use verified system TLS and read only commands`(mode: String) async throws {
    let fixture = try Fixture(mode: mode, certificate: "valid")
    let root = try Data(contentsOf: fixture.directory.appendingPathComponent("root.der"))
    let connection = ConnectionSettings(host: "localhost", port: fixture.port, username: "fixture", security: .tls)
    let updates = Updates()
    let outcome = try await SwiftMailSearchClient(credentials: EmptyCredentials()).search(
        server: IMAPServer(
            host: "localhost", port: fixture.port, transportSecurity: .implicitTLS,
            certificateVerificationPolicy: .trustRoots([root]),
        ),
        account: MailAccount(id: "fixture", name: "Fixture", addresses: [], kind: .imap, connection: connection),
        username: "fixture", password: "fixture", query: SearchQuery("something anything"),
        iCloud: mode.hasPrefix("icloud"), receive: { await updates.add($0) },
    )
    #expect(outcome == .complete)
    #expect(await updates.rows.count == 240)
    #expect(try fixture.commands().allSatisfy {
        ["LOGIN", "CAPABILITY", "LIST", "EXAMINE", "UID", "SEARCH X-GM-RAW"].contains($0) ||
            $0.hasPrefix("UID FETCH") && $0.contains("BODY.PEEK")
    })
}

@Test(arguments: [Duration.zero, .seconds(3)])
func `cancelling a stalled TLS handshake drains within the connection deadline`(startupDelay: Duration) async throws {
    let fixture = try Fixture(mode: "tls-stall")
    let connection = ConnectionSettings(host: "127.0.0.1", port: fixture.port, username: "fixture", security: .tls)
    let client = SwiftMailSearchClient(credentials: EmptyCredentials())
    let task = Task {
        try await Task.sleep(for: startupDelay)
        try await client.verify(connection: connection, password: "fixture")
    }
    try await fixture.waitFor("tls-started")
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    try await fixture.waitFor("tls-closed")
    let duration = try #require(Double(String(
        contentsOf: fixture.directory.appendingPathComponent("tls-duration"), encoding: .utf8,
    )))
    #expect(duration < 12)
    #expect(try fixture.commands().isEmpty)
}
