// inbox — send events to a Claude Code session from Node/TypeScript.
//
//     import { send, contract } from "./inbox";
//     contract("jobs-1", readFileSync("worker.contract", "utf8"));   // what the events will mean
//     send("jobs-1", "done 3 /tmp/out", { tag: "job" });       // an event
//
// An inbox is a file under $CLAUDE_INBOX_DIR (default /tmp/claude-inbox). Sending an
// event is appending one line, so this uses only Node built-ins and never blocks. A
// session receives events only while it is listening (/inbox); events sent before that
// wait in the file.

import { appendFileSync, closeSync, existsSync, lstatSync, mkdirSync, openSync, realpathSync, renameSync, writeFileSync } from "node:fs";
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

function ensure(p: string, create: boolean): void {
  if (existsSync(p)) return;
  if (!create) throw new Error(`no inbox at ${p} (pass { create: true }, or: inbox ls)`);
  mkdirSync(dirname(p), { recursive: true });
  closeSync(openSync(p, "a"));
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
  ensure(p, opts.create ?? false);
  const now = new Date();
  const stamp = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
  const line = opts.tag ? `${stamp} [${opts.tag}] ${event}\n` : `${stamp} ${event}\n`;
  appendFileSync(p, line);
  return p;
}

/**
 * Set what events on this inbox mean. Makes the inbox if it does not exist.
 *
 * The session reads the text at start, after every compaction, at the top of its
 * listener's stream, and again whenever it changes. {inbox} {name} {listen} {send}
 * {waiting} inside it are filled in at delivery. Written as one atomic swap.
 */
export function contract(session: string, text: string): string {
  const p = path(session);
  ensure(p, true);
  const tmp = `${p}.contract.tmp`;
  writeFileSync(tmp, text.endsWith("\n") ? text : `${text}\n`);
  renameSync(tmp, `${p}.contract`);
  return `${p}.contract`;
}
