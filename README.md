# ✉️ MailSearch

MailSearch is a native macOS menu bar app for searching email directly
on IMAP servers. It discovers accounts from Mail.app, shows results from
each server as they arrive and lets you preview, flag and unflag messages.

![MailSearch showing email search results in its menu bar panel](docs/screenshot.png)

## 💡 Motivation

Find mail across accounts and folders without waiting for a local index
or keeping another email client open.

## ✨ Features

- Discover Mail.app accounts and store verified IMAP credentials in Keychain.
- Search across accounts and server folders, including archived and sent
  mail, with results arriving newest first and progress for each account.
- Preview message text without marking mail as read or loading remote content.
- Find flagged mail and flag or unflag individual messages, synchronising
  through the server with Mail.
- Use a native Liquid Glass menu bar panel with keyboard controls and VoiceOver.

## 🚫 Out of Scope

- Composition, attachments, rich HTML, moving or deleting mail or opening
  messages in Mail. Only explicit flagging and unflagging change messages.
- Local folders, POP or Exchange without IMAP, background indexing and polling.
- Reusing Mail's credentials or OAuth. Accounts need separate IMAP credentials.

## 📋 Requirements

- macOS Tahoe (26) or later. CI builds target Apple silicon.
- IMAP accounts configured in Mail.app, permitting implicit TLS
  (normally port 993). STARTTLS is not supported.
- Automation permission to discover accounts from Mail.app.
- To build: Xcode 27.2 with Swift 6.4 and [Homebrew](https://brew.sh).

## 📦 Installation

Build from source:

```sh
script/bootstrap
script/build
open MailSearch.app
```

Use `script/install` to build, install to /Applications and launch the app.
No public binary release or Homebrew cask is available yet.

The app uses App Sandbox and Hardened Runtime. Local builds are signed
ad hoc unless `MAILSEARCH_SIGNING_IDENTITY` names a signing certificate.
Use a consistent identity to avoid fresh Keychain authorisation; see
[authentication](AUTHENTICATION.md#keychain-access-and-rebuilds).

## ⚙️ Configuration

Open MailSearch from the menu bar, allow Automation access to Mail when
prompted and connect accounts in **Settings → Accounts**. Gmail needs an
app password; iCloud needs an app-specific password and primary Mail address.
See [authentication setup and troubleshooting](AUTHENTICATION.md).

Enter a plain phrase such as `project update` and press Return or Search;
do not add quotes or Gmail operators. Click a result or press Return or
Space to preview it. See [search behaviour](SEARCH.md) for matching,
controls, caching and limits.

## 🛠️ Development

- `script/test`: unit, native view and loopback IMAP integration tests
- `script/style [--fix]`: Swift, shell, workflow and README checks
- `script/analyze`: dependency boundaries, SwiftLint analysis and Periphery

Builds default to Release; use `XCODE_CONFIGURATION=Debug` for debugging.
Tests use synthetic data and never access real mail or credentials.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development conventions,
[ARCHITECTURE.md](ARCHITECTURE.md) for the design and
[RELEASING.md](RELEASING.md) for CI and distribution setup.

## 🚧 Status

Early development, primarily for Mike McQuaid's workflow. Behaviour and
interfaces may change. iCloud authentication and searches have been checked
manually; wider provider coverage, flag propagation and live previews still
need the checks in [HOST-CHECKS.md](HOST-CHECKS.md).

## 📮 Contact

[Mike McQuaid](mailto:mike@mikemcquaid.com). Report vulnerabilities privately
as described in [SECURITY.md](SECURITY.md).

## 📄 Licence

Copyright © 2026 Mike McQuaid. Licensed under [AGPLv3](LICENSE).
Third-party dependencies retain their own licences; see
[THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt).
