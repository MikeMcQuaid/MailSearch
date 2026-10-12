import MailSearchDomain
@testable import MailSearchFeatures
import Testing

// MARK: - FailedMail

private struct FailedMail: MailAccountSource {
    let failure: MailAutomationFailure

    func accounts() throws -> [MailAccount] {
        throw failure
    }
}

@MainActor
@Test(arguments: [-1_743, -1_712, -10_004, -600, -1_708])
func `discovery retains specific Mail errors`(code: Int) async {
    let mail = FailedMail(failure: MailAutomationFailure(code: code))
    let discovery = SearchModel(
        source: mail,
        client: Client(),
        credentials: Credentials(),
        settings: Settings(),
        flagger: Flagger(),
        previewer: Previewer(),
    )
    await discovery.refresh()
    #expect(discovery.error == mail.failure.errorDescription)
}
