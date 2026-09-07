#!/bin/sh
# SessionStart: the session gets an inbox, `latest` points at it, the model is handed the contract.
# Fires on startup, resume, clear and compact — so what events mean is re-stated whenever context was lost.
dir=${CLAUDE_INBOX_DIR:-/tmp/claude-inbox}
root=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
in=$(cat 2>/dev/null)
sid=$(printf '%s' "$in" | sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p')
src=$(printf '%s' "$in" | sed -n 's/.*"source" *: *"\([^"]*\)".*/\1/p')
name=${INBOX:-${sid:-session-$$}}
box=$dir/$name
bin=$root/bin/inbox
mkdir -p "$dir"
[ -e "$box" ] || : > "$box"
[ "$src" = compact ] || ln -sfn "$box" "$dir/latest"
# put `inbox` on PATH for the rest of the machine: a link in ~/.local/bin, never over a real file
lb=$HOME/.local/bin
if [ -d "$lb" ] && { [ ! -e "$lb/inbox" ] || [ -L "$lb/inbox" ]; }; then ln -sfn "$bin" "$lb/inbox"; fi
# the text the session starts with: the owner's contract if there is one ($box.contract or $INBOX_CONTRACT), else the default
"$bin" contract "$name"
