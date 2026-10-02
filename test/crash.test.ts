/**
 * POST /api/crash: input validation, subject sanitizing, limits and status
 * codes, against a real HTTP server on an ephemeral port with a fake mail
 * transport. No SMTP, no network beyond loopback.
 *
 * Run: npm run test:crash
 */
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import {
  MAX_BODY_BYTES,
  crashBody,
  crashOptionsFromEnv,
  crashSubject,
  createCrashHandler,
  parseCrashReport,
  type MailTransport,
} from "../server/src/crash.js";

let failures = 0;
let checks = 0;
const check = (cond: boolean, msg: string): void => {
  checks++;
  if (!cond) {
    failures++;
    console.log(`✗ ${msg}`);
  }
};

const valid = {
  platform: "android",
  reportId: "8d1c0f3e-1",
  appVersionCode: "16",
  appVersionName: "0.0.16",
  packageName: "app.herebee",
  androidVersion: "16",
  brand: "google",
  phoneModel: "Pixel 9",
  stackTrace: "java.lang.IllegalStateException: boom\n\tat app.herebee.MainActivity.onCreate(MainActivity.kt:12)\n",
  stackTraceHash: "abc123",
  userComment: "tapped share",
  crashDate: "2026-10-02T18:00:00.000+02:00",
};

// --- parsing --------------------------------------------------------------
check(parseCrashReport(valid) !== null, "a complete report parses");
check(parseCrashReport({ stackTrace: "x" }) !== null, "only stackTrace is required");
check(parseCrashReport({ ...valid, stackTrace: "" }) === null, "empty stackTrace is rejected");
check(parseCrashReport({ ...valid, logcat: "..." }) === null, "unknown fields are rejected");
check(parseCrashReport({ ...valid, brand: "x".repeat(201) }) === null, "short fields are length-capped");
check(parseCrashReport({ ...valid, stackTrace: "x".repeat(32_001) }) === null, "stackTrace is length-capped");
check(parseCrashReport({ ...valid, userComment: "x".repeat(2_001) }) === null, "comment is length-capped");
check(parseCrashReport({ ...valid, appVersionCode: 16 }) === null, "non-string fields are rejected");
check(parseCrashReport([valid]) === null, "an array is rejected");
check(parseCrashReport({ ...valid, platform: "symbian" }) === null, "unknown platform is rejected");

// A Dart error report as mobile/lib/core/crash_reporter.dart sends it.
const dart = {
  platform: "ios",
  source: "dart",
  appVersionName: "0.0.16",
  osVersion: "ios Version 26.0 (Build 23A340)",
  stackTrace: "StateError: Bad state: boom\n#0 main (package:herebee/main.dart:1:1)",
  crashDate: "2026-10-02T12:00:00.000Z",
};
check(parseCrashReport(dart) !== null, "a Dart error report parses");
check(parseCrashReport({ ...dart, source: "js" }) === null, "unknown source is rejected");
check(crashSubject(dart as never).startsWith("[HereBee Dart error] 0.0.16 StateError"), `Dart subject: ${crashSubject(dart as never)}`);
check(crashBody(dart as never).includes("Source: dart") && crashBody(dart as never).includes("OS: ios Version 26.0"), "Dart body names source and OS");

// --- subject / body -------------------------------------------------------
const subject = crashSubject(valid as never);
check(subject === "[HereBee crash] 0.0.16 (16) java.lang.IllegalStateException: boom", `subject format: ${subject}`);
const evil = crashSubject({
  ...valid,
  appVersionName: "1\r\nBcc: victim@example.org",
  stackTrace: "Boom\u2028X-Injected: 1\rmore\nsecond line",
} as never);
check(!/[\r\n\u2028\u2029]/.test(evil), "subject has no CR/LF/line separators");
check(evil.includes("Boom X-Injected: 1 more") && !evil.includes("second line"), `subject is the first line only: ${evil}`);
check(crashSubject({ ...valid, stackTrace: "E".repeat(1000) } as never).length <= 180, "subject is capped");
const body = crashBody({ ...valid, userComment: "a\u0000b\r\nc" } as never);
check(body.includes("Model: Pixel 9") && body.includes("User comment:\nab\nc"), "body has fields, control chars stripped");
check(!body.includes("\r"), "body uses LF only");

