import MailSearchDomain
@testable import MailSearchFeatures
import Testing

@MainActor
@Test(arguments: ["allowed", "keychain"])
func `a credential dialog dismissing the panel does not cancel its search`(accountID: String) async {
    let client = Client(held: true)
    let model = SearchModel(
        source: Accounts([account(accountID)]),
        client: client,
        credentials: Credentials(),
        settings: Settings(),
        flagger: Flagger(),
        previewer: Previewer(),
    )
    await model.refresh()
    model.queryText = "q"
    model.submit()
    await client.waitFor("q" + accountID)
    model.cancelPreview()
    #expect(model.isSearching)
    await client.release("q" + accountID)
    await model.waitForSearch()
    #expect(model.statuses[accountID]?.outcome == (accountID == "keychain" ? .failed(.keychainAccess) : .complete))
    #expect(model.results.rows.count == (accountID == "keychain" ? 0 : 1))
}
