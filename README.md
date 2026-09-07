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

An event is a line of text from another process. By itself it means nothing; the session
has to be told, by the right party. That telling is the **contract**: a short text, written by
whoever owns the inbox, that the session reads before the first event lands — and again at
every point where it could have been lost.

    inbox contract jobs-1 worker.contract     # set it; makes the inbox if it isn't there yet
    INBOX=jobs-1 claude                       # the session starts with it

`inbox contract <session> -` takes the text on stdin. Writing `/tmp/claude-inbox/<name>.contract`
by hand is the same thing; `INBOX_CONTRACT=/path` points at a file instead. In the text,
`{inbox}`, `{name}`, `{listen}`, `{send}` and `{waiting}` are filled in at delivery.
`inbox contract <session>` with no file prints the filled text, as the session will see it.

### when it lands

- **At session start.** The plugin's SessionStart hook prints it into context in place of
  the default `inbox:` line.
- **After compaction, and on resume.** The same hook fires on both, so the meaning is
  re-stated exactly when context was thrown away. It does not fade.
- **At the top of the listener's stream.** `inbox listen` prints `(contract)` and the text
  before any event. A session that joins a named inbox later, with `/inbox <name>`, gets
  the contract without having been started with it.
- **When it changes while listening.** The listener watches the contract file. A rewrite
  arrives as `(new contract)` and the new text, within two seconds. So a program can attach
  meaning to a session it did not start — `inbox contract latest worker.contract` — or change
  what events mean between phases of a run. Removing the file arrives as `(contract withdrawn)`.

`inbox contract` writes with one atomic swap: a listener sees the old text or the new, never
half. One listener per inbox — a second `inbox listen` on the same inbox exits and names the
pid that has it, so a re-stated "listen" after compaction cannot start a rival.

### writing one

`examples/jobs/worker.contract` is the shape. Four moves, in this order:

1. **What this is.** One sentence: whose events, what is happening outside.
   *You are a worker for a job run happening outside this session.*
2. **Listen.** The exact command, filled, so nothing has to be composed:
   *Listen with Monitor(command: "{listen}", description: "jobs", persistent: true).*
   `{waiting}` says how many events are already there.
3. **The vocabulary.** One line per shape of event and what to do with each. The tag names
   the stream (`[job]`), the first word names the shape (`done`, `failed`, `finished`), an
   id ties it to work the session fired, the rest is payload.
4. **Between, and after.** What to do while nothing arrives (usually: wait), and which
   event ends it (`finished`: sum up, TaskStop the listener). *Nothing else comes through*,
   when true, stops the session guessing at lines it was not told about.

Write it to read right wherever it lands — at start, after a compaction, at the top of the
stream — not only the first time. "Listen with X" ages better than "start now".

### the principle

Meaning belongs to the owner of the inbox, not to the sender of an event. An event carries
data; the contract carries instructions. A program that wants a session to do something new
writes a new contract, not a cleverer event. A session that receives an event it was not told
about treats it as a message from outside, nothing more.

That is also the security stance. Anyone who can write an inbox can send it text; only
whoever can write the `.contract` beside it says what the text means. On one machine that is
the same user either way, so it is a design line rather than a wall — but it is the line.

## examples

- `examples/track` — every song change on the machine becomes an event. Three lines.
- `examples/jobs` — a job runner that starts a session with instructions, sends it `done <id>`
  as each job finishes, and `finished` at the end. The shape a runner uses to fan out parallel
  work and hear each piece finish.

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
