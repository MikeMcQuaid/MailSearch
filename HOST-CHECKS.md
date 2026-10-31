# Host acceptance checks

These checks are manual and require the account owner’s GUI session.
Automated tests never read real Mail accounts, mail or Keychain items.
Build 10 removes all message-opening integration with Mail.app. Earlier opening
checks below are historical and no longer apply; Mail automation is discovery-only.

## Native project migration (31 October 2026)

- Xcode 27.2 (27B52), Swift 6.4 and macOS 27.2 on arm64. Xcode's converter
  produced the tracked `project.xcproj`; the shared scheme names the actual
  `MailSearch.app` product. All Debug and Release build settings, target identity
  and package dependencies were compared with the original project.
- Unsigned Debug builds and the source membership checks passed. Temporary
  sources were added, renamed and removed in all seven app, library and test
  modules without project or scheme edits. Identically named declarations
  verified target isolation. Resource discovery and recursive exclusions passed.
  Excluding `Icons` alone initially compiled an invalid nested Swift probe and
  copied its text resource; marking that directory opaque fixed both failures.
- The ad hoc signed Release build and ZIP passed signature verification, with
  App Sandbox and Hardened Runtime retained. The arm64 bundle contains the icon,
  asset catalogue, licence, notices and SwiftNIO's privacy resource bundle,
  without source configuration files or excluded descendants. The dependency
  bundle's generated `Info.plist` is retained. Package libraries are linked
  statically; there are no embedded frameworks or extensions. Git-derived version
  `0.1.1 (23)` was preserved.
- An unsigned Release `xcodebuild archive` produced a recognised application
  archive with matching app, executable and dSYM names. This does not validate
  Developer ID signing, notarisation or Gatekeeper distribution acceptance.
- All 76 tests passed normally, with Address Sanitizer in Release and with
  Thread Sanitizer in Debug, alongside the shell regression checks. Style fixes
  and checks passed. SwiftLint analysed all 45 application and test source files
  with no findings, and Periphery reported no unused code from the fresh index.
  Periphery 3.8.0 uses its supported Swift package manifest integration, avoiding
  any need to parse the JSON project or retain a legacy project. The existing
  native SwiftPM index build engine remains deprecated but available in this
  toolchain. Hosted workflow execution is still required to validate the runner.
- Bootstrap passed with all eight dependencies installed using
  `HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_FROM_API=1`. The normal Homebrew
  API refresh could not acquire its host-owned download lock inside Sandvault;
  no repository workaround or permission changes were needed.
- In the owner's GUI session, open the tracked project and run the shared scheme.
  Check the menu bar icon, Settings → About icon and displayed version, then
  confirm the archive appears correctly in Xcode's organiser. These GUI checks
  have not been performed as part of this migration.
- Hosted CI and the manual signed Release workflow still need a run, including
  startup on macOS 26 and 27. No app was launched or real mail accessed during
  this migration's automated validation.

## Direct Xcode dependencies (31 October 2026)

- Reproduced the review finding: Xcode's default checkout lacked the SwiftNIO
  continuation patch after preparing only `.build`. Default preparation now asks
  Xcode for its actual location and patches that checkout and `.build` from the
  same pins and lockfile.
- An unsigned Debug build passed without Derived Data or checkout-location
  overrides. Both SwiftNIO revisions and patches matched before and after that
  build. The regression checks reject an unexpected Xcode checkout revision and
  retain preparation of isolated analysis and sanitizer directories.
- The first location check was masked by this sandbox's global `.DerivedData`
  preference. CI used its standard `~/Library/Developer/Xcode/DerivedData` path.
  A fresh fixture also ignored a different shared location, so the ineffective
  shared settings file was removed. Regression fixtures cover standard unique
  paths, custom paths containing spaces and failed Xcode settings queries.
  Workspace state and the generated lockfile remain ignored.
