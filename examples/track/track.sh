#!/bin/sh
# What's playing, as events: one line per change, tagged [track].
#   ./track.sh            -> the newest session's inbox
#   ./track.sh music      -> a named inbox (INBOX=music claude)
target=${1:-latest}
playerctl --follow metadata --format '{{artist}} — {{title}}' 2>/dev/null \
  | awk '$0 != last { print; last = $0; fflush() }' \
  | while IFS= read -r line; do inbox send --tag track "$target" "$line"; done
