# Vendored dependencies

## SwiftMail

[SwiftMail](https://github.com/Cocoanetics/SwiftMail) supplies IMAP connection
state, command handling and Apple's NIOIMAP parser. Its version and exact
revision are pinned in [upstream.json](SwiftMail/upstream.json).

Run `script/prepare` from the repository root to extract that revision,
apply [network-framework.patch](SwiftMail/network-framework.patch) and copy
the extensions from `script/support` into generated, ignored sources.
Change the patch or extensions, not `SwiftMail/Sources`, which preparation
overwrites. [Package.swift](SwiftMail/Package.swift) replaces the upstream
manifest and excludes SMTP, STARTTLS, Outlook MSG/RTF import and EML export.

The patch changes the transport implementation, not just linker settings:

- Use Apple Network.framework through SwiftNIO Transport Services instead
  of SwiftNIO SSL, with a ten-second connection deadline.
- Require TLS 1.2 or later with certificate trust and hostname validation.
  Synthetic TLS tests can supply connection-scoped trust roots without
  changing Keychain trust or disabling verification.
- Reject STARTTLS. MailSearch requires implicit TLS before reading
  credentials; plaintext connections exist only for loopback fixtures.
- Add Swift 6.4 `SendableMetatype` compatibility and protect command
  completion reads with the handler's existing lock.

Upstream SwiftNIO SSL compiles its own vendored BoringSSL. This package
omits SwiftNIO SSL entirely, so MailSearch bundles neither BoringSSL nor
OpenSSL. macOS supplies and updates the TLS implementation behind its
public Network and Security frameworks.

The extensions add Gmail raw search, password authentication selection and
flag-change confirmation using the existing typed encoders and parsers.
SwiftMail retains its BSD-2-Clause licence, included in generated notices
and app/source archives.

When updating the pin, review the manifest, patch and extensions against
upstream, regenerate notices with `python3 script/licences.py --write`
and run the build, style, analysis and protocol/TLS tests, including both
sanitizers. Upstream transport support could remove this patch; until
then, these source changes need maintenance with every SwiftMail update.

## SwiftNIO

`script/prepare` also applies two small patches to pinned checkouts,
checking their revisions and preserving already-applied patches:

- [nio-checked-continuation.patch](../script/support/nio-checked-continuation.patch)
  uses a checked continuation in `EventLoopFuture.get()`. Swift 6.4 with
  Thread Sanitizer reports a race between unsafe continuation resumption
  and reuse of the task's storage. A regression test reproduces the
  same NIO access stack as CI under repeated concurrent
  success and failure completions. Checked continuations avoid that path
  and add validation that the future resumes its waiter exactly once.
  This adds a small allocation per awaited future; cancellation and
  result propagation are unchanged. No sanitizer reports are suppressed.
- [nio-imap-empty-base64.patch](../script/support/nio-imap-empty-base64.patch)
  returns an empty array directly for empty Base64 input, avoiding writes
  to Swift's shared empty-array storage during SASL challenges.

Review these patches when updating their pins in `Package.resolved` and
update the revision checks in `script/prepare`. Remove a patch when its
upstream dependency or toolchain fixes the reproduced issue. Run the
future-handoff test repeatedly with Thread Sanitizer when changing the
continuation patch, alongside the full protocol and sanitizer suites.
