import Foundation
import MailSearchDomain
import Testing

@Test(arguments: [
    ("[Gmail]/Sent Mail", "Sent Mail"),
    ("[Gmail]/Projects/2026", "Projects/2026"),
    ("[Google Mail]/All Mail", "All Mail"),
    ("Archive", "Archive"),
    ("Projects/[Gmail]/Archive", "Projects/[Gmail]/Archive"),
    ("[Gmail]/", "[Gmail]/"),
])
func `folder display names only remove leading Gmail namespaces`(mailbox: String, expected: String) {
    #expect(mailboxDisplayName(mailbox) == expected)
    #expect(MessageLocation(accountID: "fixture", mailbox: mailbox, uidValidity: 1, uid: 2).mailbox == mailbox)
}

@Test
func `literal query`() throws {
    #expect(try SearchQuery("  from:alice quarterly report  ").text == "from:alice quarterly report")
    #expect(throws: SearchFailure.invalidQuery) { try SearchQuery("  ") }
    #expect(try SearchQuery("  ", flaggedOnly: true).text.isEmpty)
    #expect(try SearchQuery("  ", flaggedOnly: true).flaggedOnly)
    #expect(throws: SearchFailure.invalidQuery) { try SearchQuery("a\rb", flaggedOnly: true) }
    #expect(throws: SearchFailure.invalidQuery) { try SearchQuery("x\r\nLOGOUT") }
    #expect(throws: SearchFailure.invalidQuery) { try SearchQuery(String(repeating: "a", count: 1_025)) }
}

@Test
func `gmail phrases keep plain input and avoid guessing quote escaping`() throws {
    #expect(try SearchQuery(" something anything ").gmailPhrase == "\"something anything\"")
    #expect(try SearchQuery("from:alice has:attachment").gmailPhrase == "\"from:alice has:attachment\"")
    #expect(try SearchQuery("subject:\"report\"").gmailPhrase == nil)
    #expect(try SearchQuery("path\\archive").gmailPhrase == nil)
    #expect(try SearchQuery("", flaggedOnly: true).gmailPhrase == nil)
    #expect(try SearchQuery(String(repeating: "x", count: 1_024)).gmailPhrase?.utf8.count == 1_026)
}

@Test
func `mailbox identity and newest first across batches`() {
    func row(_ mailbox: String, _ validity: UInt32, _ uid: UInt32, _ time: Double) -> SearchResult {
        SearchResult(
            id: MessageLocation(accountID: "a", mailbox: mailbox, uidValidity: validity, uid: uid),
            accountName: "A",
            subject: "Same subject",
            sender: "Alice",
            date: Date(timeIntervalSince1970: time),
            messageID: "<duplicate@example.test>",
        )
    }
    var collection = ResultCollection()
    let first = row("INBOX", 1, 1, 1)
    collection.append([first])
    collection.append([first, row("Sent", 1, 1, 100), row("INBOX", 2, 1, 200)])
    #expect(collection.rows.count == 3)
    #expect(collection.rows.last == first)
    #expect(collection.rows.first?.id.uidValidity == 2)
    let order = collection.rows.map(\.id)
    collection.setFlag(true, for: first.id)
    collection.append([first])
    #expect(collection.rows.filter(\.isFlagged).map(\.id) == [first.id])
    #expect(collection.rows.map(\.id) == order)
}

@Test
func `identity does not case fold or accept controls`() {
    #expect(MessageIdentity.normalise(" <ABC@example.test> ") == "ABC@example.test")
    #expect(MessageIdentity.normalise(nil) == nil)
    #expect(MessageIdentity.normalise("<x\r\n@example.test>") == nil)
    #expect(MessageIdentity.normalise("<missing>") == nil)
}

