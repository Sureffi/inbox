#!/usr/bin/env python3
"""An MCP server that talks to the session that started it, and no other.

Claude Code starts one stdio MCP server process per session and puts the session's id in
its environment. `self` resolves to that session's inbox. So this server can address exactly
one walker, the one it belongs to, and nothing has to be configured or handed over.

At startup it writes its contract onto that inbox. Each tool call returns at once with a job
id and does its work in the background, sending an event when it lands, unless the call said
notify=false.

No dependencies: the MCP stdio transport is newline-delimited JSON-RPC, handled below.
"""
import json, os, sys, threading, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from inbox import send, contract, path

CONTRACT = """inbox: {inbox}. An engine (examples/mcp/server.py) is running for this session and sends
its events here. Listen with Monitor(command: "{listen}", description: "engine", persistent: true).
{waiting} event(s) already waiting.

Events tagged [engine] are the engine's:

    done <id> <label>     the job you started with run() has finished; say so
    failed <id> <why>     the job did not finish; say so, do not retry

Nothing else comes through. Between events, wait.
"""

TOOLS = [{
    "name": "run",
    "description": "Start a job that takes `seconds` to finish. Returns at once with a job id. "
                   "When the job lands, an event arrives in this session's inbox, unless notify is false.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "seconds": {"type": "number", "description": "how long the job takes"},
            "label": {"type": "string", "description": "a name for the job, echoed in the event"},
            "notify": {"type": "boolean", "description": "send an event when the job lands (default true)", "default": True},
        },
        "required": ["seconds", "label"],
    },
}]

box = path("self")                 # raises if no session started this process: fail loud, never `latest`
contract("self", CONTRACT)
jobs = 0

def job(job_id, seconds, label, notify):
    time.sleep(seconds)
    if notify:
        send(box, f"done {job_id} {label}", tag="engine")

def call(name, args):
    global jobs
    if name != "run":
        raise ValueError(f"no tool {name}")
    jobs += 1
    threading.Thread(target=job, args=(jobs, float(args["seconds"]), args["label"], args.get("notify", True)), daemon=True).start()
    where = f"an event lands in {box} when it does" if args.get("notify", True) else "no event will be sent"
    return f"started job {jobs} ({args['label']}, {args['seconds']}s); {where}"

def reply(msg_id, result=None, error=None):
    out = {"jsonrpc": "2.0", "id": msg_id}
    out["error" if error else "result"] = error or result
    sys.stdout.write(json.dumps(out) + "\n"); sys.stdout.flush()

for line in sys.stdin:
    if not line.strip():
        continue
    msg = json.loads(line)
    method, msg_id, params = msg.get("method"), msg.get("id"), msg.get("params") or {}
    if method == "initialize":
        reply(msg_id, {"protocolVersion": params.get("protocolVersion", "2025-06-18"),
                       "capabilities": {"tools": {}}, "serverInfo": {"name": "engine", "version": "0.1"}})
    elif method == "tools/list":
        reply(msg_id, {"tools": TOOLS})
    elif method == "tools/call":
        try:
            reply(msg_id, {"content": [{"type": "text", "text": call(params["name"], params.get("arguments") or {})}]})
        except Exception as e:
            reply(msg_id, {"content": [{"type": "text", "text": str(e)}], "isError": True})
    elif method == "ping":
        reply(msg_id, {})
    elif msg_id is not None:
        reply(msg_id, error={"code": -32601, "message": f"unknown method {method}"})
