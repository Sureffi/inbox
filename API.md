# inbox — reference

Everything the tool does, by surface. The README says why; this says what.

## the inbox

An inbox is a plain file. Its path resolves from one argument, `<inbox>`, everywhere:

| argument | resolves to |
|---|---|
| contains `/` | that path, as given |
| anything else | `$CLAUDE_INBOX_DIR/<inbox>` |
| a symlink (`latest`) | its target |

`CLAUDE_INBOX_DIR` defaults to `/tmp/claude-inbox`. Files beside an inbox, all optional:

| file | holds | written by |
|---|---|---|
| `<inbox>` | events, one per line | `send` |
| `<inbox>.seen` | delivery cursor: number of lines delivered | `listen` |
| `<inbox>.listener` | pid of the live listener | `listen`; removed on exit |
| `<inbox>.contract` | what events mean | `contract`, or anyone |
| `<inbox>.contract.tmp` | a contract mid-write, renamed into place | `contract` |
| `latest` | symlink to the newest session's inbox | SessionStart hook |

Same user only. Permissions are the file's.

## line formats

An event line, as stored and as delivered:

    HH:MM event
    HH:MM [tag] event

`HH:MM` is the sender's local wall clock. `[tag]` is present when `--tag`/`tag=` was given.
`event` is the text as sent; newlines in it become separate events.

The listener's output, one line each unless noted:

| line | meaning |
|---|---|
| `(contract)` then the text | the contract that applies, before any event; only if one exists |
| `(queued) HH:MM …` | an event that was in the file before this listener started |
| `HH:MM …` | an event that arrived while listening |
| `(new contract)` then the text | the contract file changed; the new text applies from here |
| `(contract withdrawn) events are plain messages from outside` | the contract file was removed |

Contract text is delivered filled (see placeholders) and may be several lines.

## cli

`inbox` is on `PATH` inside a session and linked at `~/.local/bin/inbox` outside it. Exit
codes: `0` done, `1` no inbox or refused, `2` usage.

### `inbox send [--tag T] [-n] [--] <inbox> [event...]`

Append one event. With `event...`, the arguments joined by single spaces are the event.
Without, each line of stdin is one event; empty lines are skipped.

| flag | effect |
|---|---|
| `--tag T` | prefix the event with `[T]` |
| `-n` | create the inbox if it is missing; otherwise a missing inbox is exit `1` |
| `--` | end of flags |

Prints `inbox: nobody listening on <path> yet — event queued` to stderr when no live
listener holds `<inbox>.listener`. The event is still written.

### `inbox listen <inbox>`

Follow the inbox and print each new line, per the line formats above. Meant to run inside
`Monitor(command: "inbox listen <inbox>", persistent: true)`, but it is an ordinary program:
any process can read an inbox with it.

- Exit `1` if the inbox does not exist, or if `<inbox>.listener` names a live pid: one
  listener per inbox. The message names the pid.
- Writes its pid to `<inbox>.listener`; removes it on exit, including on SIGINT/SIGTERM.
- Delivers from the cursor in `<inbox>.seen`, marks those `(queued)`, then follows. Updates
  the cursor after each line, so nothing is delivered twice across restarts. If the file
  shrinks below the cursor (truncated), the cursor resets to 0.
- Wakes on `inotifywait` when installed (immediate), else polls every 0.5 s. The contract
  file is checked on every wake and at least every 2 s.

### `inbox contract <inbox> [file|-]`

Without a second argument: print the contract that applies to `<inbox>`, filled. That is
`<inbox>.contract` if it exists, else the file `INBOX_CONTRACT` names, else the default
text. Exit `1` if the inbox does not exist.

With `file` or `-` (stdin): write the text to `<inbox>.contract` via a temp file and one
rename. Creates the inbox if missing. A listener, if any, delivers it as `(new contract)`.

### `inbox status <inbox>`

    inbox     /tmp/claude-inbox/jobs-1
    listener  pid 4242                    | none — events queue
    events    7 delivered, 2 waiting
    contract  /tmp/claude-inbox/jobs-1.contract   | none (default text)

Exit `1` if the inbox does not exist.

### `inbox ls`

One line per inbox in `CLAUDE_INBOX_DIR`: name, `listening` or `idle`, events waiting, and
`(contract)` if one is set. Symlinks, executables and the side files are not listed.

### `inbox path <inbox>`

