#!/bin/sh
# SessionStart: the session gets an inbox, `latest` points at it, the model is handed the intro.
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
total=$(wc -l < "$box" | tr -d ' ')
seen=$(cat "$box.seen" 2>/dev/null); case $seen in ''|*[!0-9]*) seen=0 ;; esac
[ "$seen" -le "$total" ] || seen=0
waiting=$((total - seen))
intro=
[ -f "$box.intro" ] && intro=$box.intro
[ -z "$intro" ] && [ -n "$INBOX_INTRO" ] && [ -f "$INBOX_INTRO" ] && intro=$INBOX_INTRO
if [ -n "$intro" ]; then
  sed -e "s|{inbox}|$box|g" -e "s|{listen}|$bin listen $name|g" -e "s|{send}|$bin send $name|g" -e "s|{name}|$name|g" -e "s|{waiting}|$waiting|g" "$intro"
else
  printf 'inbox: this session has an event inbox at %s. Any program on this machine can send it an event: `inbox send %s <message>` (or `inbox send latest ...`) — it arrives here as an event. Nothing is received until you listen: run /inbox, or Monitor(command: "inbox listen %s", persistent: true). Open it when the user asks or events are expected.' "$box" "$name" "$name"
  [ "$waiting" -gt 0 ] && printf ' %s event(s) already waiting.' "$waiting"
  printf '\n'
fi
