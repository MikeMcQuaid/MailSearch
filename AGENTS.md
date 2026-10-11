# MailSearch development

Read README.md and ARCHITECTURE.md before changes. Keep them accurate.
Keep Domain pure. Features depends only on Domain; adapters live in Data.
Use Swift 6 strict concurrency, accessible native controls and UK English.
Keep changes small. Use red-green tests for fixes and regressions.
Run script/style --fix, script/test, script/build and script/analyze.
Never test against real mail or write credentials to logs.
Never add private Mail APIs, database reads or polling.
Only explicit single-result flagging or unflagging may mutate mail;
searches and previews remain read-only.
Keep App Sandbox enabled. Record GUI-only checks in HOST-CHECKS.md.
Keep CI and development scripts aligned with MinMaxCal and AgentIDE.
Copy their shared conventions; ask when the reference repos disagree.
Default app builds to Release, cache dependency downloads in CI and sign
when signing secrets are available, failing on incomplete credentials.

Never use verbose or trace output for authenticated curl diagnostics,
including pipelines that filter it afterwards. Start with --disable
and use --silent --show-error --no-verbose. Real passwords belong only
in curl's hidden interactive prompt, never arguments, URLs, environment
variables or logs.
