import Foundation
@testable import MailSearchData
import MailSearchDomain
import Testing

@Test(arguments: [-1_743, -1_712, -10_004, -600, -1_708])
func `mail failures preserve codes without exposing scripting data or misdiagnosing permissions`(code: Int) {
    let failure = MailAutomation.failure([
        NSAppleScript.errorNumber: code,
        NSAppleScript.errorMessage: "private message content and identifiers",
    ])
    let message = failure.errorDescription ?? ""
    #expect(message.contains(String(code)))
    #expect(message.contains("private message") == false)
    #expect(message.contains("Privacy & Security") == (code == -1_743))
    if code == -1_712 {
        #expect(message.contains("timed out"))
    }
}

@MainActor
@Test(arguments: [false, true])
func `discovery retains account type and available settings`(missingPort: Bool) throws {
    let source = MailAutomation.discoveryScript
        .replacing("tell application \"Mail\"", with: "using terms from application \"Mail\"")
        .replacing("end tell", with: "end using terms from")
        .replacing("every account", with: """
        {{\(missingPort ? "" : "port:993,") id:"fixture", name:"Fixture", account type:imap, ¬
            email addresses:{"alice@example.test"}, ¬
          server name:"imap.example.test", user name:"alice", uses ssl:true, enabled:true}}
        """)
    // swiftlint:disable:next legacy_objc_type - Required Objective-C API bridge.
    var error: NSDictionary?
    let descriptor = try #require(unsafe NSAppleScript(source: source)?.executeAndReturnError(&error))
    #expect(error == nil)
    let account = try #require(MailAutomation.decodeAccounts(descriptor).first)
    #expect(account.kind == .imap)
    #expect(account.addresses == ["alice@example.test"])
    #expect(account.connection.host == "imap.example.test")
    #expect(account.connection.username == "alice")
    #expect(account.exclusion == nil)
    #expect(account.discoveryWarnings.count == (missingPort ? 1 : 0))
    if missingPort {
        #expect(account.discoveryWarnings.first?.hasPrefix("port (error ") == true)
    }
}
