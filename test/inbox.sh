#!/bin/sh
# End to end without Claude Code: send, listen, queue, cursor, python helper.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
export CLAUDE_INBOX_DIR=$(mktemp -d)
PATH=$here/bin:$PATH
out=$CLAUDE_INBOX_DIR/out
fail() { echo "FAIL: $*" >&2; exit 1; }

inbox send -n s "before anyone listens"                       2>/dev/null
inbox send --tag job s "done 1 /tmp/x"                         2>&1 | grep -q 'nobody listening' || fail "no-listener notice"
inbox listen s > "$out" & lp=$!
sleep 1
grep -q '^(queued) [0-9:]* before anyone listens$' "$out"     || fail "queued line 1"
grep -q '^(queued) [0-9:]* \[job\] done 1 /tmp/x$' "$out"      || fail "queued tagged line"
inbox send s "live one"                                       2>"$CLAUDE_INBOX_DIR/err"
grep -q 'nobody' "$CLAUDE_INBOX_DIR/err" && fail "listener not seen as present"
python3 - "$here" s <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); from inbox import send
send(sys.argv[2], "from python", tag="py")
PY
sleep 1
grep -q '^[0-9:]* live one$' "$out"                           || fail "live line"
grep -q '^[0-9:]* \[py\] from python$' "$out"                 || fail "python helper line"
[ "$(cat "$CLAUDE_INBOX_DIR/s.seen")" = 4 ]                   || fail "cursor $(cat "$CLAUDE_INBOX_DIR/s.seen") != 4"
kill $lp; wait $lp 2>/dev/null || true
[ -e "$CLAUDE_INBOX_DIR/s.listener" ] && fail "listener pidfile left behind"
inbox send s "while away"                                     2>/dev/null
inbox listen s > "$out" & lp=$!
sleep 1
[ "$(wc -l < "$out" | tr -d ' ')" = 1 ]                       || fail "redelivery: $(cat "$out")"
grep -q '^(queued) [0-9:]* while away$' "$out"                || fail "queued after restart"
kill $lp; wait $lp 2>/dev/null || true
inbox send nope "x" 2>/dev/null && fail "sent to an inbox that doesn't exist"
inbox path s | grep -q "^$CLAUDE_INBOX_DIR/s$"                || fail "path subcommand"
rm -rf "$CLAUDE_INBOX_DIR"
echo "inbox: ok"
