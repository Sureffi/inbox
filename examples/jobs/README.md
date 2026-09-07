# jobs

A program that runs Claude owns the inbox: it writes the instructions, names the inbox, starts
the session, and sends an event as each job finishes. The session reads the instructions at
start, opens its listener, and acts on each event — no polling, no prompt per event.

    ./run.sh

`worker.contract` is the whole contract; `run.sh` sets it with `inbox contract` before the session exists. `run.sh` is a sketch: a tmux window for the worker,
three jobs fifteen seconds apart, `finished` at the end. A named inbox outlives the session,
so an event can land before the worker is up, and a second worker can pick up where the first
stopped.

This is the shape for fanning out parallel work: the session starts each task with its own
inbox and an id, the task's runner sends `done <id>` back when it finishes, and the session —
one listener open — wakes and correlates by the id.