@Test
func `windows cover all UI ds without date assumptions`() {
    #expect(SearchLimits.window(start: 1, uidNext: 20_002) == 1 ... 10_000)
    #expect(SearchLimits.window(start: 10_001, uidNext: 20_002) == 10_001 ... 20_000)
    #expect(SearchLimits.window(start: 20_001, uidNext: 20_002) == 20_001 ... 20_001)
    #expect(SearchLimits.window(start: 20_002, uidNext: 20_002) == nil)
    #expect(SearchLimits.window(start: UInt32.max - 1, uidNext: .max) == (UInt32.max - 1) ... (UInt32.max - 1))
}

@Test
func `credentials follow connection identity`() {
    var connection = ConnectionSettings(host: "mail.example.test", port: 993, username: "a", security: .tls)
    let original = connection.credentialKey(accountID: "a")
    connection.host = "another.example.test"
    #expect(original != connection.credentialKey(accountID: "a"))
    connection.host = "bad.test/INBOX"
    #expect(connection.isValid == false)
}

@Test
func `message identity needs both parts`() {
    #expect(MessageIdentity.normalise("<@>") == nil)
    #expect(MessageIdentity.normalise("<a@>") == nil)
    #expect(MessageIdentity.normalise("<@example.test>") == nil)
}

@Test
func `provider suggestions fill gaps without replacing discovered settings`() {
    let missing = ConnectionSettings(host: "", port: 0, username: "", security: .startTLS)
    let gmail = MailAccount(id: "g", name: "Gmail", addresses: ["alice@gmail.com"], kind: .imap, connection: missing)
    #expect(MailProvider(account: gmail) == .gmail)
    #expect(MailProvider.gmail.suggestedConnection(for: gmail) == ConnectionSettings(
        host: "imap.gmail.com",
        port: 993,
        username: "alice@gmail.com",
        security: .tls,
    ))
    let cloud = MailAccount(
        id: "i",
        name: "iCloud",
        addresses: ["alice@custom.test"],
        kind: .iCloud,
        connection: missing,
    )
    #expect(MailProvider(account: cloud) == .iCloud)
    #expect(MailProvider.iCloud.suggestedConnection(for: cloud).host == "imap.mail.me.com")
    let custom = ConnectionSettings(host: "custom.example.test", port: 143, username: "alice", security: .startTLS)
    let other = MailAccount(id: "o", name: "Custom", addresses: ["alice@gmail.com"], kind: .imap, connection: custom)
    #expect(MailProvider(account: other) == .other)
    #expect(MailProvider.other.suggestedConnection(for: other) == custom)
    #expect(MailProvider.isGoogleHost("imap.gmail.com.example.test") == false)
}

@Test
func `iCloud suggestions replace numeric Mail identifiers with a mail address`() {
    let cloud = MailAccount(
        id: "icloud",
        name: "iCloud",
        addresses: ["alias@custom.test", "primary@icloud.com"],
        kind: .iCloud,
        connection: ConnectionSettings(host: "p01-imap.mail.me.com", port: 993, username: "123456789", security: .tls),
    )
    let suggested = MailProvider.iCloud.suggestedConnection(for: cloud)
    #expect(suggested.username == "primary@icloud.com")
    #expect(suggested.host == "imap.mail.me.com")
}

@Test
func `google app password link encodes an account hint`() throws {
    let url = MailProvider.googleAppPasswordURL(email: "alice+mail@gmail.com")
    let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(parts.host == "myaccount.google.com")
    #expect(parts.queryItems == [URLQueryItem(name: "authuser", value: "alice+mail@gmail.com")])
}

@Test
func `iCloud defaults use the public TLS endpoint regardless of imported transport`() {
    let cloud = MailAccount(
        id: "icloud",
        name: "Custom display address",
        addresses: ["alias@custom.test", "primary@me.com"],
        kind: .iCloud,
        connection: ConnectionSettings(
            host: "p01-imap.mail.me.com",
            port: 143,
            username: "123456789",
            security: .startTLS,
        ),
    )
    #expect(MailProvider.iCloud.suggestedConnection(for: cloud) == ConnectionSettings(
        host: "imap.mail.me.com",
        port: 993,
        username: "primary@me.com",
        security: .tls,
    ))
}
