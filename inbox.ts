// inbox — send events to a Claude Code session from Node/TypeScript.
//
//     import { send } from "./inbox";
//     send("latest", "task 3 done", { tag: "task" });
//
// An inbox is a file under $CLAUDE_INBOX_DIR (default /tmp/claude-inbox). Sending an
// event is appending one line, so this uses only Node built-ins and never blocks. A
// session receives events only while it is listening (/inbox); events sent before that
// wait in the file.

import { appendFileSync, closeSync, existsSync, lstatSync, mkdirSync, openSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";

export function inboxDir(): string {
  return process.env.CLAUDE_INBOX_DIR ?? "/tmp/claude-inbox";
}

/** Absolute inbox path for a session id/name, "latest", or a full path. */
export function path(session: string): string {
  const p = session.includes("/") ? session : join(inboxDir(), session);
  try {
    if (lstatSync(p).isSymbolicLink()) return realpathSync(p);
  } catch {
    /* not there yet — return the plain path */
  }
  return p;
}

export interface SendOptions {
  /** label; the event arrives as "HH:MM [tag] event" */
  tag?: string;
  /** create the inbox if it does not exist (default: throw if missing) */
  create?: boolean;
}

/** Append one event to a session's inbox. Returns the inbox path. */
export function send(session: string, event: string, opts: SendOptions = {}): string {
  const p = path(session);
  if (!existsSync(p)) {
    if (!opts.create) {
      throw new Error(`no inbox at ${p} (pass { create: true }, or ls ${inboxDir()})`);
    }
    mkdirSync(dirname(p), { recursive: true });
    closeSync(openSync(p, "a"));
  }
  const now = new Date();
  const stamp = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
  const line = opts.tag ? `${stamp} [${opts.tag}] ${event}\n` : `${stamp} ${event}\n`;
  appendFileSync(p, line);
  return p;
}