- All three workflow caches require exact keys containing `script/prepare` and
  `script/support/*.patch`. Mutation checks verify that editing preparation,
  editing either patch or adding a patch changes the key. The shared namespace
  also requires this policy in analysis, which must not resave stale checkouts
  under a newer key after a broad restore.
- All 76 tests, the source membership checks, style, the ad hoc Release build
  and both analysers passed. GUI interaction and signed release checks remain
  subject to the owner checks above.

## Flat icon (18 October 2026)

- Option A replaces the glass artwork with a flat white envelope and amber
  search lens on teal. The compiled ICNS preview was inspected for shape,
  spacing and transparent cut-outs.
- Check the rebuilt app in Finder and Settings → About in light, dark and
  tinted appearances. Confirm the fold and lens centre show the tile colour.
- The menu-bar template uses the same envelope and lens in monochrome, with a
  transparent separation around the lens. Its compiled template flag and
  20 × 18-point size were verified, and light/dark previews were inspected.
  Check it on light and dark menu bars, including while the panel is open,
  and confirm VoiceOver announces MailSearch.

## Recorded in development

- Xcode 27.0 (27A5228h), Swift 6.4, arm64, macOS 27 SDK.
- Read Mail’s installed public scripting dictionary. Account passwords
  are explicitly write-only; RFC Message-ID differs from Mail’s local id.
- Mail registers the `message:` URL scheme. Resolution of real messages
  through that scheme is not assumed or used.
- Account discovery from Sandvault returned privilege error −10004.
  No account names, types, messages or credentials were obtained.
- The signed bundle launches through `open MailSearch.app` into the host
  user’s session and remains running. Discovery now runs once when the
  menu bar panel or Settings first opens and on explicit refresh, without connecting to IMAP.
  Direct binary execution inside Sandvault terminated with
  SIGTRAP; sandbox restrictions also deny access to its crash diagnostics.
  The normal LaunchServices path succeeded; visual checks remain manual.
- The host user reported the generic connection-settings error for every
  account. Synthetic account records reproduced an AppleScript `kind`
  assignment error (−10006). Renaming that variable and reading properties
  separately passes complete and missing-port regressions. Host discovery
  needs a fresh check with the rebuilt app.
- Static discovery and opening scripts compile against Mail’s dictionary.
- Loopback fixtures exercise plain IMAP and ESEARCH, metadata batches,
  result limits, missing messages, authentication failure, disconnects,
  read-only refusal, required STARTTLS, namespace name preservation,
  cancellation between batches and an actual metadata-command timeout.
- Gmail fixtures verify capability-gated X-GM-RAW phrase wrapping, Unicode
  queries, the maximum query size, combined FLAGGED searches, rejected commands and
  standard TEXT fallback when the capability is absent or input has quotes or
  backslashes. These are protocol checks,
  not evidence of successful authentication to a real Google account.
- Flag fixtures verify FLAGGED searches with and without text, existing
  flags, single-UID additive and subtractive STORE, unchanged read/unread and answered
  flags, changed UIDVALIDITY, vanished messages, read-only mailboxes,
  missing permanent-flag support, rejected writes, lost replies and Gmail
  removing an unflagged message from Starred before the confirmation fetch.
  Model tests cover the original search connection, failed/late flag
  completion, retained flags after search cancellation and stable selection. No fixture changes real mail.
- Preview fixtures cover plain text, base64, inert HTML conversion,
  attachment exclusion, the 32 KiB limit, stale identities and non-marking
  BODY.PEEK commands. Model fakes verify cancellation and stale responses.
- The signed app’s entitlements retain App Sandbox, outgoing network
  access and the Mail-only Apple-event exception. No sandbox bypass is
  used to make Mail automation work.
- A host screenshot showed Keychain asking for the login keychain password
  for `com.mikemcquaid.MailSearch.imap` after a rebuild. Inspection confirmed
  the ad hoc build's designated requirement was a code hash. Account refresh
  unnecessarily read every stored password; a failing model regression now
  passes with metadata-only queries. Injected Security calls verify that those
  queries request no secret data and skip authentication UI. Tests do not use
  the real keychain. No valid code-signing identity is visible in Sandvault.
