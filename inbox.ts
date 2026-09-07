// inbox — send events to a Claude Code session from Node/TypeScript.
//
//     import { send, contract, status } from "./inbox";
//     contract("jobs-1", readFileSync("worker.contract", "utf8"));   // what the events will mean
//     send("jobs-1", "done 3 /tmp/out", { tag: "job" });             // an event
//     status("jobs-1").listener;                                     // pid of the session's listener, or null
//
// An inbox is a file under $CLAUDE_INBOX_DIR (default /tmp/claude-inbox). Sending an
// event is appending one line, so this uses only Node built-ins and never blocks. A
// session receives events only while it is listening (/inbox); events sent before that
// wait in the file.

import { appendFileSync, closeSync, existsSync, lstatSync, mkdirSync, openSync, readFileSync, realpathSync, renameSync, writeFileSync } from "node:fs";
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
  if (event === "") return p; // like the CLI: an empty event is not an event; the inbox still gets made
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

export interface Status {
  /** the inbox file */
  path: string;
  /** pid of the live listener, or null: events queue until one is up */
  listener: number | null;
  /** events the listener has passed on */
  delivered: number;
  /** events in the file not yet delivered */
  waiting: number;
  /** the contract file that applies, or null: default text */
  contract: string | null;
}

/** What the CLI's `inbox status` shows. Throws if there is no inbox. */
export function status(session: string): Status {
  const p = path(session);
  if (!existsSync(p)) throw new Error(`no inbox at ${p}`);
  const text = readFileSync(p, "utf8");
  const total = text.length === 0 ? 0 : text.split("\n").length - (text.endsWith("\n") ? 1 : 0);
  let seen = 0;
  try {
    seen = parseInt(readFileSync(`${p}.seen`, "utf8").trim(), 10) || 0;
  } catch {
    /* no cursor yet */
  }
  if (seen > total) seen = 0;
  let listener: number | null = null;
  try {
    const pid = parseInt(readFileSync(`${p}.listener`, "utf8").trim(), 10);
    process.kill(pid, 0);
    listener = pid;
  } catch {
    /* no listener, or not ours */
  }
  let contract: string | null = null;
  if (existsSync(`${p}.contract`)) contract = `${p}.contract`;
  else if (process.env.INBOX_CONTRACT && existsSync(process.env.INBOX_CONTRACT)) contract = process.env.INBOX_CONTRACT;
  return { path: p, listener, delivered: seen, waiting: total - seen, contract };
}
