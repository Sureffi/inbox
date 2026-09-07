"""inbox — send events to a Claude Code session from Python.

    from inbox import send, contract, status
    contract("jobs-1", open("worker.contract").read())   # what the events will mean
    send("jobs-1", "done 3 /tmp/out", tag="job")           # an event
    status("jobs-1")["listener"]                           # pid of the session's listener, or None

An inbox is a file under $CLAUDE_INBOX_DIR (default /tmp/claude-inbox). Sending an
event is appending one line, so this has no dependency on the `inbox` CLI and never
blocks. A session receives events only while it is listening (`/inbox`); events sent
before that wait in the file.
"""
import os
import time

def inbox_dir():
    return os.environ.get("CLAUDE_INBOX_DIR", "/tmp/claude-inbox")

def path(session):
    """Absolute inbox path for a session name, `latest`, or a full path."""
    p = session if "/" in session else os.path.join(inbox_dir(), session)
    return os.path.realpath(p) if os.path.islink(p) else p

def _ensure(p, create):
    if not os.path.exists(p):
        if not create:
            raise FileNotFoundError(f"no inbox at {p} (pass create=True, or: inbox ls)")
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "a").close()

def send(session, event, tag=None, create=False):
    """Append one event to a session's inbox. Returns the inbox path.

    session  a session id/name, "latest", or a full path
    event    the line the session receives
    tag      optional label; arrives as "HH:MM [tag] event"
    create   make the inbox if it does not exist (default: error if missing)
    """
    p = path(session)
    _ensure(p, create)
    if not event:
        return p                       # like the CLI: an empty event is not an event; the inbox still gets made
    stamp = time.strftime("%H:%M")
    line = f"{stamp} [{tag}] {event}\n" if tag else f"{stamp} {event}\n"
    with open(p, "a") as f:
        f.write(line)
    return p

def contract(session, text):
    """Set what events on this inbox mean. Makes the inbox if it does not exist.

    The session reads the text at start, after every compaction, at the top of its
    listener's stream, and again whenever it changes. {inbox} {name} {listen} {send}
    {waiting} inside it are filled in at delivery. Written as one atomic swap.
    """
    p = path(session)
    _ensure(p, True)
    tmp = p + ".contract.tmp"
    with open(tmp, "w") as f:
        f.write(text if text.endswith("\n") else text + "\n")
    os.replace(tmp, p + ".contract")
    return p + ".contract"

def status(session):
    """What the CLI's `inbox status` shows, as a dict.

    path       the inbox file
    listener   pid of the live listener, or None (events queue until one is up)
    delivered  events the listener has passed on
    waiting    events in the file not yet delivered
    contract   path of the contract file that applies, or None (default text)
    """
    p = path(session)
    if not os.path.exists(p):
        raise FileNotFoundError(f"no inbox at {p}")
    with open(p) as f:
        total = sum(1 for _ in f)
    try:
        seen = int(open(p + ".seen").read().strip() or 0)
    except (FileNotFoundError, ValueError):
        seen = 0
    if seen > total:
        seen = 0
    listener = None
    try:
        pid = int(open(p + ".listener").read().strip())
        os.kill(pid, 0)
        listener = pid
    except (FileNotFoundError, ValueError, ProcessLookupError, PermissionError):
        pass
    c = None
    if os.path.isfile(p + ".contract"):
        c = p + ".contract"
    elif os.environ.get("INBOX_CONTRACT") and os.path.isfile(os.environ["INBOX_CONTRACT"]):
        c = os.environ["INBOX_CONTRACT"]
    return {"path": p, "listener": listener, "delivered": seen, "waiting": total - seen, "contract": c}