- A subsequent report described repeated prompts and no results after Allow.
  A failing model regression reproduced cancellation when the menu bar panel
  disappeared. Panel disappearance now cancels only the preview; searches and
  flag writes finish. Injected Keychain tests verify one read per credential,
  remembered denials, explicit account-scoped retries and cache invalidation
  after successful saves or removals. Real Keychain authorisation still needs
  the host GUI check below.
- Generated a new transparent envelope and gold search-lens asset with imagegen,
  compiled its Icon Composer bundle and inspected the resulting ICNS image.
  About explicitly loads that resource. Build 2 identified the icon and
  prompt-loop fix. Build 3 uses a native template envelope in the menu bar,
  a 420-point panel and a clearly labelled IMAP login in Settings.
- Failing regressions reproduced incorrect imported iCloud transport defaults
  and pasted whitespace in iCloud credentials. They pass with TLS port 993
  defaults and whitespace trimming. No real iCloud login was attempted.
- Model tests pin each search diagnostic to its submitted login, so editing
  Settings cannot pair a new username with an old authentication failure.
- Build 4 removes the Copy Details button and routine protocol/container notices;
  diagnostics remain selectable with standard copy shortcuts. Plain phrases use
  standard TEXT elsewhere and automatic Gmail phrase quoting.
- A credentials-free manual TLS check of imap.mail.me.com confirmed certificate
  verification, TLS 1.3, AUTH=PLAIN and SASL-IR. No account or mail was accessed.
  Authentication fixtures cover PLAIN with and without SASL-IR, disabled LOGIN
  and rejected credentials without mechanism retries. The documented curl
  diagnostic is also tested against the loopback fixture, including its exact
  read-only command sequence. It never uses real credentials in tests.
- On 6 October 2026 the user confirmed real iCloud curl authentication with
  AUTH=PLAIN, the short username and EXAMINE INBOX after correcting trailing
  whitespace in the app-specific password. The server advertised persistent
  `\Flagged` support. This verifies the user's independent connection, not
  MailSearch search, preview, flag propagation or exact-message opening.
- Build 5 replaces per-account Keychain items with one protected password
  dictionary. A failing cross-account regression reproduced multiple reads and
  repeated denials. Injected Security tests now cover one shared read, global
  denial/retry, metadata-only discovery, edits preserving other accounts,
  persistence across adapter instances and corrupt-storage failures. No real
  Keychain is accessed. Existing passwords must be re-entered once; old items
  are not read or deleted. Real system prompt counts remain a GUI check.
- A later host curl response confirmed iCloud sends `[READ-WRITE]` for EXAMINE.
  Build 6 handles this only for recognised iCloud hosts. Regressions reproduced
  the rejected text search, Flagged search and preview, then passed with the
  exception. Fixtures still reject other read-write servers and missing UID
  metadata and verify no SELECT or mutation command occurs on read paths.
- Build 6 adds Verify Connection without saving or mailbox access, removes the
  Advanced disclosure and simplifies provider wording. Loopback tests cover
  authentication success/failure and cancellation; model tests cover unchanged
  saved settings, password normalisation and same-server credential reuse.
- A native view regression failed to find selectable text in the old details
  view. It passes with a non-editable NSTextView and verifies selection survives
  an unchanged update. Actual dragging and ⌘C in the menu bar remain GUI checks.
  Previews expand inside the selected row, with no split pane or repeated header.

## First launch

1. Run `script/install` as your normal user, including with an older build
   already running. Confirm it quits that build and launches only the newly
   installed /Applications/MailSearch.app. Click its envelope, then Settings.
   The app no longer shows a Dock icon or opens a main window at launch.