Print the resolved inbox path. Does not check that it exists.

## the contract

A text file. Placeholders are replaced at every delivery, as literal text, no escaping
needed in the values:

| placeholder | filled with |
|---|---|
| `{inbox}` | the inbox path |
| `{name}` | the inbox name (`jobs-1`), or the path if outside `CLAUDE_INBOX_DIR` |
| `{listen}` | `<path to inbox binary> listen <name>` |
| `{send}` | `<path to inbox binary> send <name>` |
| `{waiting}` | events in the file not yet delivered, at the moment of delivery |

Where it is looked up, in order: `<inbox>.contract`; the file `INBOX_CONTRACT` names; else
the default text. Where it is delivered:

| moment | by | as |
|---|---|---|
| session start, resume, clear, compaction | SessionStart hook | context text |
| listener start | `inbox listen` | `(contract)` + text |
| `.contract` changes while listening | `inbox listen` | `(new contract)` + text |
| `.contract` removed while listening | `inbox listen` | `(contract withdrawn)` |
| on request | `inbox contract <inbox>` | stdout |

## environment

| variable | read by | effect |
|---|---|---|
| `CLAUDE_INBOX_DIR` | everything | where inboxes live; default `/tmp/claude-inbox` |
| `INBOX` | hooks | name the session's inbox `<INBOX>` instead of its session id; such an inbox is not removed at session end |
| `INBOX_CONTRACT` | `contract`, `listen`, `status`, libraries | contract file to use when `<inbox>.contract` does not exist |

## hooks

**SessionStart** (startup, resume, clear, compact): makes `$CLAUDE_INBOX_DIR/<name>` if
missing, where `<name>` is `INBOX` or the session id; points `latest` at it (not on compact);
links `~/.local/bin/inbox` to the plugin's binary if `~/.local/bin` exists and the name is
free or already a symlink; prints `inbox contract <name>`, which is the contract or the
default text:

> inbox: this session has an event inbox at `<path>`. Any program on this machine can send
> it an event: `inbox send <name> <message>` (or `inbox send latest ...`) — it arrives here
> as an event. Nothing is received until you listen: run /inbox, or Monitor(command:
> "inbox listen <name>", persistent: true). Open it when the user asks or events are
> expected. *N event(s) already waiting.*

**SessionEnd**: if `INBOX` is unset, removes the session-id inbox and its side files, and
`latest` if it pointed there. A named inbox is left for whoever named it.

## python — `inbox.py`

Zero dependencies. Copy the file or put the repo on `sys.path`.

```python
from inbox import send, contract, status, path, inbox_dir
```

| call | returns | raises |
|---|---|---|
| `inbox_dir()` | `CLAUDE_INBOX_DIR` or the default | |
| `path(session)` | resolved inbox path (symlinks followed) | |
| `send(session, event, tag=None, create=False)` | inbox path | `FileNotFoundError` if missing and not `create` |
| `contract(session, text)` | contract path; creates the inbox; atomic write; adds a trailing newline if absent | |
| `status(session)` | `{"path", "listener", "delivered", "waiting", "contract"}` — `listener` is a pid or `None`, `contract` a path or `None` | `FileNotFoundError` |

`send` with an empty event writes nothing but still creates the inbox when `create=True`.
It does not warn about a missing listener; check `status()` if that matters. There is
no `listen()`: run `inbox listen` as a subprocess and read its stdout, as
`examples/roundtrip/run.py` does.

## node / typescript — `inbox.ts`

Node built-ins only.

```ts
import { send, contract, status, path, inboxDir } from "./inbox";
```

| call | returns | throws |
|---|---|---|
| `inboxDir()` | `CLAUDE_INBOX_DIR` or the default | |
| `path(session)` | resolved inbox path | |
| `send(session, event, { tag?, create? })` | inbox path; an empty event writes nothing | `Error` if missing and not `create` |
| `contract(session, text)` | contract path; creates the inbox; atomic write; adds a trailing newline if absent | |
| `status(session)` | `Status { path, listener, delivered, waiting, contract }` — `listener` a pid or `null`, `contract` a path or `null` | `Error` |

## any language

Append a line to the file:

    printf '%s %s\n' "$(date +%H:%M)" "task 3 done" >> /tmp/claude-inbox/<inbox>

Set the contract: write `<inbox>.contract` via a temp file and rename. Check for a
listener: read the pid in `<inbox>.listener` and signal 0.
