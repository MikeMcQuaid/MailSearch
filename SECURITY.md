# Security reports

Report suspected vulnerabilities privately to
[Mike McQuaid](mailto:mike@mikemcquaid.com). Include the affected version,
impact and a reproduction using synthetic accounts or message data.
Do not include passwords, tokens or private email.

The latest source is the supported version; there is no commitment to
backport fixes to older releases or a guaranteed response time.

MailSearch stores credentials in Keychain and keeps message data in
bounded memory caches. Search and preview commands are read-only; only an
explicit flag or unflag action writes to a server. See
[ARCHITECTURE.md](ARCHITECTURE.md) for trust boundaries and
[AUTHENTICATION.md](AUTHENTICATION.md) for safe connection diagnostics.
