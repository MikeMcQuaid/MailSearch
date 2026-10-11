#!/usr/bin/python3
"""Check the small set of dependencies and APIs that define this app."""
import json
import re
from pathlib import Path

assert not any(pin['identity'] == 'swift-nio-ssl' for pin in json.loads(Path('Package.resolved').read_text())['pins']), \
    'The app must use system TLS, without SwiftNIO SSL or BoringSSL.'

for path in Path("Sources").rglob("*.swift"):
    source = path.read_text()
    imports = set(re.findall(r"^import (\w+)", source, re.M))
    if "MailSearchDomain" in path.parts:
        assert imports <= {"Foundation"}, f"Domain dependency: {path}"
        assert not re.search(r"\b(URLSession|FileManager|UserDefaults|Process)\b", source), path
    if "MailSearchFeatures" in path.parts:
        assert imports <= {"Foundation", "SwiftUI", "Observation", "MailSearchDomain"}, path
    assert "@unchecked Sendable" not in source, path
    assert not re.search(r"\b(print|debugPrint|NSLog|Logger)\s*\(", source), path

adapter = Path("Sources/MailSearchData/SwiftMailSearchClient.swift").read_text()
allowed = {"connect", "loginWithPassword", "disconnect", "listMailboxes", "examineMailbox", "extendedSearch", "searchGmail", "fetchMessageInfosBulk"}
assert set(re.findall(r"server\.(\w+)\(", adapter)) <= allowed
assert ".plainText" not in adapter and ".noVerification" not in adapter and ".trustRoots" not in adapter
assert "transportSecurity: .implicitTLS" in adapter
assert "SwiftLogNoOpLogHandler" in adapter
assert "options: [.internalDate, .flags]" in adapter
assert 'headerFields: ["SUBJECT", "FROM", "DATE", "MESSAGE-ID"]' in adapter
flagger = Path("Sources/MailSearchData/SwiftMailMessageFlagger.swift").read_text()
assert set(re.findall(r"server\.(\w+)\(", flagger)) <= {
    "connect", "loginWithPassword", "disconnect", "selectMailbox", "fetchMessageInfosBulk", "storeMessageFlag"
}
assert flagger.count("server.storeMessageFlag(") == 1
flag_command = Path("script/support/IMAPServer+FlagUpdate.swift").read_text()
assert "StoreCommand(identifierSet: UIDSet([uid]), data: .flags([.flagged], flagged ? .add : .remove))" in flag_command
assert "options: .uidFlagsOnly" in flagger
preview = Path("Sources/MailSearchData/SwiftMailMessagePreviewer.swift").read_text()
assert set(re.findall(r"server\.(\w+)\(", preview)) <= {
    "connect", "loginWithPassword", "disconnect", "examineMailbox", "fetchMessageInfosBulk", "fetchPart"
}
assert "offset: bytes.count" in preview and "count: count" in preview
assert "let limit = 32 * 1024" in preview
assert "WKWebView" not in preview and "NSAttributedString" not in preview
verification = Path("Sources/MailSearchData/SwiftMailConnectionVerifier.swift").read_text()
assert set(re.findall(r"server\.(\w+)\(", verification)) <= {"connect", "loginWithPassword", "disconnect"}
assert ".plainText" not in verification and ".noVerification" not in verification
extension = Path("script/support/IMAPServer+GmailSearch.swift").read_text()
assert 'name: "UID SEARCH"' in extension
assert '.literal(ByteBuffer(string: query))' in extension
assert "guard supportsGmailExtensions" in extension
authentication = Path("script/support/IMAPServer+PasswordLogin.swift").read_text()
assert 'capabilities.contains(.authenticate(AuthenticationMechanism("PLAIN")))' in authentication
assert 'capabilities.contains(.loginDisabled)' in authentication
assert 'authenticatePlain(username: username, password: password)' in authentication
print("Dependency, read-only search, explicit flagging and logging boundaries passed.")
