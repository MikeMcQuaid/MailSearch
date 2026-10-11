import Foundation
import MailSearchDomain
@testable import MailSearchFeatures
import Testing

@MainActor @Test func `previews complete while two searches are still producing results`() async throws {
    let client = Client(holdAfterBatch: true)
    let previewer = Previewer()
    let model = SearchModel(
        source: Accounts([account("a"), account("b")]), client: client,
        credentials: Credentials(), settings: Settings(), flagger: Flagger(), previewer: previewer,
    )
    await model.refresh()
    model.showFlagged()
    await client.waitFor("a")
    await client.waitFor("b")
    let id = try #require(model.results.rows.first?.id)
    model.togglePreview(id)
    await model.waitForPreview()
    #expect(model.isSearching && model.expanded == id && model.preview?.text == id.accountID)
    await client.release("a")
    await client.release("b")
    await model.waitForSearch()
    #expect(model.expanded == id && model.preview?.text == id.accountID)
}

@MainActor @Test func `account changes cancel only irrelevant work and preserve submitted query`() async {
    let client = Client(holdAfterBatch: true)
    let model = SearchModel(
        source: Accounts([account("a"), account("b"), account("c")]), client: client,
        credentials: Credentials(), settings: Settings(), flagger: Flagger(), previewer: Previewer(),
    )
    await model.refresh()
    model.queryText = "submitted"
    model.submit()
    await client.waitFor("submitteda")
    await client.waitFor("submittedb")
    model.selection = model.results.rows.first { $0.id.accountID == "b" }?.id
    let selection = model.selection
    model.queryText = "unsubmitted edit"
    model.setEnabled(false, account: account("a"))
    #expect(model.results.rows.allSatisfy { $0.id.accountID == "b" })
    #expect(model.selection == selection)
    #expect(model.statuses["a"] == nil)
    await client.release("submitteda")
    await client.waitFor("submittedc")
    await client.release("submittedb")
    await client.release("submittedc")
    await model.waitForSearch()
    #expect(await client.cancelled == ["a"])
    #expect(await client.calls.sorted() == ["submitteda", "submittedb", "submittedc"])
    #expect(await client.maximum == 2)
    #expect(Set(model.results.rows.map(\.id.accountID)) == ["b", "c"])
}

@MainActor @Test func `cached results appear immediately and are removed by an empty refresh`() async {
    let client = Client()
    let model = SearchModel(
        source: Accounts([account("a")]), client: client, credentials: Credentials(),
        settings: Settings(), flagger: Flagger(), previewer: Previewer(),
    )
    await model.refresh()
    model.showFlagged()
    await model.waitForSearch()
    model.showAllMail()
    await client.setEmpty()
    model.showFlagged()
    #expect(model.results.rows.count == 1 && model.statuses["a"]?.isCached == true)
    await model.waitForSearch()
    #expect(model.results.rows.isEmpty && model.statuses["a"]?.isCached == false)
    #expect(model.statuses["a"]?.outcome == .complete)
}

@MainActor @Test func `preview clicks collapse and reuse only the exact cached location`() async throws {
    let previewer = Previewer()
    let model = SearchModel(
        source: Accounts([account("a"), account("b")]), client: Client(), credentials: Credentials(),
        settings: Settings(), flagger: Flagger(), previewer: previewer,
    )
    await model.refresh()
    model.showFlagged()
    await model.waitForSearch()
    let first = try #require(model.results.rows.first?.id)
    let second = try #require(model.results.rows.last?.id)
    model.togglePreview(first)
    await model.waitForPreview()
    #expect(model.preview?.text == first.accountID)
    model.togglePreview(first)
    #expect(model.expanded == nil && model.preview == nil && model.selection == first)
    model.togglePreview(first)
    #expect(model.preview?.text == first.accountID && !model.isPreviewing)
    #expect(await previewer.calls == [first])
    model.togglePreview(second)
    await model.waitForPreview()
    #expect(await previewer.calls == [first, second])
    model.close()
    model.togglePreview(first)
    await model.waitForPreview()
    #expect(await previewer.calls == [first, second, first])
}

@MainActor @Test func `memory cache expires and bounds bytes and entries`() {
    var cache = MemoryCache<Int, String>()
    let now = ContinuousClock.now
    cache.insert("fixture", for: 1, bytes: 10, now: now)
    #expect(cache.value(for: 1, now: now.advanced(by: .seconds(299))) == "fixture")
    #expect(cache.value(for: 1, now: now.advanced(by: .seconds(300))) == nil)
    for index in 0 ... 8 {
        cache.insert("fixture", for: index, bytes: 10, now: now)
    }
    #expect(cache.value(for: 0, now: now) == nil)
    #expect(cache.value(for: 1, now: now) == "fixture")
    cache.insert("large", for: 9, bytes: 16 * 1024 * 1024, now: now)
    #expect(cache.value(for: 8, now: now) == nil)
    #expect(cache.value(for: 9, now: now) == "large")
    cache.insert("oversized", for: 10, bytes: 16 * 1024 * 1024 + 1, now: now)
    #expect(cache.value(for: 10, now: now) == nil)
    cache.removeAll()
    #expect(cache.value(for: 9, now: now) == nil)
}

