# Search behaviour

Enter the same plain phrase for every account. `something anything` becomes
IMAP `TEXT "something anything"` on ordinary servers and a quoted Gmail phrase,
`"something anything"`, through `X-GM-RAW` when `X-GM-EXT-1` is advertised.
No manual Gmail quoting or provider-specific query syntax is needed.
For example, enter `Clean Strength Media` without quotes. The whole phrase can
match in any header or the body, even when the displayed subject looks unrelated.
This is case-insensitive server phrase matching, not exact sender-field equality;
there is no separate strict whole-field match mode.
Input containing literal double quotes or backslashes uses standard IMAP TEXT
on every provider rather than guessing Gmail’s escape syntax. Operators such
as `from:` are treated as text, not as commands.
Server indexing, punctuation and word matching differ, so equivalent phrase
intent cannot guarantee identical result sets. There is no implicit date filter.
The Flagged button clears the search field and submits immediately. Gmail uses the advertised Starred folder when available, falling back to all selectable folders. Other providers use IMAP `FLAGGED` across folders.
Subsequent text searches can narrow the flagged view; the search placeholder reflects the active mode.
iCloud Archive and Gmail All Mail are searched last, using special-use attributes
or their standard names when attributes are missing. Other mailbox ordering is retained.
Server matching varies and attachment-content searching is not guaranteed.
Searching and previewing request read-only mailbox access and never change flags. Mail.app is used only for account discovery.
iCloud has been observed returning `[READ-WRITE]` for a successful EXAMINE. For
recognised iCloud hosts only, MailSearch accepts that response;
it still sends only search and non-marking fetch commands. Valid UID metadata
remains mandatory. Other providers must confirm read-only access.
Select a result and choose Flag or Unflag, the context-menu action or ⇧⌘L.
An unflagged row stays in the current results to preserve selection; submit again to refresh the flagged view.
Flagging and unflagging change only the standard server `\Flagged` flag, without marking the message as read.
Mail displays it after its normal synchronisation; colour flags and provider-specific star types are outside this scope.
Flag status is a snapshot: submit again to see changes made elsewhere.
Results retain their account, mailbox, UIDVALIDITY and UID; identical subjects or Message-IDs never merge distinct locations.
Results sort newest first across accounts as batches arrive. Selection and scroll position track message identity, keeping an expanded preview visible when newer results arrive.
Account selection updates the visible results immediately and cancels only deselected accounts.

Recent complete searches are cached for five minutes, up to eight account/query entries
and an approximately 16 MiB metadata budget. Repeating a search shows cached
results while refreshing them from the server. Cached results are labelled until replaced; failures never claim
that cached mail is current. Previews cache up to eight messages for five minutes.
Caches never persist across launches and account edits or flag changes invalidate them.

Searches use at most two accounts concurrently, one request per account and 50 messages per metadata batch.
Each account displays at most 2,000 matches and searches at most 500 selectable mailboxes and 2,000 UID windows; reaching a limit is shown as incomplete.
UID windows contain at most 10,000 possible UIDs and cover the mailbox snapshot without a date window.
Non-selectable hierarchy containers such as `[Gmail]` are skipped; their selectable
children are searched. Names the IMAP library cannot preserve exactly are listed
as exclusions and make results incomplete. Junk and trash are otherwise included.
Displayed folder names omit leading `[Gmail]/` and `[Google Mail]/`; server
requests, message identity and copied message details retain the full path.
A new submission cancels the previous search and discards late results.
An in-flight library command may take up to its timeout (60 seconds for search) to drain before another search of that account starts; other accounts can continue within the two-connection limit.
Cancelled, incomplete, failed, unauthenticated and genuinely empty searches have different states.
One preview and one explicit flag update can run alongside the two search connections.
Dismissing the panel cancels its preview. Submitted searches and flag changes
finish even when a Keychain dialog takes focus; reopen the panel for results.
Use Stop to cancel a search. No new work starts while the panel is hidden.