2. Allow the Automation prompt during initial discovery. If denied, enable
   MailSearch → Mail under System Settings → Privacy & Security →
   Automation, then refresh again. Mail may launch for discovery.
3. Compare the names and addresses with Mail’s settings. Confirm POP,
   Exchange/unknown and disabled accounts have explanations. An account
   Mail’s public interface does not expose cannot be discovered here.
4. If a field is unavailable, check the named field and numeric error in
   the account row. Available fields and IMAP type should be retained.
   In Settings, choose Connect for each available IMAP account. Recognised Gmail and
   iCloud accounts fill missing connection settings and link to their
   password-creation pages. These providers fix the server, port and TLS mode;
   other providers retain editable fields. Save must verify before storing.
   Check a deliberately wrong draft password: the sheet stays open with an error
   and the existing settings and password remain unchanged. Cancel during a test
   must also leave them unchanged. Confirm long iCloud guidance wraps fully.
   Change a field or dismiss the sheet during verification: stale success must
   not appear, and a second test cannot overlap the cancelled request's cleanup.
   Saving remains separate from verification.
5. Verify credentials appear only in Keychain under service
   `com.mikemcquaid.MailSearch.credentials` in one MailSearch Saved Passwords item.
   If upgrading from builds 1–4, enter each app password once again; the old
   `com.mikemcquaid.MailSearch.imap` items remain untouched. Quit and relaunch to check settings
   persist but search text and results do not.
6. Check the icon in Finder, including dark and tinted appearances.
   Check the menu bar panel, search controls, Settings and Connect sheet
   with VoiceOver, Full Keyboard Access and Reduce Transparency enabled.
7. In Settings → About, check the running app icon, version and build number.
   Switching between Accounts and About must not request saved passwords.
   Opening Settings must hide the search panel. Verify the menu bar envelope
   in light and dark appearances and the narrower result rows at 420 points.
   Drag to select account details, then use ⌘C. Check ⌘A in that text view too.
   There is no Copy Details button or ‘see account details’ suffix.
   Use Copy Message Details from a result’s context menu.
8. If a previous build needs Keychain authorisation, test from the host
   session. Allow must let the search finish after the panel disappears;
   reopen it to see results. Deny must produce a Keychain-specific explanation
   and not prompt again for any account on resubmission. Quit and reopen or save
   credentials in Settings to retry. There are no unlock or forget buttons. Check a
   search covering multiple saved accounts, then preview and flag one result:
   only the first shared password read may request authorisation. Repeat after
   a changed build. Saving one account must preserve the others.
   Check the Mac login password separately
   if it is rejected; never reset the login keychain as part of this check.
   Use the same `MAILSEARCH_SIGNING_IDENTITY` for two changed builds and verify
   that the second retains access after the first is authorised. This remains
   unverified here and requires the host's signing certificate and GUI session.

## Search and opening

1. Use a distinctive term known to occur in old, archived and sent mail.
   Compare results with those server folders. Junk and trash are included;
   local folders and server `\\Noselect` containers are excluded.
2. Record an unread test message’s state in Mail. Search for it without
   activating it and confirm the state has not changed.
3. Activate that result with Return, double-click and Open in Mail. Check
   that an opening spinner remains visible until the operation completes. Verify Mail
   opens that exact message in that account. Mail may mark it as read.
4. Check a message copied into multiple mailboxes or accounts. The app
   keeps separate locations. A duplicate Message-ID within one Mail
   account is deliberately refused, even when those copies look alike.
5. A message not yet synchronised to Mail must report that it cannot be
   found. Missing or ambiguous Message-IDs must open nothing.
6. Scroll into a long result list, select a row and allow further batches
   to arrive. Rows must re-sort newest first and selection must retain its identity. Test arrow
   keys, Return, double-click, context menu and VoiceOver.
7. Submit a different search while one runs, then cancel. Old results
   must never appear in the new search. An active command can take up to
   60 seconds to drain; the stopping indicator remains visible meanwhile.
