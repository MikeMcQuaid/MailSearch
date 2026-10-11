import Foundation
import Testing

@Test(arguments: ["plain", "plain-ir", "normal"])
func `documented curl diagnostic authenticates and only examines INBOX`(mode: String) throws {
    let fixture = try Fixture(mode: mode)
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/curl")
    process.arguments = [
        "--disable", "--silent", "--show-error", "--no-verbose", "--connect-timeout", "10", "--max-time", "20",
        "--url", "imap://127.0.0.1:\(fixture.port)/", "--user", "fixture:fixture",
        "--login-options", mode == "normal" ? "AUTH=+LOGIN" : "AUTH=PLAIN", "--request", "EXAMINE INBOX",
    ] + (mode == "plain-ir" ? ["--sasl-ir"] : [])
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    let transcript = try #require(String(
        data: output.fileHandleForReading.readDataToEndOfFile()
            + errors.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8,
    ))
    #expect(!transcript.contains("AUTHENTICATE"))
    #expect(!transcript.contains("LOGIN"))
    #expect(!transcript.contains(Data("\0fixture\0fixture".utf8).base64EncodedString()))
    #expect(try fixture.commands() == ["CAPABILITY", mode == "normal" ? "LOGIN" : "AUTHENTICATE", "EXAMINE", "LOGOUT"])
}
