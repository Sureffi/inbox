# roundtrip

Every call in the programmatic API, in the order a runner makes them, and the session
answering back on the runner's own inbox.

    ./run.py

It prints the command to start the worker. Start it in another terminal; the runner waits
until `status()` shows a listener, sends three jobs and `finished`, then reads the acks from
its own inbox with `inbox listen` — a program like any other — and checks the sums.

What is exercised:

- `contract(session, text)` — authored in code, with the runner's inbox path written into
  it. `{inbox}`, `{listen}`, `{waiting}` are left for inbox to fill at delivery.
- `status(session)["listener"]` — is anyone there yet.
- `send(session, event, tag=)` — one event per job.
- `inbox listen` on the runner's own inbox — the return channel. The session sends with
  the `{send}`-shaped command the contract gave it.

The contract asks the session for the ack. That is the only way a program learns a
contract was read: ask for a reply in it.
