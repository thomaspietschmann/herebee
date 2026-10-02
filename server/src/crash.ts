/**
 * POST /api/crash — opt-in crash reports, mailed to the operator.
 *
 * The Android app sends a report here only after the user agreed in ACRA's
 * dialog (see mobile/android/app/src/main/kotlin/app/herebee/). The body is a
 * small JSON object with a fixed set of fields; everything in it is untrusted.
 * It is turned into a plain-text email and forgotten: nothing is stored, and
 * neither the report nor the sender's IP is logged. The IP is held in memory
 * only for the per-IP rate-limit window.
 */
import type { IncomingMessage, ServerResponse } from "node:http";
import nodemailer from "nodemailer";
import { z } from "zod";

/** Request body limit. A capped stack trace plus a comment fit comfortably. */
export const MAX_BODY_BYTES = 64 * 1024;

const short = z.string().max(200);

/**
 * Exactly the fields the apps send: Android's native crashes through ACRA
 * (HereBeeReportSender.buildPayload), Dart errors on both platforms through
 * mobile/lib/core/crash_reporter.dart.
 */
export const crashReportSchema = z
  .object({
    platform: z.enum(["android", "ios", "web"]).optional(),
    /** "native" for an ACRA report, "dart" for an uncaught Dart error. */
    source: z.enum(["native", "dart"]).optional(),
    /** OS name and version where androidVersion does not apply (iOS). */
    osVersion: short.optional(),
    reportId: short.optional(),
    appVersionCode: short.optional(),
    appVersionName: short.optional(),
    packageName: short.optional(),
    androidVersion: short.optional(),
    brand: short.optional(),
    phoneModel: short.optional(),
    stackTrace: z.string().min(1).max(32_000),
    stackTraceHash: short.optional(),
    userComment: z.string().max(2_000).optional(),
    crashDate: short.optional(),
  })
  .strict();

export type CrashReport = z.infer<typeof crashReportSchema>;

/** Validates a parsed JSON value. Returns null for anything that is not a report. */
export function parseCrashReport(value: unknown): CrashReport | null {
  const parsed = crashReportSchema.safeParse(value);
  return parsed.success ? parsed.data : null;
}

/** One line, no control characters (so no CR/LF header injection), capped. */
export function oneLine(s: string, max = 200): string {
  // eslint-disable-next-line no-control-regex
  const flat = s.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]+/g, " ").replace(/\s+/g, " ").trim();
  return flat.length > max ? flat.slice(0, max - 1) + "\u2026" : flat;
}

