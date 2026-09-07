#!/bin/sh
# A job runner: give a session its instructions and inbox, start it, send an event as each job finishes.
# The session here is an interactive one in a tmux window; a runner built on the SDK does the same.
set -e
name=jobs-$$
dir=${CLAUDE_INBOX_DIR:-/tmp/claude-inbox}
mkdir -p "$dir" /tmp/jobs
inbox contract "$name" "$(dirname "$0")/worker.contract"     # what the events will mean; makes the inbox
inbox send --tag job "$name" "run started, 3 jobs"        # before the session exists: waits in the inbox
tmux new-window -n worker "INBOX=$name claude"            # reads its contract at start, opens the listener
for id in 1 2 3; do
  sleep 15
  printf 'result of job %s\n' "$id" > "/tmp/jobs/$id.out"
  inbox send --tag job "$name" "done $id /tmp/jobs/$id.out"
done
inbox send --tag job "$name" finished