8. Disconnect one account or use an invalid password. Other accounts’
   results must remain available, and the summary must say incomplete.
9. Leave the finished app idle. It should make no network requests.
   Dismissing the panel cancels only the preview. Previously submitted searches
   and flag writes finish without starting new operations; Stop cancels search.
   The app does not register a login item or leave a background service.
10. Enter the same plain phrase on Gmail and iCloud, with no extra quoting.
    Gmail receives a quoted phrase through X-GM-RAW; iCloud uses standard TEXT.
    Compare provider matching without assuming identical indexes or punctuation
    handling. Quotes, backslashes and operator-looking input remain text.

## Flags and stars

1. Search for a message already flagged/starred on your server. Check its
   filled flag indicator against Mail. Click Flagged with an old search term
   present: it must clear the term and submit immediately. Gmail uses its Starred
   folder when advertised, otherwise all selectable folders. Repeat
   with text to narrow the search. Neither action should change flags.
2. Select an unflagged test message and choose Flag, its context-menu
   action or ⇧⌘L. Confirm the success notice appears and the row becomes
   flagged without opening Mail or moving the selection.
3. Choose Unflag and verify the inverse operation. The row stays selected
   until the next search. Let Mail synchronise normally and confirm it
   displays the final flag state. Check
   the message remains unread if it was unread before. Flag colours and
   provider-specific star variants are not assigned by MailSearch.
4. Submit again to refresh flag status after changing a flag elsewhere.
   There is no polling or automatic Mail refresh. Other copies/locations
   are not marked locally based on a shared Message-ID.
5. A server must explicitly advertise persistent `\Flagged` support.
   SwiftMail does not distinguish an omitted PERMANENTFLAGS response from
   an empty one, so both are conservatively refused for writes.

## Preview and account corrections

1. Select a message. Its text must expand directly beneath that row's existing
   information, without a repeated header or separate resizable pane. Other
   rows remain in the same results list. Check long text, scrolling and text
   selection. Displayed Gmail folders omit their namespace prefix; server paths
   and copied message details retain it. Previewing must not open Mail or
   change its read/unread state. Select rapidly between rows and dismiss
   the panel: old text must never appear under another message's heading.
2. Check a plain-text message, an HTML-only message, an attachment and a
   long message. No remote image, script or attachment should load. Long
   previews show a limit notice. Main viewing remains in Mail.
3. For Gmail, the app-password link should request the displayed account;
   confirm the browser's account selector, which can override the hint.
4. The user reported an iCloud alias/custom-domain username and an otherwise
   correct app password. Correct the username to the primary iCloud address
   in Settings, leave the password blank on the same server and save. Retry
   a search. Try the part before @ if the full address is rejected. This
   remains a host check; no real credentials were accessed during tests.
   Check the accounts list’s IMAP login after saving, independently of the
   account label. Gmail/iCloud must not offer editable server, port or encryption fields.
5. If iCloud still rejects the login, run the read-only curl commands in
   AUTHENTICATION.md from your normal Terminal session. Compare the short
   username, full primary address, AUTHENTICATE PLAIN and LOGIN. Enter the
   app-specific password only at curl's hidden prompt. Never enable verbose or trace
   output, including through a filter. Report which combination
   succeeds or the error number, never the password.

## Provider status and authentication

The user verified iCloud password authentication and read-only mailbox access
independently with curl, then confirmed iCloud Flagged results and a known text
match in MailSearch. Flag propagation and exact-message opening still need the
host checks above. POP and non-IMAP accounts are unsupported.
OAuth is not implemented or represented as connected. Mail cannot export
its OAuth tokens to this app.

The requested setup uses app-specific passwords, without asking the user
to register an OAuth application. See AUTHENTICATION.md for provider steps.
If a provider or organisation disallows app passwords, this build cannot
authenticate that account. Neither Mail nor Internet Accounts provides a
supported credential-sharing API for these accounts. Never share a password,
access token or refresh token in chat.

