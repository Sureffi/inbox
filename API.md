# inbox — reference

Everything the tool does, in the order a program meets it: address an inbox, send to it,
say what the events mean, check who is there, and what the session sees.

## address

One argument, `<inbox>`, everywhere:

| argument | resolves to |
|---|---|
| contains `/` | that path, as given |
| anything else | `$CLAUDE_INBOX_DIR/<inbox>` |
| a symlink (`latest`) | its target |

`CLAUDE_INBOX_DIR` defaults to `/tmp/claude-inbox`. `latest` points at the newest session's
inbox. An empty name is a usage error; a directory is refused.

## send

    inbox send [--tag T] [-n] [--] <inbox> [event...]

Append one event. With `event...`, the arguments joined by single spaces are the event.
Without, each line of stdin is one event. Empty events are skipped.

| flag | effect |
|---|---|
| `--tag T` | prefix the event with `[T]` |
| `-n` | create the inbox if it is missing; otherwise a missing inbox is exit `1` |
| `--` | end of flags |

The line as stored and as delivered:

    HH:MM event
    HH:MM [tag] event

`HH:MM` is the sender's local wall clock. Newlines in the event become separate events.
When no live listener holds the inbox, stderr says
`inbox: nobody listening on <path> yet — event queued`; the event is still written.

## contract

    inbox contract <inbox>              print the contract that applies, filled
    inbox contract <inbox> <file>       set it from a file; makes the inbox if missing
    inbox contract <inbox> -            set it from stdin

The contract that applies is `<inbox>.contract` if it exists, else the file `INBOX_CONTRACT`
names, else the default text. Setting writes a temp file and renames it into place. A
listener, if any, delivers the new text as `(new contract)`.

Placeholders, replaced as literal text at every delivery:

| placeholder | filled with |
|---|---|
| `{inbox}` | the inbox path |
| `{name}` | the inbox name (`jobs-1`), or the path if outside `CLAUDE_INBOX_DIR` |
| `{listen}` | `<path to inbox binary> listen <name>` |
| `{send}` | `<path to inbox binary> send <name>` |
| `{waiting}` | events in the file not yet delivered, at the moment of delivery |

Delivered:

| moment | by | as |
|---|---|---|
| session start, resume, clear, compaction | SessionStart hook | context text |
| listener start | `inbox listen` | `(contract)` + text |
| `.contract` changes while listening | `inbox listen` | `(new contract)` + text |
| `.contract` removed while listening | `inbox listen` | `(contract withdrawn)` |
| on request | `inbox contract <inbox>` | stdout |

## status, ls, path

    inbox status <inbox>

    inbox     /tmp/claude-inbox/jobs-1
    listener  pid 4242                    | none — events queue
    events    7 delivered, 2 waiting
    contract  /tmp/claude-inbox/jobs-1.contract   | none (default text)

`inbox ls`: one line per inbox in `CLAUDE_INBOX_DIR` — name, `listening` or `idle`, events
waiting, `(contract)` if one is set. Symlinks, executables and side files are not listed.

`inbox path <inbox>`: the resolved path, whether or not it exists.

## listen: what the session sees

    inbox listen <inbox>

Runs inside `Monitor(command: "inbox listen <inbox>", persistent: true)` in a session, and
as an ordinary program anywhere else. Each line of its output:

| line | meaning |
|---|---|
| `(contract)` then the text | the contract that applies, before any event; only if one exists |
| `(queued) HH:MM …` | an event that was in the file before this listener started |
| `HH:MM …` | an event that arrived while listening |
| `(new contract)` then the text | the contract file changed; the new text applies from here |
| `(contract withdrawn) events are plain messages from outside` | the contract file was removed |

Contract text is delivered filled and may be several lines.

- One listener per inbox. If `<inbox>.listener` names a live pid, exit `1` with that pid.
- Writes its pid to `<inbox>.listener`; removes it on exit, including SIGINT/SIGTERM.
- Delivers from the cursor in `<inbox>.seen`, marks those `(queued)`, then follows. The
  cursor advances after each line, so nothing is delivered twice across restarts. If the
  file shrinks below the cursor, the cursor resets to 0.
- Wakes on `inotifywait` when installed, else polls every 0.5 s. The contract file is
  checked on every wake and at least every 2 s.

Exit codes for every command: `0` done, `1` no inbox or refused, `2` usage. `inbox` is on
`PATH` inside a session and linked at `~/.local/bin/inbox` outside it.

## files

| file | holds | written by |
|---|---|---|
| `<inbox>` | events, one per line | `send` |
| `<inbox>.contract` | what events mean | `contract`, or anyone |
| `<inbox>.contract.tmp` | a contract mid-write, renamed into place | `contract` |
| `<inbox>.seen` | delivery cursor: number of lines delivered | `listen` |
| `<inbox>.listener` | pid of the live listener | `listen`; removed on exit |
| `latest` | symlink to the newest session's inbox | SessionStart hook |

Same user only. Permissions are the file's.

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
| `send(session, event, tag=None, create=False)` | inbox path; an empty event writes nothing | `FileNotFoundError` if missing and not `create` |
| `contract(session, text)` | contract path; creates the inbox; atomic write; adds a trailing newline if absent | |
| `status(session)` | `{"path", "listener", "delivered", "waiting", "contract"}` — `listener` a pid or `None`, `contract` a path or `None` | `FileNotFoundError` |
| `path(session)` | resolved inbox path, symlinks followed | |
| `inbox_dir()` | `CLAUDE_INBOX_DIR` or the default | |

`send` does not warn about a missing listener; `status()` says. There is no `listen()`:
run `inbox listen` as a subprocess and read its stdout, as `examples/roundtrip/run.py` does.

## node / typescript — `inbox.ts`

Node built-ins only.

```ts
import { send, contract, status, path, inboxDir } from "./inbox";
```

| call | returns | throws |
|---|---|---|
| `send(session, event, { tag?, create? })` | inbox path; an empty event writes nothing | `Error` if missing and not `create` |
| `contract(session, text)` | contract path; creates the inbox; atomic write; adds a trailing newline if absent | |
| `status(session)` | `Status { path, listener, delivered, waiting, contract }` — `listener` a pid or `null`, `contract` a path or `null` | `Error` |
| `path(session)` | resolved inbox path | |
| `inboxDir()` | `CLAUDE_INBOX_DIR` or the default | |

## any language

Append a line to the file:

    printf '%s %s\n' "$(date +%H:%M)" "task 3 done" >> /tmp/claude-inbox/<inbox>

Set the contract: write `<inbox>.contract` via a temp file and rename. Check for a
listener: read the pid in `<inbox>.listener` and signal 0.
