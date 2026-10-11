import MailSearchDomain
@testable import MailSearchFeatures
import Testing

private struct FailedMail: MailAccountSource {
    let failure: MailAutomationFailure
    func accounts() throws -> [MailAccount] {
        throw failure
    }
}

@MainActor @Test(arguments: [-1743, -1712, -10004, -600, -1708])
func `discovery retains specific Mail errors`(code: Int) async {
    let mail = FailedMail(failure: MailAutomationFailure(code: code))
    let discovery = SearchModel(
        source: mail, client: Client(),
        credentials: Credentials(), settings: Settings(), flagger: Flagger(), previewer: Previewer(),
    )
    await discovery.refresh()
    #expect(discovery.error == mail.failure.errorDescription)
}
