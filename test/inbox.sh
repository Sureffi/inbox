#!/bin/sh
# End to end without Claude Code: send, listen, queue, cursor, contract, status, python helper.
set -e
here=$(cd "$(dirname "$0")/.." && pwd -P)
export CLAUDE_INBOX_DIR=$(mktemp -d)
PATH=$here/bin:$PATH
out=$CLAUDE_INBOX_DIR/out
lp=
trap '[ -z "$lp" ] || kill $lp 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
settle() { sleep "${1:-1}"; }

# --- send / listen / queue / cursor
inbox send -n s "before anyone listens"                       2>/dev/null
inbox send --tag job s "done 1 /tmp/x"                         2>&1 | grep -q 'nobody listening' || fail "no-listener notice"
inbox listen s > "$out" & lp=$!
settle
grep -q '^(queued) [0-9:]* before anyone listens$' "$out"     || fail "queued line 1"
grep -q '^(queued) [0-9:]* \[job\] done 1 /tmp/x$' "$out"      || fail "queued tagged line"
grep -q '^(contract)' "$out"                                      && fail "contract line with no contract set"
inbox send s "live one"                                       2>"$CLAUDE_INBOX_DIR/err"
grep -q 'nobody' "$CLAUDE_INBOX_DIR/err" && fail "listener not seen as present"
python3 - "$here" s <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); from inbox import send
send(sys.argv[2], "from python", tag="py")
PY
settle
grep -q '^[0-9:]* live one$' "$out"                           || fail "live line"
grep -q '^[0-9:]* \[py\] from python$' "$out"                 || fail "python helper line"
[ "$(cat "$CLAUDE_INBOX_DIR/s.seen")" = 4 ]                   || fail "cursor $(cat "$CLAUDE_INBOX_DIR/s.seen") != 4"

# --- one listener per inbox; status sees it
inbox listen s 2>"$CLAUDE_INBOX_DIR/err" && fail "second listener accepted"
grep -q "already listening on $CLAUDE_INBOX_DIR/s (pid $lp)" "$CLAUDE_INBOX_DIR/err" || fail "second listener message: $(cat "$CLAUDE_INBOX_DIR/err")"
[ "$(cat "$CLAUDE_INBOX_DIR/s.listener")" = "$lp" ]           || fail "refused listener clobbered the pidfile"
inbox status s > "$CLAUDE_INBOX_DIR/st"
grep -q "^listener  pid $lp$" "$CLAUDE_INBOX_DIR/st"          || fail "status listener: $(cat "$CLAUDE_INBOX_DIR/st")"
grep -q '^events    4 delivered, 0 waiting$' "$CLAUDE_INBOX_DIR/st" || fail "status events: $(cat "$CLAUDE_INBOX_DIR/st")"
grep -q '^contract  none' "$CLAUDE_INBOX_DIR/st"              || fail "status contract: $(cat "$CLAUDE_INBOX_DIR/st")"
kill $lp; wait $lp 2>/dev/null || true
[ -e "$CLAUDE_INBOX_DIR/s.listener" ] && fail "listener pidfile left behind"
inbox send s "while away"                                     2>/dev/null
inbox listen s > "$out" & lp=$!
settle
[ "$(wc -l < "$out" | tr -d ' ')" = 1 ]                       || fail "redelivery: $(cat "$out")"
grep -q '^(queued) [0-9:]* while away$' "$out"                || fail "queued after restart"
kill $lp; wait $lp 2>/dev/null || true

