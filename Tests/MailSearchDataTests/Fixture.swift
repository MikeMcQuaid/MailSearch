import Foundation
import MailSearchDomain
import SwiftMail
import Testing

// MARK: - EmptyCredentials

actor EmptyCredentials: CredentialStore {
    private(set) var passwordReads = 0

    func authorise() throws {
        throw SearchFailure.credentials
    }

    func contains(_: String) -> Bool {
        false
    }

    func password(for _: String) -> String? {
        passwordReads += 1
        return nil
    }

    func save(password _: String, for _: String) {
        // This fixture has no persistent credentials.
    }
}

// MARK: - Updates

actor Updates {
    var values: [SearchUpdate] = []

    var rows: [SearchResult] {
        values.flatMap { value -> [SearchResult] in
            if case let .batch(rows) = value {
                return rows
            }
            return []
        }
    }

    func add(_ value: SearchUpdate) {
        values.append(value)
    }
}

// MARK: - Fixture

final class Fixture {
    // MARK: Lifecycle

    init(mode: String, certificate: String? = nil) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = try [
            #require(Bundle.module.url(forResource: "imap", withExtension: "py", subdirectory: "Fixtures")).path,
            mode,
            directory.appendingPathComponent("commands.json").path,
        ]
        if let certificate {
            process.arguments?.append(certificate)
        }
        process.standardOutput = output
        process.terminationHandler = { [terminated] _ in terminated.signal() }
        try process.run()
        let portText = try #require(String(data: output.fileHandleForReading.availableData, encoding: .utf8))
        port = try #require(Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    deinit {
        if process.isRunning {
            process.terminate()
        }
        #expect(terminated.wait(timeout: .now() + 5) == .success, "Fixture process did not terminate")
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Internal

    let process: Process = .init()
    let directory: URL
    let port: Int

    func commands() throws -> [String] {
        try JSONDecoder().decode(
            [String].self,
            from: Data(contentsOf: directory.appendingPathComponent("commands.json")),
        )
    }

    func waitFor(_ event: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(event).path) == false {
            try #require(ContinuousClock.now < deadline, "Fixture did not report \(event)")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Private

    private let terminated: DispatchSemaphore = .init(value: 0)
}

// MARK: - BatchGate

actor BatchGate {
    var started = false
    var waiter: CheckedContinuation<Void, Never>?
    var release: CheckedContinuation<Void, Never>?
    var batches = 0

    func receive(_ update: SearchUpdate) async {
        guard case .batch = update else {
            return
        }

        batches += 1
        await withCheckedContinuation { continuation in
            release = continuation
            started = true
            waiter?.resume()
            waiter = nil
        }
    }

    func wait() async {
        if started {
            return
        }
        await withCheckedContinuation { waiter = $0 }
    }

    func resume() {
        release?.resume(); release = nil
    }
}