@MainActor @Test(arguments: [MailProvider.gmail, .iCloud])
func `provider endpoints cannot be overridden in settings or verification`(provider: MailProvider) async throws {
    let client = Client()
    let original = MailAccount(
        id: "provider", name: "Provider", addresses: [], kind: provider == .iCloud ? .iCloud : .imap,
        connection: ConnectionSettings(
            host: provider == .gmail ? "imap.gmail.com" : "imap.mail.me.com",
            port: 993,
            username: "fixture",
            security: .tls,
        ),
    )
    let settings = Settings()
    let custom = ConnectionSettings(host: "wrong.example.test", port: 143, username: "corrected", security: .startTLS)
    settings.accounts[original.id] = AccountSettings(connection: custom)
    let model = SearchModel(
        source: Accounts([original]), client: client, credentials: Credentials(),
        settings: settings, flagger: Flagger(), previewer: Previewer(),
    )
    #expect(model.connection(for: original) == provider.fixedEndpoint(custom))
    try await model.configure(original, connection: custom, password: "fixture")
    #expect(await client.verifiedConnection == provider.fixedEndpoint(custom))
    #expect(settings.accounts[original.id]?.connection == provider.fixedEndpoint(custom))
}

@MainActor @Test func `failed refresh retains a cache label and new queries do not reuse it`() async {
    let client = Client()
    let model = SearchModel(
        source: Accounts([account("a")]), client: client, credentials: Credentials(),
        settings: Settings(), flagger: Flagger(), previewer: Previewer(),
    )
    await model.refresh()
    model.showFlagged()
    await model.waitForSearch()
    await client.failSearch()
    model.showFlagged()
    await model.waitForSearch()
    #expect(model.results.rows.count == 1 && model.statuses["a"]?.isCached == true)
    #expect(model.statuses["a"]?.outcome == .failed(.authentication))
    #expect(model.summary.hasPrefix("Incomplete"))
    model.queryText = "new phrase"
    model.submit()
    #expect(model.results.rows.isEmpty && model.statuses["a"]?.isCached == false)
    await model.waitForSearch()
}

@MainActor @Test func `flag changes invalidate cached searches`() async throws {
    let model = SearchModel(
        source: Accounts([account("a")]), client: Client(), credentials: Credentials(),
        settings: Settings(), flagger: Flagger(), previewer: Previewer(),
    )
    await model.refresh()
    model.showFlagged()
    await model.waitForSearch()
    let id = try #require(model.results.rows.first?.id)
    await model.toggleFlag(id)
    model.showFlagged()
    #expect(model.results.rows.isEmpty && model.statuses["a"]?.isCached == false)
    await model.waitForSearch()
}

@MainActor @Test(arguments: [false, true])
func `one click opens a preview regardless of list selection event order`(selectionFirst: Bool) async throws {
    let previewer = Previewer()
    let model = SearchModel(
        source: Accounts([account("a"), account("b")]), client: Client(), credentials: Credentials(),
        settings: Settings(), flagger: Flagger(), previewer: previewer,
    )
    await model.refresh()
    model.showFlagged()
    await model.waitForSearch()
    let first = try #require(model.results.rows.first?.id)
    let second = try #require(model.results.rows.last?.id)
    for id in [first, second] {
        if selectionFirst {
            model.selection = id; model.selectionDidChange()
        }
        model.togglePreview(id)
        if !selectionFirst {
            model.selectionDidChange()
        }
        await model.waitForPreview()
        #expect(model.expanded == id && model.preview?.text == id.accountID)
    }
    model.togglePreview(second)
    model.selectionDidChange()
    #expect(model.expanded == nil && model.preview == nil)
    #expect(await previewer.calls == [first, second])
}

@MainActor @Test func `reenabling an account waits for its cancelled search to drain`() async {
    let client = Client(held: true)
    let model = SearchModel(
        source: Accounts([account("a")]), client: client, credentials: Credentials(),
        settings: Settings(), flagger: Flagger(), previewer: Previewer(),
    )
    await model.refresh()
    model.queryText = "q"
    model.submit()
    await client.waitFor("qa")
    model.setEnabled(false, account: account("a"))
    model.setEnabled(true, account: account("a"))
    #expect(model.isSearching && model.isStopping)
    #expect(await client.calls == ["qa"])
    await client.release("qa")
    await client.waitFor("qa")
    #expect(model.results.rows.isEmpty)
    #expect(await client.calls == ["qa", "qa"])
    #expect(await client.maximum == 1)
    await client.release("qa")
    await model.waitForSearch()
    #expect(model.results.rows.count == 1)
    #expect(model.statuses["a"]?.outcome == .complete)
    #expect(!model.isSearching && !model.isStopping)
}
