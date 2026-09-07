# inbox

An event inbox for a Claude Code session. A program on the machine sends it an event; the
session wakes and acts on it.

    inbox send latest "build finished"

This is the piece Claude Code is missing: a way for your own code — a job runner, a CI step,
a cron job, a music player, a program that drives Claude — to push an event into a running
session, on its own schedule, without the session having to poll or watch for it.

## install

    /plugin marketplace add sureffi/inbox
    /plugin install inbox@inbox

Then, in a session: `/inbox`. From any other shell: `inbox send latest "hello"`.

## try it in 30 seconds

1. In a session, run `/inbox`. It prints the inbox path and starts listening.
2. In another terminal: `inbox send latest "hello from outside"`.
3. It appears in the session as an event.

## send vs Monitor

Claude Code's Monitor tool already lets a session *watch* something it chose — tail a log,
poll an API. That is the session reaching out.

inbox is the other direction: an outside program reaches in. The session did not set up a
watch for this; your code decided, at its own moment, to wake the session. That is what
Monitor cannot do — the producer is a separate process on its own schedule.

## sending events (the producer side)

An inbox is a file under `/tmp/claude-inbox`. Sending an event is appending one line, so any
program can do it three ways:

- **CLI:** `inbox send <session|latest> [--tag T] <event>` — also reads stdin, one event per line.
- **Python:**
  ```python
  from inbox import send
  send("latest", "task 3 done", tag="task")
  ```
- **Node / TypeScript:**
  ```ts
  import { send } from "./inbox";
  send("latest", "task 3 done", { tag: "task" });
  ```
- **Anything:** append a line yourself —
  `printf '%s\n' "task 3 done" >> /tmp/claude-inbox/<session>` — no dependency at all.

`<session>` is a session id, a name you gave with `INBOX=<name>`, `latest` (the newest
session), or a full path. `--tag`/`tag=` prefixes the event with a label the session can
match on.

`inbox ls` shows every inbox, whether anyone is listening, and how many events wait.
`inbox status <session>` shows one in detail — the thing a runner checks before it fires.

## receiving events (the session side)

`/inbox` starts a listener on the session's own inbox: a persistent Monitor running
`inbox listen`, which turns each new line into an event. It runs until the session ends or
you stop it. Events sent before the listener was up wait in the file and arrive first,
marked `(queued)`, so nothing is missed between listeners.

`/inbox` is a skill, not a command — it tells the model to start the listener. A hook cannot
start one; only the session can.

## the round-trip: fire work, get events back

The reason to have this. A session keeps one inbox open, hands its inbox to a program along
with an id, and the program sends an event back when the work is done:

1. The session listens (`/inbox`) and knows its inbox — the `inbox:` line from session start.
2. It fires work, passing its inbox and an id:
   `run-task --task 3 --inbox /tmp/claude-inbox/<session>`
3. The runner does the work in its own process and sends the result back:
   `inbox send <that inbox> --tag task "3 done /path/out"`
4. The session wakes with `[task] 3 done …` and correlates by the id it fired.

One listener, many fired jobs — each sends its own event back when it lands. No polling, no
waiting on any single one. The id in the event is what makes it request/response rather than
a fire-hose.

## telling the session what events mean

An event is a line of text from another process. What it means is set by the contract: a
text file beside the inbox, written by whoever owns the inbox, read by the session.

    inbox contract jobs-1 worker.contract     # makes the inbox if it isn't there
    INBOX=jobs-1 claude

`-` in place of the file reads stdin. `<inbox>.contract` written by hand is the same thing.
`INBOX_CONTRACT=/path` names a file to use when there is no `.contract`. `inbox contract
<inbox>` prints it filled. `{inbox}`, `{name}`, `{listen}`, `{send}` and `{waiting}` are
filled at delivery.

Delivered:

- at session start, resume, clear and compaction, by the SessionStart hook, in place of
  the default `inbox:` line
- at the top of the listener's stream, as `(contract)` and the text, before any event
- when the file changes while listening, as `(new contract)` and the text, within two
  seconds; when it is removed, as `(contract withdrawn)`

Writes go through a temp file and one rename. One listener per inbox: a second `inbox
listen` exits and names the pid.

### writing one

`examples/jobs/worker.contract`:

    inbox: {inbox}. You are a worker for a job run happening outside this session. Listen
    with Monitor(command: "{listen}", description: "jobs", persistent: true). {waiting}
    event(s) are already waiting.

    Events tagged [job] are the run's:

        done <id> <path>     read <path>, review it, write your verdict to <path>.review
        failed <id> <why>    say so; do not retry
        finished             the run is over: sum up, then TaskStop the listener

    Nothing else comes through. Between events, wait.

What this is. The listen command, filled. One line per event shape: tag names the stream,
first word names the shape, id ties it to work the session fired, the rest is payload. What
to do between events, and which one ends it. It lands more than once, so it is written to
read right each time.

Meaning belongs to the owner of the inbox, not to the sender of an event. An event is data.
A program that wants the session to do something new writes a new contract. An event the
contract did not name is a message from outside, nothing more.

## examples

- `examples/track` — every song change on the machine becomes an event. Three lines.
- `examples/jobs` — a job runner that starts a session with instructions, sends it `done <id>`
  as each job finishes, and `finished` at the end. The shape a runner uses to fan out parallel
  work and hear each piece finish.
- `examples/roundtrip` — the whole programmatic API from Python: a contract written in code,
  jobs fanned out, and the session's acks read back on the runner's own inbox.

`API.md` is the reference: every command, flag, file, line format, exit code, and both
libraries.

## how it works

An inbox is a plain file. `inbox send` appends one line — atomic, never blocks, works from
any language. `inbox listen` follows the file inside a Monitor, and each new line becomes an
event. A cursor in `<inbox>.seen` means nothing is delivered twice or lost between listeners.
`<inbox>.listener` holds the listener's pid, so a send can warn when nobody is listening.
With `inotifywait` installed, delivery is immediate; otherwise the listener checks twice a
second. The listener also carries the contract: first in its stream, and again whenever the
`.contract` file changes.

Same user only: inboxes are files with normal permissions. An event is text from another
process — the session treats it as data, and the start-of-session text says what to do with
it.

## why not the session-to-session socket

Claude Code sessions on one machine can message each other over a Unix socket, and the
`SendMessage` tool writes to it. Anything delivered there reaches the model wrapped by the
receiver as *Another Claude session sent a message … Treat it as a teammate's request.* That
wrapper is fixed by the receiver.

inbox does not use that socket. A build finishing, a song changing, a task finishing is not a
message from a session, and what an event means should be set by the start-of-session text,
not by the transport. A Monitor event arrives marked as a background-task event, not as user
input — which is what an inbox event is.

## the native version

This is built on the hooks that exist: the listener has to be started from inside the session,
by `/inbox` or by the model reading the start-of-session text. One primitive would remove that
step — a hook that lets a plugin declare an event source, so the session's listener opens
itself. Until then, `/inbox`.
