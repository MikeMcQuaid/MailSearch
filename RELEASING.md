# CI and releases

## Repository setup

The workflows are ready for a public GitHub repository with a `main`
default branch. They do not create a repository, push code or configure
GitHub settings by themselves.

Enable Actions and Dependabot, then require the `style`, `tests` and
`analyze` checks in branch protection. All three run on pull requests
and pushes to `main`, including when secrets are unavailable. Actions are
pinned to commit hashes. Dependabot proposes weekly action and Swift updates.

Builds use GitHub's public
[Xcode 27 runner](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
for Swift 6.4. Release startup checks also run on macOS 26. The
`xcode-27` entry in actionlint's configuration recognises that public
preview label; it does not require a self-hosted machine.

CI runs both sanitizers against synthetic tests, checks dependency
boundaries and unused code, compiles the icon and sandboxed bundle and
exercises app archiving. It never receives email credentials.
Style checks include actionlint and offline zizmor workflow analysis.

App builds default to Release. Test, analysis and release jobs cache Swift
package downloads, keyed by the lockfile and SwiftMail pin. Compiled output,
signing material and app data are not cached.

Like MinMaxCal, normal CI signs and notarises when
`DEVELOPER_ID_APPLICATION_CERTIFICATE` is available, then uploads the app ZIP.
That secret stands for the complete set below:
partial configuration fails instead of silently skipping signing.
Fork and Dependabot pull requests use ad hoc signing without secrets.
CI artefacts do not create a GitHub release.

Run sanitizer checks locally with `script/test --sanitize thread` and
`script/test --sanitize address --configuration release`. Address Sanitizer
uses optimisation because SwiftSoup's large HTML state machine overflows
the cooperative executor's stack in an instrumented debug build. Thread
Sanitizer runs in debug mode. Neither run suppresses sanitizer findings.

Every test step retains its console log. Address Sanitizer also runs each
test target separately and retains its xUnit report. On failure, download
the `test-diagnostics` artefact for these logs, reports and any ASan runtime
report. This preserves feature-test failures when later target output hides
them in the Actions log. A failed target still fails CI.

## Signed distribution

Configure these Actions secrets, matching AgentIDE and MinMaxCal:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_APPLICATION_CERTIFICATE` | Base64 `.p12` export of the Developer ID Application certificate and private key |
| `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD` | Password protecting that export |
| `NOTARIZATION_KEY` | Original multiline PEM contents of the App Store Connect API `.p8` key |
| `NOTARIZATION_KEY_ID` | API key identifier |
| `NOTARIZATION_ISSUER_ID` | API issuer identifier |

Set the notarisation key directly from Apple's downloaded file, preserving
its `BEGIN PRIVATE KEY` and `END PRIVATE KEY` lines and real line breaks:

```sh
gh secret set NOTARIZATION_KEY --repo MikeMcQuaid/MailSearch < /path/to/AuthKey_KEYID.p8
```

This reads the key privately from the file. Do not base64-encode this secret,
replace line breaks with literal `\n` or supply the filename as its value.
Only the certificate secret uses base64. `invalidPEMDocument` means the
notarisation key could not be parsed. Packaging validates and normalises its
PEM encoding before accessing Keychain, preserving the key itself. Apple's
parser requires 64-column wrapping, whereas OpenSSL also accepts other
wrapping. A successful OpenSSL check alone does not establish that Apple can
read the original encoding. Packaging never prints the key. After correcting
the secret, rerun the failed GitHub Actions jobs. After changing the workflow
or packaging script, push the change and use the new run: rerunning an older
job uses its original commit.

Never put signing material in the repository. `script/package` disables
shell tracing and uses a temporary private keychain, deleted on exit.
Like the reference apps, it temporarily adds that keychain to the search
list and restores the original list on exit. It does not change the login
keychain's contents or password. Packaging keeps App Sandbox and Hardened
Runtime, notarises with Apple, staples the ticket and verifies Gatekeeper
acceptance before recreating the ZIP.

Like AgentIDE and MinMaxCal, the Release workflow also performs a dry run
on pushes changing release-related files. It creates a local `9999.0.0`
tag, builds, signs, notarises and launches the packaged app on macOS 26
and 27. The app ZIP is uploaded as a workflow artefact;
the tag is never pushed and no release is created.

Human dry runs require all five secrets, so missing or invalid credentials
fail the workflow before a release is needed. Dependabot pushes build and
launch with ad hoc signing, skipping notarisation
because Actions secrets are unavailable.

1. Check that CI passes on `main` and complete the manual checks in
   [HOST-CHECKS.md](HOST-CHECKS.md).
2. Run **Release** from `main` with a bare `MAJOR.MINOR.PATCH` version.
   Leading zeroes, prefixes, suffixes, `0.0.0`, `9999.0.0`, existing tags
   and an already-tagged commit are rejected. The local tag is created
   before building so the app carries that version.
3. After signing, notarisation and successful startup on macOS 26 and 27,
   the workflow pushes the version tag and publishes a full GitHub release
   with generated notes and the app ZIP. There is no draft or further
   confirmation. Missing secrets fail the release.
4. Keep the app ZIP and Git tag available for every distributed version.
   Update the README's installation section when the first release is available.

A successful hosted dry run is needed to verify signing, notarisation and
both runtime checks with the configured secrets; local checks cannot
prove them. Dry runs never publish, while manual releases publish
automatically after those checks pass.

## Archives and licences

`script/build` checks generated dependency notices and bundles them with
the project licence. `script/zip` validates the signature before archiving
the app. Development ZIPs are ad hoc signed and are not notarised releases.

Source is available at each release's Git tag. To rebuild a release,
check out that tag and follow the README's build instructions.
`Package.resolved` and `vendor/SwiftMail/upstream.json` pin dependencies;
the tracked patches and extensions are applied by `script/prepare`.

TLS uses Apple's system frameworks through SwiftNIO Transport Services.
SwiftNIO SSL and BoringSSL are absent from the package graph and app binary.
When updating packages, review their licences and regenerate
`THIRD-PARTY-NOTICES.txt` using `python3 script/licences.py --write`.
