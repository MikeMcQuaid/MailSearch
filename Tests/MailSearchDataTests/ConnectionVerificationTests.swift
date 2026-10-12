import Foundation
@testable import MailSearchData
import MailSearchDomain
import SwiftMail
import Testing

@Test(arguments: ["normal", "plain-ir", "plain-reject", "auth"])
func `connection verification only authenticates and disconnects`(mode: String) async throws {
    let fixture = try Fixture(mode: mode)
    let client = SwiftMailSearchClient(credentials: EmptyCredentials())
    var failure: SearchFailure?
    do {
        try await client.verify(
            server: IMAPServer(host: "127.0.0.1", port: fixture.port, transportSecurity: .plainText),
            username: "fixture",
            password: "fixture",
        )
    } catch { failure = error as? SearchFailure; #expect(failure != nil) }
    #expect(failure == (["auth", "plain-reject"].contains(mode) ? .authentication : nil))
    let commands = try fixture.commands()
    #expect(commands == [mode.hasPrefix("plain") ? "AUTHENTICATE" : "LOGIN"] + (failure == nil ? ["CAPABILITY"] : []))
}

@Test
func `cancelled verification never opens a connection`() async throws {
    let fixture = try Fixture(mode: "normal")
    let port = fixture.port
    let client = SwiftMailSearchClient(credentials: EmptyCredentials())
    let task = Task {
        unsafe withUnsafeCurrentTask { unsafe $0?.cancel() }
        try await client.verify(
            server: IMAPServer(host: "127.0.0.1", port: port, transportSecurity: .plainText),
            username: "fixture",
            password: "fixture",
        )
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try fixture.commands().isEmpty)
}
