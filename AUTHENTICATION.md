# Connecting accounts

Mail supplies account metadata, not passwords or reusable OAuth tokens.
Apple's deprecated [Accounts framework](https://developer.apple.com/documentation/accounts)
is not a supported bridge to Gmail or iCloud Mail credentials.
MailSearch uses app-specific passwords so you do not need an OAuth app
registration. All connections require implicit TLS 1.2 or later, with system
certificate and hostname verification. Gmail and iCloud use port 993.
STARTTLS is unsupported; older settings must be corrected and verified in
Account Settings before use. Saved passwords are reused from Keychain for
explicit searches, previews and flag changes. There is no background
authentication or polling.

## Keychain access and rebuilds

The initial builds used ad hoc code signing. Each changed executable has a
different designated requirement, so macOS can ask to authorise MailSearch's
existing credentials again. The app also used to read every password during
account refresh, unnecessarily causing prompts before a search. Refresh now
checks metadata only and cannot display a credential-authorisation dialog.

Searches now survive the menu bar panel disappearing when a Keychain prompt
takes focus. Previously that disappearance cancelled the search even after
Allow. Reopen the panel to see progress and results; Stop still cancels explicitly.
All saved passwords now share one protected Keychain item named
**MailSearch Saved Passwords**, under service
`com.mikemcquaid.MailSearch.credentials`. One read unlocks all saved accounts,
reused in memory for searches, previews and flag changes. A denial is remembered
for all accounts instead of prompting once per password. Quit and reopen to retry,
or save credentials in Settings. Saving retries Keychain authorisation explicitly
after verifying the draft login. Successful writes replace only that connection's
cached password; other accounts are retained. Nothing is cached in defaults or files.

**One-time upgrade from builds 1–4:** re-enter each app password in Settings.
The old `com.mikemcquaid.MailSearch.imap` items are left untouched and never read
by build 5. Automatically copying them would require the same separate prompts.
After saving into the shared item, a changed ad hoc build needs at most one
item read during a search session, regardless of account count. macOS controls
the dialogue itself; a locked keychain or an explicit credential edit can also
require authorisation. Stable signing remains the way to retain trust across builds.