/** Multi-line text with every control character except newline and tab removed. */
function multiLine(s: string): string {
  // eslint-disable-next-line no-control-regex
  return s.replace(/\r\n?/g, "\n").replace(/[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/g, "");
}

export function crashSubject(r: CrashReport): string {
  const version = r.appVersionName ? `${r.appVersionName}${r.appVersionCode ? ` (${r.appVersionCode})` : ""}` : "?";
  const firstLine = r.stackTrace.split(/\r?\n/, 1)[0] ?? "";
  const tag = r.source === "dart" ? "[HereBee Dart error]" : "[HereBee crash]";
  return oneLine(`${tag} ${oneLine(version, 60)} ${firstLine}`, 180);
}

export function crashBody(r: CrashReport): string {
  const rows: [string, string | undefined][] = [
    ["Platform", r.platform],
    ["Source", r.source],
    ["OS", r.osVersion],
    ["Report id", r.reportId],
    ["App version", r.appVersionName],
    ["Version code", r.appVersionCode],
    ["Package", r.packageName],
    ["Android", r.androidVersion],
    ["Brand", r.brand],
    ["Model", r.phoneModel],
    ["Crash date", r.crashDate],
    ["Trace hash", r.stackTraceHash],
  ];
  const head = rows
    .filter(([, v]) => v !== undefined && v !== "")
    .map(([k, v]) => `${k}: ${oneLine(v as string)}`)
    .join("\n");
  const comment = r.userComment?.trim() ? multiLine(r.userComment.trim()) : "(none)";
  return `${head}\n\nUser comment:\n${comment}\n\nStack trace:\n${multiLine(r.stackTrace)}\n`;
}

/** The part of a nodemailer transport this module uses; a fake in tests. */
export interface MailTransport {
  sendMail(mail: { from: string; to: string; subject: string; text: string }): Promise<unknown>;
}

export interface CrashHandlerOptions {
  /** null: mail is not configured, the endpoint answers 503. */
  transport: MailTransport | null;
  mailTo: string;
  mailFrom: string;
  /** Reports accepted per IP per window. */
  perIpLimit?: number;
  /** Mails sent in total per window, so the endpoint cannot flood the mailbox. */
  globalLimit?: number;
  windowMs?: number;
  now?: () => number;
}

export type CrashHandler = (req: IncomingMessage, res: ServerResponse, ip: string) => void;

const HOUR = 60 * 60 * 1000;

export function createCrashHandler(opts: CrashHandlerOptions): CrashHandler {
  const perIpLimit = opts.perIpLimit ?? 5;
  const globalLimit = opts.globalLimit ?? 30;
  const windowMs = opts.windowMs ?? HOUR;
  const now = opts.now ?? Date.now;
  const perIp = new Map<string, { start: number; count: number }>();
  let global = { start: now(), count: 0 };

  function takeIpSlot(ip: string): boolean {
    const t = now();
    if (perIp.size > 10_000) {
      for (const [k, e] of perIp) if (t - e.start >= windowMs) perIp.delete(k);
    }
    const e = perIp.get(ip);
    if (!e || t - e.start >= windowMs) {
      perIp.set(ip, { start: t, count: 1 });
      return true;
    }
    e.count += 1;
    return e.count <= perIpLimit;
  }

  function takeGlobalSlot(): boolean {
    const t = now();
    if (t - global.start >= windowMs) global = { start: t, count: 0 };
    if (global.count >= globalLimit) return false;
    global.count += 1;
    return true;
  }

  const reply = (res: ServerResponse, status: number, text?: string): void => {
    if (text === undefined) {
      res.writeHead(status).end();
      return;
    }
    res.writeHead(status, { "Content-Type": "text/plain; charset=utf-8" }).end(text);
  };

  return (req, res, ip) => {
    if (req.method !== "POST") {
      res.setHeader("Allow", "POST");
      reply(res, 405, "Method not allowed");
      req.resume();
      return;
    }
    if (!opts.transport) {
      reply(res, 503, "Crash reports are not configured");
      req.resume();
      return;
    }
    const type = (req.headers["content-type"] ?? "").split(";")[0].trim().toLowerCase();
    if (type !== "application/json") {
      reply(res, 415, "Expected application/json");
      req.resume();
      return;
    }
    const declared = Number(req.headers["content-length"] ?? "0");
    if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
      reply(res, 413, "Too large");
      req.resume();
      return;
    }
    if (!takeIpSlot(ip)) {
      reply(res, 429, "Too many reports");
      req.resume();
      return;
    }

    const chunks: Buffer[] = [];
    let size = 0;
    let done = false;
    req.on("data", (chunk: Buffer) => {
      if (done) return;
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        done = true;
        reply(res, 413, "Too large");
        return;
      }
      chunks.push(chunk);
    });
    req.on("error", () => {
      done = true;
    });
    req.on("end", () => {
      if (done) return;
      done = true;
      let report: CrashReport | null = null;
      try {
        report = parseCrashReport(JSON.parse(Buffer.concat(chunks).toString("utf8")));
      } catch {
        report = null;
      }
      if (!report) {
        reply(res, 400, "Invalid report");
        return;
      }
      if (!takeGlobalSlot()) {
        reply(res, 429, "Too many reports");
        return;
      }
      opts.transport!
        .sendMail({ from: opts.mailFrom, to: opts.mailTo, subject: crashSubject(report), text: crashBody(report) })
        .then(
          () => reply(res, 204),
          (err: unknown) => {
            // The error only, never the report or the client.
            console.error("crash mail failed:", err instanceof Error ? err.message : String(err));
            reply(res, 502, "Could not deliver the report");
          }
        );
    });
  };
}

export const DEFAULT_CRASH_MAIL_TO = "thomas@pietschie.de";

/**
 * Reads the mail settings: SMTP_URL (a nodemailer connection URL such as
 * smtps://user:pass@mail.example.org:465), CRASH_MAIL_TO, CRASH_MAIL_FROM.
 * Without SMTP_URL the endpoint is off (503) and the server runs as usual.
 */
export function crashOptionsFromEnv(env: NodeJS.ProcessEnv = process.env): CrashHandlerOptions {
  const url = (env.SMTP_URL ?? "").trim();
  const mailTo = (env.CRASH_MAIL_TO ?? "").trim() || DEFAULT_CRASH_MAIL_TO;
  let mailFrom = (env.CRASH_MAIL_FROM ?? "").trim();
  if (!url) return { transport: null, mailTo, mailFrom: mailFrom || mailTo };
  if (!mailFrom) {
    // Most providers only relay mail from the authenticated account.
    try {
      const user = decodeURIComponent(new URL(url).username);
      mailFrom = user.includes("@") ? user : mailTo;
    } catch {
      mailFrom = mailTo;
    }
  }
  // Created lazily by nodemailer: no connection is opened until a report is sent,
  // so a wrong SMTP_URL never keeps the server from starting.
  const transport = nodemailer.createTransport({
    url,
    connectionTimeout: 15_000,
    greetingTimeout: 15_000,
    socketTimeout: 30_000,
  });
  return { transport, mailTo, mailFrom: mailFrom.includes("<") ? mailFrom : `HereBee <${mailFrom}>` };
}
