#!/usr/bin/env python3
"""The whole programmatic API in one runner: a contract written from code, work fanned out,
and the session heard back from — on the runner's own inbox.

    ./run.py                # then, in another terminal, the command it prints

The runner owns two inboxes. The worker's, which it writes the contract to and sends jobs
to; and its own, which the session sends acks to. `inbox listen` is a program like any
other, so the runner reads its inbox the same way a session does.
"""
import os, subprocess, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from inbox import send, contract, status, path

worker = f"worker-{os.getpid()}"
runner = f"runner-{os.getpid()}"
send(runner, "", create=True)                   # an empty event makes the inbox; nothing is written
runner_box = path(runner)

# 1. the contract — authored here, with the runner's own inbox written into it.
#    {listen} and {waiting} are filled by inbox at delivery; the rest is this program's.
contract(worker, f"""inbox: {{inbox}}. You are a worker for run {runner}, happening outside this session.
Listen with Monitor(command: "{{listen}}", description: "worker", persistent: true). {{waiting}} event(s) already waiting.

Events tagged [job] are the run's:

    do <id> <n>      compute the sum 1..n; report it: inbox send --tag ack {runner_box} "<id> <sum>"
    finished         the run is over: inbox send --tag ack {runner_box} finished, then TaskStop the listener

Nothing else comes through. Between events, wait.
""")

print(f"start the worker in another terminal:\n\n    INBOX={worker} claude\n", flush=True)
while status(worker)["listener"] is None:        # 2. wait for someone to be there
    time.sleep(1)
print("worker is listening", flush=True)

for i, n in enumerate((10, 100, 1000), start=1):  # 3. fan out; each job is one event
    send(worker, f"do {i} {n}", tag="job")
send(worker, "finished", tag="job")

# 4. hear back. The runner's inbox is read with the same listener a session uses.
expect = {"1": 55, "2": 5050, "3": 500500}
with subprocess.Popen(["inbox", "listen", runner], stdout=subprocess.PIPE, text=True) as lst:
    for line in lst.stdout:
        line = line.removeprefix("(queued) ").strip()
        parts = line.split(" ", 2)                # "HH:MM [ack] <body>"
        if len(parts) < 3 or parts[1] != "[ack]":
            continue                              # not one of ours: the contract says nothing else comes, but data is data
        body = parts[2]
        if body == "finished":
            break
        job_id, value = body.split()
        ok = int(value) == expect.get(job_id)
        print(f"job {job_id}: {value} {'ok' if ok else 'WRONG, expected ' + str(expect.get(job_id))}")
    lst.terminate()
print("run finished")