# --- contract: set before the inbox exists, filled, first in the stream, follows changes
printf 'box {inbox} name {name}\nlisten: {listen}\nsend: {send} ({waiting} waiting) a|b&c\n' | inbox contract w -
[ -f "$CLAUDE_INBOX_DIR/w" ]                                  || fail "contract did not make the inbox"
inbox send --tag job w "done 1" 2>/dev/null
inbox contract w > "$CLAUDE_INBOX_DIR/it"
grep -q "^box $CLAUDE_INBOX_DIR/w name w$" "$CLAUDE_INBOX_DIR/it"        || fail "fill inbox/name: $(cat "$CLAUDE_INBOX_DIR/it")"
grep -q "^listen: $here/bin/inbox listen w$" "$CLAUDE_INBOX_DIR/it"      || fail "fill listen: $(cat "$CLAUDE_INBOX_DIR/it")"
grep -q "^send: $here/bin/inbox send w (1 waiting) a|b&c$" "$CLAUDE_INBOX_DIR/it" || fail "fill send/waiting, literal chars: $(cat "$CLAUDE_INBOX_DIR/it")"
inbox listen w > "$out" & lp=$!
settle
[ "$(sed -n 1p "$out")" = "(contract)" ]                         || fail "contract not first in stream: $(cat "$out")"
[ "$(sed -n 2p "$out")" = "box $CLAUDE_INBOX_DIR/w name w" ]  || fail "contract text not filled in stream: $(cat "$out")"
grep -q '^(queued) [0-9:]* \[job\] done 1$' "$out"            || fail "queued event after contract"
[ "$(grep -c '' "$out")" = 5 ]                                || fail "stream shape: $(cat "$out")"
printf 'phase two: {waiting} waiting\n' > "$CLAUDE_INBOX_DIR/p2"
inbox contract w "$CLAUDE_INBOX_DIR/p2"
settle 3
grep -q '^(new contract)$' "$out"                            || fail "contract change not delivered: $(cat "$out")"
grep -q '^phase two: 0 waiting$' "$out"                       || fail "changed contract not filled: $(cat "$out")"
inbox status w | grep -q "^contract  $CLAUDE_INBOX_DIR/w.contract$" || fail "status contract path"
rm "$CLAUDE_INBOX_DIR/w.contract"
settle 3
grep -q '^(contract withdrawn)' "$out"                             || fail "contract removal not delivered: $(cat "$out")"
kill $lp; wait $lp 2>/dev/null || true
INBOX_CONTRACT=$CLAUDE_INBOX_DIR/p2 inbox contract w | grep -q '^phase two: 0 waiting$' || fail "INBOX_CONTRACT not honoured"
inbox contract s | grep -q '^inbox: this session has an event inbox at' || fail "default contract when none set"
python3 - "$here" py <<'PY'
import sys, os; sys.path.insert(0, sys.argv[1]); from inbox import contract
p = contract(sys.argv[2], "hello {name}")
assert p.endswith("/py.contract") and open(p).read() == "hello {name}\n", p
PY
inbox contract py | grep -q '^hello py$'                         || fail "python contract helper"
python3 - "$here" py <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); from inbox import send, path
send(sys.argv[2], "")
assert open(path(sys.argv[2])).read() == "", "empty event was written"
PY
inbox send --tag x py "one" 2>/dev/null
python3 - "$here" py <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); from inbox import status
s = status(sys.argv[2])
assert s["listener"] is None and s["delivered"] == 0 and s["waiting"] == 1 and s["contract"].endswith("/py.contract"), s
PY

# --- ls, path, missing
inbox ls > "$CLAUDE_INBOX_DIR/ls"
grep -q '^s  *idle  *0 waiting$' "$CLAUDE_INBOX_DIR/ls"       || fail "ls s: $(cat "$CLAUDE_INBOX_DIR/ls")"
grep -q '^py  *idle  *1 waiting  (contract)$' "$CLAUDE_INBOX_DIR/ls" || fail "ls py: $(cat "$CLAUDE_INBOX_DIR/ls")"
inbox send nope "x" 2>/dev/null && fail "sent to an inbox that doesn't exist"
inbox contract "" 2>/dev/null && fail "empty name accepted"
inbox status "$CLAUDE_INBOX_DIR" 2>/dev/null && fail "directory accepted as an inbox"
inbox path s | grep -q "^$CLAUDE_INBOX_DIR/s$"                || fail "path subcommand"
CLAUDE_CODE_SESSION_ID=sid-1 inbox path self | grep -q "^$CLAUDE_INBOX_DIR/sid-1$" || fail "self from session id"
INBOX=named CLAUDE_CODE_SESSION_ID=sid-1 inbox path self | grep -q "^$CLAUDE_INBOX_DIR/named$" || fail "self prefers INBOX"
env -u INBOX -u CLAUDE_CODE_SESSION_ID inbox path self 2>/dev/null && fail "self resolved with no session in the environment"
CLAUDE_CODE_SESSION_ID=sid-1 python3 - "$here" <<'PY'
import sys, os; sys.path.insert(0, sys.argv[1]); from inbox import path
assert path("self").endswith("/sid-1"), path("self")
PY
rm -rf "$CLAUDE_INBOX_DIR"
echo "inbox: ok"
