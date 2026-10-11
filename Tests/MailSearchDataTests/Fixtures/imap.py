#!/usr/bin/python3
"""Loopback-only IMAP fixture. It never contacts an external server."""
import base64
import json
import re
import socket
import ssl
import sys
import time
from pathlib import Path

mode, transcript_path = sys.argv[1:3]
transcript = []
Path(transcript_path).write_text(json.dumps(transcript))
if len(sys.argv) == 4:
    from tls import make_context
    context = make_context(Path(transcript_path).parent, sys.argv[3])
with socket.socket() as listener:
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(20)
    print(listener.getsockname()[1], flush=True)
    connection, _ = listener.accept()
    if mode == "tls-stall":
        connection.settimeout(20)
        started = time.monotonic()
        assert connection.recv(1)
        directory = Path(transcript_path).parent
        (directory / 'tls-started').touch()
        try:
            while connection.recv(65536):
                pass
        except ConnectionResetError:
            pass
        (directory / 'tls-duration').write_text(str(time.monotonic() - started))
        (directory / 'tls-closed').touch()
        connection.close()
        sys.exit(0)
    if len(sys.argv) == 4:
        connection.settimeout(10)
        try:
            connection = context.wrap_socket(connection, server_side=True)
        except ssl.SSLError:
            connection.close()
            sys.exit(0)
    with connection:
        connection.settimeout(20)
        stream = connection.makefile("rb")

        def send(value):
            connection.sendall((value + "\r\n").encode())

        capabilities = "IMAP4rev1 ESEARCH" if mode in ("esearch", "oversized") else "IMAP4rev1"
        if mode == "whitespace":
            capabilities += " NAMESPACE"
        if (mode.startswith("gmail") and mode != "gmail-absent") or mode.startswith("order-gmail"):
            capabilities += " X-GM-EXT-1"
        if mode.startswith("plain"):
            capabilities += " AUTH=PLAIN"
        if mode == "plain-ir":
            capabilities += " SASL-IR"
        if mode in ("plain-disabled", "auth-disabled"):
            capabilities += " LOGINDISABLED"
        send(f"* OK [CAPABILITY {capabilities}] Fixture ready")
        mailbox = "INBOX"
        count = 2100 if mode == "cap" else 120
        flag_state = {"\\Answered"}
        if mode in ("flagseen", "flagremove-seen"):
            flag_state.add("\\Seen")
        if mode == "flagalready" or mode.startswith("flagremove") and mode != "flagremove-noop":
            flag_state.add("\\Flagged")
        stored = False
        while True:
            line = stream.readline().decode().rstrip("\r\n")
            if not line:
                break
            literal_query = None
            literal = re.search(r"\{(\d+)(\+)?\}$", line)
            if literal:
                size = int(literal.group(1))
                assert size <= 1026
                if not literal.group(2):
                    send("+ Fixture literal ready")
                literal_query = stream.read(size).decode()
                line = line[:literal.start()] + '"fixture-literal"' + stream.readline().decode().rstrip("\r\n")
            tag, command = line.split(" ", 1)
            verb = command.split(" ", 1)[0].upper()
            # No passwords, search text or message content in the transcript.
            transcript.append(command if command.startswith(("UID FETCH", "UID STORE")) else verb)
            if "X-GM-RAW" in command:
                transcript[-1] = "SEARCH X-GM-RAW"
            elif command.startswith("UID SEARCH") and "FLAGGED" in command:
                transcript[-1] = "SEARCH FLAGGED"
            Path(transcript_path).write_text(json.dumps(transcript))
            if verb == "CAPABILITY":
                send(f"* CAPABILITY {capabilities}")
            elif verb == "LOGIN":
                if mode == "auth" or mode.startswith("plain") or mode == "auth-disabled":
                    send(tag + " NO [AUTHENTICATIONFAILED] Fixture rejection")
                    continue
            elif verb == "AUTHENTICATE":
                assert mode.startswith("plain")
                parts = command.split(" ")
                assert parts[1] == "PLAIN"
                if mode == "plain-ir":
                    assert len(parts) == 3
                    response = parts[2].encode()
                else:
                    assert len(parts) == 2
                    send("+")
                    response = stream.readline().strip()
                assert base64.b64decode(response) == b"\x00fixture\x00fixture"
                if mode == "plain-reject":
                    send(tag + " NO [AUTHENTICATIONFAILED] Fixture rejection")
                    continue
            elif verb == "LOGOUT":
                send("* BYE Fixture closed")
                send(tag + " OK Fixture complete")
                break
            elif verb == "NAMESPACE":
                send('* NAMESPACE (("" "/")) NIL NIL')
            elif verb == "LIST":
                if mode.startswith("order-"):
                    gmail = "gmail" in mode
                    named = mode.endswith("-name")
                    deferred = ("[Google Mail]/All Mail" if named else "[Gmail]/Tous les messages") if gmail else ("Archive" if named else "Archives")
                    attribute = "" if named else "\\All" if gmail else "\\Archive"
                    send(f'* LIST ({attribute}) "/" "{deferred}"')
                    for name in ["INBOX", "Projects/Archive", "Sent"]:
                        send(f'* LIST () "/" "{name}"')
                    send(tag + " OK Fixture complete")
                    continue
                if mode == "whitespace":
                    send('* LIST () "/" " INBOX "')
                    send(tag + " OK Fixture complete")
                    continue
                send('* LIST (\\Noselect) "/" "Container"')
                send('* LIST () "/" "INBOX"')
                send('* LIST (\\Archive) "/" "Archive"')
                if mode in ("gmail-flagged", "gmail-starred"):
                    send('* LIST (\\Flagged) "/" "[Gmail]/Suivis"')
            elif verb in ("EXAMINE", "SELECT"):
                mailbox = "Archive" if "Archive" in command else "INBOX"
                if mode == "partial" and mailbox == "Archive":
                    send(tag + " NO Fixture mailbox unavailable")
                    continue
                send(f"* {count} EXISTS")
                validity = 72 if mode in ("flagvalidity", "previewvalidity") else 71
                if mode != "icloud-no-validity":
                    send(f"* OK [UIDVALIDITY {validity}] Fixture validity")
                send("* FLAGS (\\Seen \\Answered \\Flagged)")
                if verb == "SELECT" and mode != "flagnopersistent":
                    permanent = "" if mode == "flagemptypersistent" else "\\Seen" if mode == "flagunsupported" else "\\Seen \\Answered \\Flagged"
                    send(f"* OK [PERMANENTFLAGS ({permanent})] Fixture flags")
                if mode != "icloud-no-next":
                    send(f"* OK [UIDNEXT {count + 1}] Fixture next")
                state = "READ-WRITE" if mode.startswith("icloud") or mode in ("readwrite", "previewicloud") or (verb == "SELECT" and mode != "flagreadonly") else "READ-ONLY"
                send(f"{tag} OK [{state}] Fixture examined")
                continue
            elif command.startswith("UID SEARCH"):
                if mode == "disconnect":
                    break
                if mode.startswith("gmail") or mode == "imap-phrase":
                    if mode in ("gmail-starred", "gmail-no-starred"):
                        assert "FLAGGED" in command and "X-GM-RAW" not in command
                    elif mode in ("gmail-absent", "gmail-quoted", "gmail-backslash", "imap-phrase"):
                        assert "X-GM-RAW" not in command and "TEXT" in command
                        raw = literal_query if literal_query is not None else json.loads(command.split("TEXT ", 1)[1])
                        expected = 'subject:"report" \\ archive' if mode == "gmail-quoted" else r"path\archive" if mode == "gmail-backslash" else "something anything"
                        assert raw == expected
                    else:
                        assert "X-GM-RAW" in command and "CHARSET UTF-8 UID 1:120" in command
                        raw = literal_query if literal_query is not None else json.loads(command.split("X-GM-RAW ", 1)[1])
                        text = "Résumé" if mode == "gmail-unicode" else "x" * 1024 if mode == "gmail-limit" else "something anything"
                        expected = '"' + text + '"'
                        assert raw == expected
                        assert (" FLAGGED " in command) == (mode == "gmail-flagged")
                    if mode == "gmail-reject":
                        send(tag + " NO Fixture invalid Gmail query")
                        continue
                if mode in ("esearch", "oversized"):
                    upper = 4294967295 if mode == "oversized" else count
                    send(f'* ESEARCH (TAG "{tag}") UID COUNT {upper} MIN 1 MAX {upper} ALL 1:{upper}')
                elif mode in ("flaggedsearch", "gmail-flagged", "gmail-starred", "gmail-no-starred", "icloud-flagged"):
                    assert "FLAGGED" in command
                    send("* SEARCH " + " ".join(str(i) for i in range(2, count + 1, 2)))
                elif mode == "empty":
                    send("* SEARCH")
                else:
                    send("* SEARCH " + " ".join(str(i) for i in range(1, count + 1)))
            elif command.startswith("UID FETCH"):
                if mode == "timeout":
                    time.sleep(12)
                    break
                if mode.startswith("preview"):
                    text = "Hello, résumé."
                    content = text.encode()
                    encoding = "7BIT"
                    subtype = "PLAIN"
                    if mode == "previewbase64":
                        content = base64.b64encode(content)
                        encoding = "BASE64"
                    if mode == "previewhtml":
                        content = b'<p>Hello <b>world</b></p><script>bad()</script><img src="https://invalid.test/pixel">'
                        subtype = "HTML"
                    if mode == "previewlarge":
                        content = b"x" * 40000
                    section = "2" if mode == "previewattachment" else "1"
                    if "BODYSTRUCTURE" in command:
                        assert command == "UID FETCH 7 (UID BODYSTRUCTURE)"
                        body = f'("TEXT" "{subtype}" ("CHARSET" "UTF-8") NIL NIL "{encoding}" {len(content)} 1)'
                        if mode == "previewattachment":
                            body = f'(("TEXT" "PLAIN" ("NAME" "attachment.txt") NIL NIL "7BIT" 99 1) {body} "MIXED")'
                        uid = 8 if mode == "previewmissing" else 7
                        send(f"* 7 FETCH (UID {uid} BODYSTRUCTURE {body})")
                    else:
                        match = re.fullmatch(r"UID FETCH 7 \(BODY\.PEEK\[([12])\]<([0-9]+)\.([0-9]+)>\)", command)
                        assert match and match.group(1) == section
                        offset, length = int(match.group(2)), int(match.group(3))
                        assert length <= 4096 and offset + length <= 32768
                        chunk = content[offset:offset + length]
                        uid = 8 if mode == "previewwronguid" else 7
                        connection.sendall(f"* 7 FETCH (UID {uid} BODY[{section}]<{offset}> {{{len(chunk)}}}\r\n".encode() + chunk + b")\r\n")
                    send(tag + " OK Fixture complete")
                    continue
                if command.endswith("(UID FLAGS)"):
                    assert command == "UID FETCH 7 (UID FLAGS)"
                    if mode != "flagmissing" and not (stored and mode in ("flagvanished", "flagremove-expunge")):
                        assert ("\\Seen" in flag_state) == (mode in ("flagseen", "flagremove-seen"))
                        assert "\\Answered" in flag_state
                        send(f"* 7 FETCH (UID 7 FLAGS ({' '.join(sorted(flag_state))}))")
                    send(tag + " OK Fixture complete")
                    continue
                identifiers = command.split(" ")[2]
                uids = []
                for item in identifiers.split(","):
                    endpoints = item.split(":")
                    uids.extend(range(int(endpoints[0]), int(endpoints[-1]) + 1))
                assert len(uids) <= 50
                assert command.replace('"', '').endswith("(UID INTERNALDATE FLAGS BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE MESSAGE-ID)])")
                for uid in uids:
                    if mode == "missing" and uid == 1:
                        continue
                    headers = ("Subject: =?UTF-8?B?UsOpc3Vtw6k=?=\r\n"
                               "From: Alice <alice@example.test>\r\n"
                               "Date: Mon, 05 Oct 2026 10:00:00 +0000\r\n"
                               f"Message-ID: <fixture-{uid}@example.test>\r\n\r\n")
                    flags = r'\Flagged' if uid % 2 == 0 else ''
                    send(f'* {uid} FETCH (UID {uid} FLAGS ({flags}) INTERNALDATE "05-Oct-2026 10:00:00 +0000" '
                         f'BODY[HEADER.FIELDS (SUBJECT FROM DATE MESSAGE-ID)] {{{len(headers.encode())}}}\r\n'
                         f'{headers})')
            elif command.startswith("UID STORE"):
                assert verb == "UID" and command == (r"UID STORE 7 -FLAGS (\Flagged)" if mode.startswith("flagremove") else r"UID STORE 7 +FLAGS (\Flagged)")
                assert mode.startswith("flag") and not stored
                stored = True
                if mode == "flagdenied":
                    send(tag + " NO [NOPERM] Fixture write refused")
                    continue
                if mode.startswith("flagremove"):
                    flag_state.discard("\\Flagged")
                else:
                    flag_state.add("\\Flagged")
                if mode in ("flagdisconnect", "flagremove-disconnect"):
                    break
                send(f"* 7 FETCH (UID 7 FLAGS ({' '.join(sorted(flag_state))}))")
                if mode == "flagremove-expunge":
                    send("* 7 EXPUNGE")
            else:
                send(tag + " BAD Unexpected fixture command")
                continue
            send(tag + " OK Fixture complete")
