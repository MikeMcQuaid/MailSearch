import Foundation
import MailSearchDomain
@testable import MailSearchFeatures
import Testing

@MainActor @Test func `partial failure does not hide other accounts`() async {
    let client = Client()
    let model = SearchModel(
        source: Accounts([account("good"), account("failed"), account("third")]),
        client: client,
        credentials: Credentials(),
        settings: Settings(), flagger: Flagger(), previewer: Previewer(),
    )
    await model.refresh()
    model.queryText = "report"
    model.submit()
    await model.waitForSearch()
    #expect(model.results.rows.count == 2)
    #expect(model.statuses["failed"]?.outcome == .failed(.authentication))
    #expect(model.summary.hasPrefix("Incomplete"))
    #expect(await client.maximum <= 2)
}

@MainActor @Test func `stale responses never reach replacement search`() async {
    let client = Client(held: true)
    let model = SearchModel(
        source: Accounts([account("a")]),
        client: client,
        credentials: Credentials(),
        settings: Settings(), flagger: Flagger(), previewer: Previewer(),
    )
    await model.refresh()
    model.queryText = "old"
    model.submit()
    await client.waitFor("olda")
    model.queryText = "new"
    model.submit()
    await client.release("olda")
    await client.waitFor("newa")
    #expect(model.results.rows.isEmpty)
    await client.release("newa")
    await model.waitForSearch()
    #expect(model.results.rows.map(\.subject) == ["new"])
    #expect(await client.maximum == 1)
}

@MainActor @Test func `cancellation rejects non cooperative late results`() async {
    let client = Client(held: true)
    let model = SearchModel(
        source: Accounts([account("a")]),
        client: client,
        credentials: Credentials(),
        settings: Settings(), flagger: Flagger(), previewer: Previewer(),
    )
    await model.refresh()
    model.queryText = "q"
    model.submit()
    await client.waitFor("qa")
    model.cancel()
    #expect(model.isStopping)
    await client.release("qa")
    await model.waitForSearch()
    #expect(model.results.rows.isEmpty)
    #expect(model.statuses["a"]?.outcome == .cancelled)
    #expect(model.summary.contains("cancelled"))
    #expect(!model.isStopping)
}

@MainActor @Test func `settings never contain password`() async throws {
    let credentials = Credentials()
    let settings = Settings()
    let model = SearchModel(
        source: Accounts([]),
        client: Client(),
        credentials: credentials,
        settings: settings, flagger: Flagger(), previewer: Previewer(),
    )
    try await model.configure(account("a"), connection: testConnection, password: "fixture-secret")
    #expect(await credentials.password(for: testConnection.credentialKey(accountID: "a")) == "fixture-secret")
    #expect(try String(data: JSONEncoder().encode(settings.accounts), encoding: .utf8)?
        .contains("fixture-secret") == false)
}

@MainActor @Test(arguments: [false, true])
func `flagging preserves identity selection and search connection`(fails: Bool) async throws {
    let flagger = Flagger(failure: fails ? .flagUnconfirmed : nil)
    let model = SearchModel(
        source: Accounts([account("a"), account("b")]), client: Client(),
        credentials: Credentials(), settings: Settings(), flagger: flagger, previewer: Previewer(),
    )
    await model.refresh()
    model.queryText = "q"
    model.submit()
    await model.waitForSearch()
    let clicked = try #require(model.results.rows.first?.id)
    let originalOrder = model.results.rows.map(\.id)
    model.selection = model.results.rows.last?.id
    let selection = model.selection
    var changed = testConnection
    changed.host = "another.example.test"
    try await model.configure(account(clicked.accountID), connection: changed, password: "fixture")
    #expect(await flagger.calls.isEmpty)
    await model.toggleFlag(clicked)
    #expect(await flagger.calls.first?.0 == clicked)
    #expect(await flagger.calls.first?.1 == testConnection)
    #expect(model.selection == selection)
    #expect(model.results.rows.map(\.id) == originalOrder)
    #expect(model.results.rows.filter(\.isFlagged).map(\.id) == (fails ? [] : [clicked]))
    #expect((model.error != nil) == fails)
    if !fails {
        #expect(model.canFlag(clicked))
        await model.toggleFlag(clicked)
        #expect(await flagger.calls.count == 2)
        #expect(model.results.rows.allSatisfy { !$0.isFlagged })
    }
}

@MainActor @Test func `late flag completion never changes a new search`() async throws {
    let flagger = Flagger(held: true)
    let model = SearchModel(
        source: Accounts([account("a")]), client: Client(),
        credentials: Credentials(), settings: Settings(), flagger: flagger, previewer: Previewer(),
    )
    await model.refresh()
    model.queryText = "old"
    model.submit()
    await model.waitForSearch()
    let id = try #require(model.results.rows.first?.id)
    let task = Task { await model.toggleFlag(id) }
    await flagger.wait()
    #expect(!model.canFlag(id))
    await model.toggleFlag(id)
    #expect(await flagger.calls.count == 1)
    model.queryText = "new"
    model.submit()
    await model.waitForSearch()
    await flagger.resume()
    await task.value
    #expect(model.results.rows.first?.subject == "new")
    #expect(model.results.rows.first?.isFlagged == false)
    #expect(model.flagNotice == nil)
}

@MainActor @Test func `flagged only allows submission without text`() async {
    let model = SearchModel(
        source: Accounts([account("a")]), client: Client(),
        credentials: Credentials(), settings: Settings(), flagger: Flagger(), previewer: Previewer(),
    )
    await model.refresh()
    model.flaggedOnly = true
    model.submit()
    await model.waitForSearch()
    #expect(model.hasSearched)
    #expect(model.error == nil)
}