The prompt naming MailSearch's saved passwords concerns this app's credentials.
It does not establish that the whole keychain is damaged. If you
cannot authorise it, choose Deny. Do not reset or delete the login keychain.
MailSearch cannot change its password and has no keychain-reset code.
The [login keychain password can differ from the current Mac login password](https://support.apple.com/en-gb/guide/keychain-access/kyca2429/mac);
check that separately in Keychain Access if other apps are affected too.

For stable access across builds, sign consistently with a certificate in the
building user's keychain, such as Apple Development or a local code-signing
certificate created through Keychain Access → Certificate Assistant:

```sh
MAILSEARCH_SIGNING_IDENTITY='your code-signing certificate name' script/build
```

Use the same identity for subsequent builds. Switching from ad hoc signing
still requires one authorisation for existing credentials. No valid signing
identity was available inside the development sandbox; this step needs the
host user's session. No old items are deleted, migrated or made accessible
to arbitrary applications. Do not choose ‘Allow all applications’ as a workaround.

Apple documents how [code identity controls Keychain access](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
and [creating a local signing certificate](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).

## Gmail

Gmail setup assumes two-step verification is enabled and uses a Google app
password, never the regular account password.

1. Open Settings → Accounts and select Connect or Account Settings.
2. Check the full Google account email. The Create App Password link
   includes it as an `authuser` hint; confirm the account shown in the browser.
3. Paste the app password and choose Save. It verifies the login before saving
   anything. Spaces in Google's grouped password are removed.

The hint is best effort, not OAuth or a guarantee that the browser selects an
account. No Google password or token is placed in a URL.

Google may hide app passwords for security-key-only two-step verification,
Advanced Protection or managed account policies. If the option is unavailable,
MailSearch cannot connect using this path. Browser OAuth would require an app
registration owned by the app developer; there is no registration-free OAuth
shortcut and another client's registration must not be reused.

[Google's app-password requirements](https://support.google.com/accounts/answer/185833)
[Google's OAuth app-registration requirements](https://developers.google.com/identity/sign-in/ios/start-integrating)

## iCloud

1. Open [Apple Account](https://account.apple.com).
2. Under Sign-In and Security → App-Specific Passwords, create MailSearch.
3. In Settings → Accounts, enter the primary iCloud Mail address as the IMAP
   username, not a custom-domain address, forwarding alias or numeric Mail id.
   If that fails, try the part before `@`, as Apple's IMAP guidance suggests.
4. Use `imap.mail.me.com`, TLS and port 993. Paste the app-specific password
   from the same Apple Account. Do not use the normal Apple Account password.
   Save verifies this draft first, without accessing mail; rejection prevents saving.

A correct app-specific password can still be rejected when paired with an alias
or the wrong username. The actual IMAP login appears both in the accounts list
and in the editor, separately from the account label and sending addresses.
Explicitly saving a corrected username on the same host, port and TLS mode
can reuse the saved password. Changing the server never copies a password to it.
Leave the password field blank to reuse it for a username correction.
The endpoint is fixed to `imap.mail.me.com`, TLS, port 993. Older custom endpoints
are replaced while retaining your username; credentials for a different endpoint
need entering again. Gmail similarly fixes `imap.gmail.com`, TLS, port 993.
Surrounding whitespace is removed from a pasted iCloud app password, with
the hyphens retained. A failed login prevents both text and Flagged searches.
Recognised numeric Mail identifiers are replaced by an available native iCloud
mail address; if none is exposed, enter the primary address yourself.

Apple offers account authorisation to supported third-party apps, but its
public support page does not provide a general developer integration that
MailSearch can claim to implement. Sign in with Apple alone is not IMAP access.

[Apple's app-specific password instructions](https://support.apple.com/en-gb/102654)
[Apple's third-party authorisation guidance](https://support.apple.com/en-gb/121539)
[Apple's IMAP settings](https://support.apple.com/en-gb/102525)

## Read-only Terminal check

This checks iCloud independently of MailSearch, Mail and Keychain. Replace
`your-icloud-username` with the part before `@` in your primary iCloud Mail address:

```sh
/usr/bin/curl --disable --silent --show-error --no-verbose \
  --connect-timeout 10 --max-time 30 \
  --url 'imaps://imap.mail.me.com/' \
  --user 'your-icloud-username' --login-options 'AUTH=PLAIN' \
  --request 'EXAMINE INBOX'
```

Curl asks for the app-specific password privately. Keep it out of the command
line, shell variables and URLs. Never add `--verbose`, `-v`, tracing or `--insecure`,
even when piping through a filter: IMAP authentication traffic exposes reusable
credentials. Do not redirect stderr away from your terminal; curl needs it for
the private password prompt. Share only the exit status or sanitised error number.
`--disable` ignores personal curl configuration, TLS verifies Apple's certificate
and EXAMINE opens INBOX read-only without fetching messages or changing flags.
The output is mailbox status, not email contents. Exit status 0 means this
authentication and read-only mailbox access succeeded; error 67 means the login
was rejected. This command never reads or changes Keychain.

If it fails, repeat with the full primary `@icloud.com`, `@me.com` or `@mac.com`
address as `--user`. To compare with the older app's LOGIN path, replace
`AUTH=PLAIN` with `AUTH=+LOGIN`. The plus is required: `AUTH=LOGIN` means a
different SASL mechanism. Both commands still use verified TLS. The installed
macOS curl 8.7.1 supports both options. See the [curl manual](https://curl.se/docs/manpage.html).

Apple's usual IMAP setup is the short username, port 993 and an app-specific
password. [Fastmail's iCloud IMAP instructions](https://www.fastmail.help/hc/en-us/articles/360058753594-Import-your-mail)
also recommend that combination. Full primary addresses are another documented
option; a custom-domain sending address need not be the IMAP login.
Changing or resetting the main Apple Account password automatically revokes
all existing app-specific passwords, as [Apple explains](https://support.apple.com/en-gb/102654).

If curl succeeds, use the same username and freshly entered app password in
MailSearch. If both username forms and both methods fail, test a newly generated
app-specific password from the Apple Account that owns this mailbox. MailSearch's
Keychain access cannot resolve a login that also fails outside the app.

The app now prefers advertised AUTHENTICATE PLAIN, including SASL-IR when
available. It only uses LOGIN when PLAIN is unavailable and LOGIN is permitted,
and never retries rejected credentials automatically. Protocol fixtures cover
both paths, including rejection. The manual TLS capability check reached
`imap.mail.me.com` and confirmed AUTH=PLAIN and SASL-IR; it supplied no username
or password and did not access mail. On 6 October 2026, the user independently
confirmed curl AUTH=PLAIN and EXAMINE INBOX with the short username after removing
a trailing space from the app password. The response advertised persistent
`\Flagged` support. MailSearch already trims surrounding iCloud app-password
whitespace when saving; re-save the corrected password in the new shared item.
The user subsequently confirmed Flagged results and a known text match in the app.
Explicit flag changes still require host verification.

The user's later EXAMINE completion reported `[READ-WRITE]` despite requesting
EXAMINE. MailSearch accepts this iCloud-specific response while continuing to
use EXAMINE, SEARCH and BODY.PEEK only for searching and previews. Fixture tests cover plain and Flagged
searches, previews and missing UID metadata with this response.

## Search extensions

Gmail advertises `X-GM-EXT-1`; MailSearch then submits `X-GM-RAW` with the
whole plain-text query wrapped as a phrase. Other accounts use literal TEXT
searches. Input containing double quotes or backslashes uses standard TEXT
on Gmail too. Gmail operators are treated as text. No public iCloud-specific search extension was
found; advertised standard capabilities such as ESEARCH are used when available.

[Google's IMAP extensions](https://developers.google.com/workspace/gmail/imap/imap-extensions)

## Other providers

Use a password or app-specific password where your provider permits IMAP.
Server settings remain editable. OAuth providers without app-password support
are currently unavailable. Automated checks use synthetic accounts and
loopback fixtures only; provider authentication still needs host testing.
