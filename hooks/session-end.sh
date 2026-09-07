#!/bin/sh
# SessionEnd: a session's own inbox goes with it. A named one (INBOX=...) belongs to whoever named it.
[ -n "$INBOX" ] && exit 0
dir=${CLAUDE_INBOX_DIR:-/tmp/claude-inbox}
in=$(cat 2>/dev/null)
sid=$(printf '%s' "$in" | sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p')
[ -n "$sid" ] || exit 0
box=$dir/$sid
[ "$(readlink "$dir/latest" 2>/dev/null)" = "$box" ] && rm -f "$dir/latest"
rm -f "$box" "$box.seen" "$box.listener" "$box.contract" "$box.contract.tmp"
exit 0
