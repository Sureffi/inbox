# mcp

An engine behind an MCP server, bound to the one session that started it.

Claude Code starts a stdio MCP server per session and sets `CLAUDE_CODE_SESSION_ID` in its
environment. `self` resolves to that session's inbox (`INBOX` if the session was named).
The server can compute no other session's inbox from what it has, so this engine talks to
this walker and another walker's engine talks to that one, with nothing configured and
nothing handed over.

    {
      "mcpServers": {
        "engine": { "command": "python3", "args": ["/path/to/inbox/examples/mcp/server.py"] }
      }
    }

in `.mcp.json`, then in the session: `/inbox`, and call `run` with `seconds` and a `label`.
The call returns at once with a job id. When the job lands, `[engine] done <id> <label>`
arrives in the inbox. `notify: false` on a call makes that one call silent.

What the server does, in order:

1. `path("self")` at import: the inbox of the session that started it. Raises if there is
   none, so a server started by hand fails loud instead of finding `latest`.
2. `contract("self", …)` before serving: what its events mean, on the walker's own inbox.
   It lands at the top of the stream when the walker opens the listener.
3. Each `run` starts a thread and returns. The thread sends `done <id> <label>` to the
   same inbox when it finishes, tagged `[engine]`, unless the call said `notify: false`.

`server.py` is the MCP stdio transport in forty lines and no dependencies, so the pattern
is visible whole. A real engine keeps steps 1 to 3 and replaces the job.
