import MailSearchDomain
@testable import MailSearchFeatures
import Testing

@MainActor
@Test
func `verification is bounded and forwards cancellation`() async {
    let client = Client(held: true)
    let credentials = Credentials()
    let settings = Settings()
    let model = SearchModel(
        source: Accounts([]),
        client: client,
        credentials: credentials,
        settings: settings,
        flagger: Flagger(),
        previewer: Previewer(),
    )
    let task = Task { try await model.configure(account("a"), connection: testConnection, password: "fixture") }
    await client.waitFor("verification")
    await #expect(throws: SearchFailure.verificationInProgress) {
        try await model.configure(account("b"), connection: testConnection, password: "fixture")
    }
    task.cancel()
    await client.release("verification")
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await client.verifiedConnection == nil)
    #expect(await credentials.values.isEmpty)
    #expect(settings.accounts.isEmpty)
}

@MainActor
@Test
func `saving never reads passwords back and refreshing only checks metadata`() async throws {
    let credentials = Credentials()
    let model = SearchModel(
        source: Accounts([account("a")]),
        client: Client(),
        credentials: credentials,
        settings: Settings(),
        flagger: Flagger(),
        previewer: Previewer(),
    )
    try await model.configure(account("a"), connection: testConnection, password: "fixture-secret")
    #expect(await credentials.passwordReads == 0)
    await model.refresh()
    await model.refresh()
    #expect(model.credentialAccounts == ["a"])
    #expect(await credentials.passwordReads == 0)
    #expect(model.error == nil)
}

@MainActor
@Test
func `iCloud login trims pasted whitespace and preserves app password hyphens`() async throws {
    let credentials = Credentials()
    let model = SearchModel(
        source: Accounts([]),
        client: Client(),
        credentials: credentials,
        settings: Settings(),
        flagger: Flagger(),
        previewer: Previewer(),
    )
    let connection = ConnectionSettings(host: "imap.mail.me.com", port: 993, username: "primary@me.com", security: .tls)
    var pasted = connection
    pasted.username = " primary@me.com "
    try await model.configure(account("cloud"), connection: pasted, password: " abcd-efgh-ijkl-mnop\n")
    #expect(model.connection(for: account("cloud")) == connection)
    #expect(await credentials.password(for: connection.credentialKey(accountID: "cloud")) == "abcd-efgh-ijkl-mnop")
}

@MainActor
@Test
func `search diagnostics retain the login actually used after editing settings`() async throws {
    let model = SearchModel(
        source: Accounts([account("a")]),
        client: Client(),
        credentials: Credentials(),
        settings: Settings(),
        flagger: Flagger(),
        previewer: Previewer(),
    )
    await model.refresh()
    model.queryText = "fixture"
    model.submit()
    await model.waitForSearch()
    var corrected = testConnection
    corrected.username = "primary@me.com"
    try await model.configure(account("a"), connection: corrected, password: "fixture")
    #expect(model.connection(for: account("a")) == corrected)
    #expect(model.statuses["a"]?.connection == testConnection)
    model.submit()
    await model.waitForSearch()
    #expect(model.statuses["a"]?.connection == corrected)
}

@MainActor
@Test
func `save verifies before changing credentials or settings`() async throws {
    let client = Client()
    let credentials = Credentials()
    let settings = Settings()
    let model = SearchModel(
        source: Accounts([]),
        client: client,
        credentials: credentials,
        settings: settings,
        flagger: Flagger(),
        previewer: Previewer(),
    )
    await #expect(throws: SearchFailure.authentication) {
        try await model.configure(account("draft"), connection: testConnection, password: "rejected")
    }
    #expect(await credentials.values.isEmpty)
    #expect(settings.accounts.isEmpty && model.settings.isEmpty)
    try await model.configure(account("draft"), connection: testConnection, password: "accepted")
    #expect(await client.verifiedPassword == "accepted")
    #expect(await credentials.password(for: testConnection.credentialKey(accountID: "draft")) == "accepted")
    var changed = testConnection
    changed.username = "incorrect"
    await #expect(throws: SearchFailure.authentication) {
        try await model.configure(account("draft"), connection: changed, password: "rejected")
    }
    #expect(model.connection(for: account("draft")) == testConnection)
    #expect(await credentials.password(for: testConnection.credentialKey(accountID: "draft")) == "accepted")
    #expect(await credentials.contains(changed.credentialKey(accountID: "draft")) == false)
}