## Build 7 interaction checks

- Switch accounts while a search runs. Deselected rows disappear immediately;
  other accounts continue without restarting. Re-enable an account and confirm
  the last submitted query is used, even if the text field has unsent edits.
- Repeat a completed search. Cached results appear while refreshing and are
  labelled until replaced. A fresh empty result must remove old cached rows.
  Reopen the app and confirm no mail cache survives the launch.
- Click a row twice with a pause to expand then collapse it. Space toggles the
  keyboard-selected row; double-click and Return still open exactly that message.
- Check the All Mail/Flagged glass controls in light/dark mode and with Reduce
  Transparency, increased contrast and VoiceOver. The active choice must be clear.
- The user confirmed the reported missing phrase match was present at the bottom
  of arrival-ordered results. Build 7 fixes global ordering without changing the
  phrase query. No real message source or credentials were saved into fixtures.

## Build 8 panel checks

- Build 8 was signed, verified and launched. Formatting, all 69 automated tests
  and static analysis pass. Tests use synthetic data and loopback servers.
- Confirm the title/icon header and bottom narrowing hint are gone. Search
  placeholders distinguish All Mail from narrowing Flagged results. Settings is
  bottom left and Quit is bottom right with MinMaxCal's exit symbol.
- Confirm tighter padding still leaves readable text and accessible controls.
  Only flagged result rows should show a flag indicator.
- Single-click an unselected row once, then click it again to collapse. Repeat
  between different rows and while metadata arrives. Double-click and Return
  must still open the exact message in Mail. Arrow keys select; Space previews.
- Preview event-order regressions fail with selection-triggered loading and pass
  when selection only dismisses a different preview. Actual pointer event
  delivery in the host menu bar remains a GUI check.
- Fixtures confirm iCloud Archive and Gmail All Mail are visited last, including
  localised special-use folders and standard-name fallbacks. Other providers and
  unrelated nested Archive folders retain their order. No folders are omitted.

## Build 9 preview and Mail access checks

- Build 9 passes formatting, all 72 tests, the signed release build and static
  analysis. The previous app instance exited and the new bundle launched.
- The user reported the failure while opening a result and found Mail needed
  force-quitting. A timeout is plausible; the old diagnostic discarded its code,
  so the original cause cannot be established from that message.
- Select an arriving result while a search is still running and use Preview in
  the toolbar or Space. Text must appear without waiting for search completion.
  Confirm the row-click gesture works too; repeat while other results arrive.
- Reproduce the reported Mail access failure and record only the displayed
  numeric error code. The old build labelled every scripting error as a missing
  Automation permission, so that message did not establish the cause.
  Real Mail opening still requires this GUI check. No permissions were reset.
- Synthetic regressions cover permission, timeout, privilege, unavailable-Mail
  and unknown errors, retaining codes through discovery and opening while
  excluding raw script diagnostics. Previews work with two active searches and
  remain available after opening fails.
- Settings → Accounts must identify the accounts as discovered from Mail.app
  and explain the separate credentials used for server searches.


## Build 10 previews during searches

- All 71 automated tests pass, including native preview layout and a real IMAP
  adapter preview while a separate loopback search connection remains busy.
  Formatting, release build and static analysis pass; Build 10 is launched.
- Open in Mail, its keyboard shortcuts, context-menu command, adapter and
  mailbox/message AppleScript lookup are removed. Return and Space toggle
  previews. Selecting results must never contact Mail.app.
- A native layout regression reproduced the loaded preview leaving the visible
  area when 100 newer results arrived. Result rows now use native buttons and a
  SwiftUI scroll position tied to message identity. Test while loading and after
  text appears, scroll manually and move between results with arrow keys.
  Repeat with System Settings → Appearance → Show scroll bars set to Always;
  a synthetic regression covers the resulting preview width change.