// --- env ------------------------------------------------------------------
const off = crashOptionsFromEnv({});
check(off.transport === null && off.mailTo === "thomas@pietschie.de", "no SMTP_URL: endpoint off, default recipient");
const on = crashOptionsFromEnv({ SMTP_URL: "smtps://crash%40example.org:pw@mail.example.org:465", CRASH_MAIL_TO: "ops@example.org" });
check(on.transport !== null && on.mailFrom === "HereBee <crash@example.org>" && on.mailTo === "ops@example.org", `from defaults to the SMTP user: ${on.mailFrom}`);
const named = crashOptionsFromEnv({ SMTP_URL: "smtp://mail.example.org", CRASH_MAIL_FROM: "Bee <bee@example.org>" });
check(named.mailFrom === "Bee <bee@example.org>", "explicit From with a display name is kept");

// --- HTTP -----------------------------------------------------------------
type Mail = { from: string; to: string; subject: string; text: string };

async function withServer(
  transport: MailTransport | null,
  fn: (url: string) => Promise<void>,
  limits: { perIpLimit?: number; globalLimit?: number } = {}
): Promise<void> {
  const handler = createCrashHandler({ transport, mailTo: "ops@example.org", mailFrom: "HereBee <bee@example.org>", ...limits });
  const server: Server = createServer((req, res) => handler(req, res, "203.0.113.7"));
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  const { port } = server.address() as AddressInfo;
  try {
    await fn(`http://127.0.0.1:${port}/api/crash`);
  } finally {
    await new Promise<void>((r) => server.close(() => r()));
  }
}

const post = (url: string, body: string, type = "application/json") =>
  fetch(url, { method: "POST", headers: { "Content-Type": type }, body });

async function main(): Promise<void> {
  const sent: Mail[] = [];
  const fake: MailTransport = {
    sendMail: async (m) => {
      sent.push(m);
    },
  };

  await withServer(null, async (url) => {
    check((await post(url, JSON.stringify(valid))).status === 503, "503 without mail config");
  });

  await withServer(fake, async (url) => {
    check((await fetch(url)).status === 405, "GET is 405");
    check((await post(url, JSON.stringify(valid), "text/plain")).status === 415, "non-JSON content type is 415");
    check((await post(url, "{not json")).status === 400, "malformed JSON is 400");
    check((await post(url, JSON.stringify({ ...valid, extra: 1 }))).status === 400, "unknown field is 400");
  });

  await withServer(fake, async (url) => {
    const big = JSON.stringify({ ...valid, stackTrace: "x".repeat(MAX_BODY_BYTES) });
    check((await post(url, big)).status === 413, "oversized body is 413");

    const ok = await post(url, JSON.stringify(valid), "application/json; charset=utf-8");
    check(ok.status === 204, `valid report is 204 (got ${ok.status})`);
    const mail = sent.at(-1);
    check(mail?.to === "ops@example.org" && mail.from === "HereBee <bee@example.org>", "mail goes to the configured recipient");
    check(mail?.subject === crashSubject(valid as never) && mail.text.includes("tapped share"), "mail carries subject and body");
  });

  await withServer(
    fake,
    async (url) => {
      const codes: number[] = [];
      for (let i = 0; i < 4; i++) codes.push((await post(url, JSON.stringify(valid))).status);
      check(codes.join(",") === "204,204,429,429", `per-IP limit (got ${codes.join(",")})`);
    },
    { perIpLimit: 2 }
  );

  await withServer(
    fake,
    async (url) => {
      const codes: number[] = [];
      for (let i = 0; i < 3; i++) codes.push((await post(url, JSON.stringify(valid))).status);
      check(codes.join(",") === "204,429,429", `global hourly cap (got ${codes.join(",")})`);
    },
    { globalLimit: 1 }
  );

  const failing: MailTransport = { sendMail: async () => Promise.reject(new Error("smtp down")) };
  const origError = console.error;
  console.error = () => {};
  await withServer(failing, async (url) => {
    check((await post(url, JSON.stringify(valid))).status === 502, "SMTP failure is 502");
  });
  console.error = origError;

  console.log(`${checks - failures}/${checks} crash endpoint checks passed`);
  if (failures) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
