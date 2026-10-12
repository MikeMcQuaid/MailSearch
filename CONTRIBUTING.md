# Contributing to MailSearch

Read [README.md](README.md), [ARCHITECTURE.md](ARCHITECTURE.md) and
[AGENTS.md](AGENTS.md) first. Keep changes small and focused on searching,
previewing and flagging server mail. Discuss larger changes before coding.

Install Xcode 27 and Homebrew, then run:

```sh
script/bootstrap
script/style --fix
script/test
ASAN_OPTIONS=halt_on_error=1 script/test --sanitize address --configuration release \
  --scratch-path .build/address-sanitizer
TSAN_OPTIONS=halt_on_error=1 script/test --sanitize thread \
  --scratch-path .build/thread-sanitizer
script/build
script/analyze
```

Style enables all rules. Prefer configuring agreement between the tools to
disabling a rule. Document unavoidable conflicts in the configuration and keep
domain exceptions scoped to the relevant declaration. Do not add baselines.
`script/analyze` needs a complete fresh build; missing tools, failed builds and
skipped SwiftLint files are failures. Logs are saved as `.build/analyze-*.log`.
Both analyser passes run independently after a successful build. SwiftLint must
report completion for every application and test source file. The analysis build
runs Xcode 27's Testing macros in its external plugin server to avoid a SourceKit
crash. Keep this compiler setting in the build itself so the log remains faithful
to the compilation. Macro failures must still fail the check.

Address Sanitizer retains Release because pinned SwiftSoup exhausts a concurrency
worker's stack under Debug instrumentation. See [vendor/README.md](vendor/README.md).
Thread Sanitizer and normal tests use Debug. All sanitizer failures block CI.

Add a failing regression test before fixing a bug. Use injected fakes or
the loopback IMAP fixtures. Automated checks must never access real mail
or Keychain credentials. Keep GUI checks in [HOST-CHECKS.md](HOST-CHECKS.md).

Describe the problem, resulting behaviour and validation in pull requests.
Issue reports should include the app and macOS versions, the provider and
redacted error details. Never include credentials, authentication traces,
real message bodies or identifying headers. See [SECURITY.md](SECURITY.md)
for private vulnerability reports.

Dependencies are locked in `Package.resolved`, except SwiftMail, whose
version and exact revision are in `vendor/SwiftMail/upstream.json`.
Run `script/prepare` before invoking SwiftPM or opening the package in Xcode.
For SwiftMail updates, review its local manifest and Network.framework patch
in `vendor/SwiftMail`, the three extensions in `script/support` and the
protocol/TLS fixtures. Dependabot does not update this separate upstream pin.
Do not remove revision checks to make an update pass. SwiftNIO IMAP has a
pinned patch for empty authentication-challenge encoding; retain its sanitizer coverage
when updating or removing the patch. After dependency updates, run
`script/prepare`, `python3 script/licences.py --write` and all checks.
Review upstream licence changes and any vendored components too.

Contributions are accepted under the project's licence. Keep third-party
copyright and licence notices intact.