@MainActor @Test func `cancelling search retains the confirmed flag on retained results`() async throws {
    let client = Client(holdAfterBatch: true)
    let flagger = Flagger(held: true)
    let model = SearchModel(
        source: Accounts([account("a")]), client: client,
        credentials: Credentials(), settings: Settings(), flagger: flagger, previewer: Previewer(),
    )
    await model.refresh()
    model.queryText = "q"
    model.submit()
    await client.waitFor("qa")
    let id = try #require(model.results.rows.first?.id)
    let task = Task { await model.toggleFlag(id) }
    await flagger.wait()
    model.cancel()
    await client.release("qa")
    await model.waitForSearch()
    await flagger.resume()
    await task.value
    #expect(model.results.rows.first?.isFlagged == true)
    #expect(model.flagNotice != nil)
}

@MainActor @Test func `connect remembers credentials without claiming a verified connection`() async throws {
    let credentials = Credentials()
    let model = SearchModel(
        source: Accounts([account("a")]), client: Client(),
        credentials: credentials, settings: Settings(), flagger: Flagger(), previewer: Previewer(),
    )
    await model.refresh()
    #expect(model.credentialAccounts.isEmpty)
    #expect(!model.hasSearched)
    var connection = testConnection
    connection.host = "imap.gmail.com"
    do {
        try await model.configure(account("a"), connection: connection, password: " \n\t ")
        Issue.record("Whitespace must not be stored as a Google app password")
    } catch {
        #expect(error as? SearchFailure == .credentials)
    }
    #expect(model.credentialAccounts.isEmpty)
    #expect(await credentials.password(for: connection.credentialKey(accountID: "a")) == nil)
    try await model.configure(account("a"), connection: connection, password: "abcd efgh ijkl mnop")
    #expect(model.credentialAccounts == ["a"])
    #expect(await credentials.password(for: connection.credentialKey(accountID: "a")) == "abcdefghijklmnop")
    await model.refresh()
    #expect(model.credentialAccounts == ["a"])
    #expect(!model.hasSearched)
}

@MainActor @Test func `flagged button clears text and submits immediately`() async {
    let client = Client()
    let model = SearchModel(
        source: Accounts([account("a")]),
        client: client,
        credentials: Credentials(),
        settings: Settings(),
        flagger: Flagger(),
        previewer: Previewer(),
    )
    await model.refresh()
    model.queryText = "old search"
    model.showFlagged()
    await model.waitForSearch()
    #expect(model.queryText.isEmpty)
    #expect(model.flaggedOnly && model.hasSearched)
    #expect(model.results.rows.count == 1)
    #expect(model.error == nil)
}

@MainActor @Test func `unflagging preserves the row selection and unrelated flags`() async throws {
    let flagger = Flagger()
    let model = SearchModel(
        source: Accounts([account("a")]),
        client: Client(),
        credentials: Credentials(),
        settings: Settings(),
        flagger: flagger,
        previewer: Previewer(),
    )
    await model.refresh()
    model.showFlagged()
    await model.waitForSearch()
    let id = try #require(model.results.rows.first?.id)
    model.selection = id
    await model.toggleFlag(id)
    #expect(model.selectedResult?.isFlagged == true)
    await model.toggleFlag(id)
    #expect(model.selectedResult?.isFlagged == false)
    #expect(model.selection == id)
    #expect(await flagger.flagValues == [true, false])
}

@MainActor @Test func `preview is on demand serial and rejects stale selection replies`() async throws {
    let previewer = Previewer(held: true)
    let model = SearchModel(
        source: Accounts([account("a"), account("b")]),
        client: Client(),
        credentials: Credentials(),
        settings: Settings(),
        flagger: Flagger(),
        previewer: previewer,
    )
    await model.refresh()
    model.queryText = "q"
    model.submit()
    await model.waitForSearch()
    #expect(await previewer.calls.isEmpty)
    model.selection = try #require(model.results.rows.first?.id)
    model.loadPreview()
    await previewer.wait()
    let next = try #require(model.results.rows.last?.id)
    model.selection = next
    model.loadPreview()
    #expect(model.isPreviewing && model.preview == nil)
    #expect(await previewer.calls.count == 1)
    await previewer.resume()
    await model.waitForPreview()
    #expect(model.preview?.text == next.accountID)
    #expect(!model.isPreviewing)
    model.close()
    #expect(model.preview == nil)
}

@MainActor @Test func `dismissing the panel rejects an unfinished preview`() async throws {
    let previewer = Previewer(held: true)
    let model = SearchModel(
        source: Accounts([account("a")]),
        client: Client(),
        credentials: Credentials(),
        settings: Settings(),
        flagger: Flagger(),
        previewer: previewer,
    )
    await model.refresh()
    model.showFlagged()
    await model.waitForSearch()
    model.selection = try #require(model.results.rows.first?.id)
    model.loadPreview()
    await previewer.wait()
    model.cancelPreview()
    await previewer.resume()
    await model.waitForPreview()
    #expect(model.preview == nil && !model.isPreviewing)
}

@MainActor @Test func `explicit username correction reuses a password only on the same server`() async throws {
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
    var corrected = testConnection
    corrected.username = "primary@icloud.com"
    try await model.configure(account("a"), connection: corrected, password: "")
    #expect(await credentials.password(for: corrected.credentialKey(accountID: "a")) == "fixture-secret")
    corrected.host = "other.example.test"
    await #expect(throws: SearchFailure.credentials) {
        try await model.configure(account("a"), connection: corrected, password: "")
    }
    #expect(await credentials.password(for: corrected.credentialKey(accountID: "a")) == nil)
}