- Search both accounts and expand a result immediately. Its loading indicator
  or text should appear while the search continues. Click again to collapse.
  Confirm text stays selectable and Copy Message Details and flag actions still
  target the clicked message.

## System TLS transport (7 October 2026)

SwiftMail now uses Network.framework through SwiftNIO Transport Services,
with no SwiftNIO SSL or BoringSSL dependency. Automated loopback fixtures
cover certificate trust, hostname and expiry validation, connection deadlines,
cancellation and Gmail/iCloud protocol behaviour over TLS. Fixture roots are
connection-scoped and never installed in Keychain. Previous live-provider
checks predate this transport change. A manual, unauthenticated
Network.framework probe completed system-verified TLS handshakes with both
`imap.gmail.com:993` and `imap.mail.me.com:993`. It sent no credentials
or IMAP commands. All 74 tests pass, including Address and Thread Sanitizer
runs. Style, dependency boundaries, static analysis and the sandboxed release
build pass. A clean source copy prepares the pinned dependency successfully;
the executable links Network.framework and Security.framework and contains
no NIOSSL or BoringSSL symbols.

Still needs the host user's GUI session and saved credentials: submit a Gmail
and iCloud search, expand a preview during the search and verify an explicit
flag/unflag. Confirm both providers connect with their existing TLS port 993
settings. No real mail or credentials were accessed by automated checks.

## Policy alignment checks (12 October 2026)

- Style, shell regressions, all 76 normal tests and the sandboxed Release app
  build pass. The app retains App Sandbox. No real mail or credentials were used.
- One repeated normal run exited during the existing packaging shell checks,
  after the build-script fixtures and before Swift tests, without a diagnostic.
  The final complete normal run and all six sanitizer invocations passed those
  checks. The cause of that intermittent shell failure remains unidentified.
- All 76 tests pass with Release Address Sanitizer and Debug Thread Sanitizer,
  using separate scratch directories and `halt_on_error=1`. Logs and per-target
  JUnit reports are in `.build/asan-*` and `.build/tsan-*`.
- Debug Address Sanitizer still fails in SwiftSoup’s HTML parser on the small
  synthetic preview fixture. LLDB confirms stack exhaustion; the existing
  Release exception and recheck procedure are documented in `vendor/README.md`.
- A fresh native analysis build compiles all 45 source files across the seven
  application and test targets. The exported package description and compiler
  log agree, and Periphery reports no unused code from the fresh index.
- Initial SwiftLint analysis failed with Xcode 27 macro-plugin malformed responses
  and a SourceKit crash. `script/analyze` returned failure and still ran Periphery.
  The follow-up below fixes the macro invocation without skipping analysis.
- Live account interaction, VoiceOver and the menu bar remain host GUI checks.
  This policy change did not access accounts or launch the app.

## Analysis macro fix (12 October 2026)

- LLDB reproduced the crash in `libSwiftInProcPluginServer` while expanding
  Testing macros. Loading the same macros through Xcode's external plugin server
  fixes it; an explicit frontend flag avoids nested macro sandboxes in Sandvault.
  Both settings are recorded by the real build, without rewriting its log.
- Regression tests fail without these compiler settings and pass with them on
  mocked host and sandbox paths. No rules, files or tests were excluded.
- Fresh sandbox `script/analyze` passes: SwiftLint reports zero violations across
  all 45 app and test files, and Periphery reports no unused code. The exported
  package description matches the compiler log for all seven targets; the fresh
  index contains 1,122 units. Three unused imports exposed by analysis were removed.
- Style, the Release app build and all 76 normal tests pass. All 76 tests also
  pass with Release Address Sanitizer and Debug Thread Sanitizer, with separate
  scratch directories, `halt_on_error=1` and three clean JUnit reports per run.
- Host/CI execution of this fix remains to be checked; sandbox analysis no longer
  has an unresolved macro failure. Recheck the external plugin setting after
  upgrading Xcode.
