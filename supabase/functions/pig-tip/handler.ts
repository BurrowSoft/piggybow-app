// The pig-tip function's routes, with everything it talks to passed in, so
// the tests need no network, no database and no key.
//
//   POST /pig-tip         a tip: 200 {tip, sig}, or 204 (no tip today: the
//                         app shows its own), 400 a body the contract refuses
//   POST /pig-tip/report  "Report this tip": 204 kept; 400 a bad body, or a
//                         tip this server didn't give; 429 over the day's caps
//   POST /pig-tip/forget  turning tips off: the anonymous user goes; 204
//
// Anonymous users only (401 otherwise). When the settings name a region,
// tips are made only there (where the runtime says the function runs).
// Every tip is signed, and a report is kept only with its tip's signature;
// without a signing key there are no tips (503). Each request logs one
// line: the route, the status and why, the model and its token counts.
// Never the request, the tip or the user's id.

import { validRequest, type TipRequest } from "./contract.ts";
import { checkTip, MAX_TIP_CHARS } from "./filter.ts";
import { isTipModel, type ModelAnswer, type ModelSettings } from "./model.ts";
import type { Signer } from "./sign.ts";

export type Take = "ok" | "off" | "cap" | "used";

/** A report's fate: kept, or over the day's cap for everyone or for this
 * person. */
export type Filed = "ok" | "cap" | "used";

export const REPORT_REASONS = ["unhelpful", "wrong", "upsetting", "advice", "other"] as const;
export type Report = { tip: string; reason: string; model: string };
const REPORT_KEYS = ["tip", "reason", "model", "sig"];

/** The model settings, and the one region tips may be made in (null: any). */
export type TipSettings = ModelSettings & { region: string | null };

export type Deps = {
  /** The caller's id when it's a signed-in anonymous user, else null. */
  userId(authorization: string | null): Promise<string | null>;
  /** The settings when tips are on, else null (the kill switch). */
  settings(): Promise<TipSettings | null>;
  /** Whether the function holds an admin key (keys.ts): without one nothing
   * can be checked, counted or deleted, and every route answers 503. */
  admin: boolean;
  /** The region this function runs in, as the runtime says (null: unsaid). */
  region: string | null;
  /** Signs the tips given and checks the reports' (null: no key). */
  signer: Signer | null;
  /** One tip for [uid] today (UTC): counted when 'ok'. */
  takeTip(uid: string, today: string): Promise<Take>;
  ask(request: TipRequest, settings: ModelSettings): Promise<ModelAnswer>;
  /** Keeps [report] for [uid] today (UTC) within the caps: 'ok' when kept.
   * The report itself keeps no one's id. */
  fileReport(uid: string, today: string, report: Report): Promise<Filed>;
  /** Deletes the anonymous user; their counters go with them. */
  forget(uid: string): Promise<void>;
  /** Today in UTC, YYYY-MM-DD. */
  today(): string;
  log(line: Record<string, unknown>): void;
};

function noTip(headers: Record<string, string> = {}): Response {
  return new Response(null, { status: 204, headers });
}

/** After the model was asked: which model, its tokens, and why no tip went
 * out (a code, never the text). The staging run reads them. */
function modelHeaders(model: string, usage: { in: number; out: number }, why?: string) {
  return {
    "x-tip-model": model,
    "x-tip-usage": `in=${usage.in};out=${usage.out}`,
    ...(why ? { "x-tip-why": why } : {}),
  };
}

function json(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });
}

async function bodyOf(req: Request): Promise<unknown> {
  try {
    return await req.json();
  } catch {
    return undefined;
  }
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const path = new URL(req.url).pathname;
  const route = path.endsWith("/report") ? "report" : path.endsWith("/forget") ? "forget" : "tip";
  const log = (line: Record<string, unknown>) => deps.log({ route, ...line });

  if (req.method !== "POST") {
    log({ status: 405 });
    return new Response(null, { status: 405 });
  }
  if (!deps.admin) {
    log({ status: 503, why: "no_admin_key" });
    return new Response(null, { status: 503 });
  }
  try {
    const uid = await deps.userId(req.headers.get("Authorization"));
    if (uid === null) {
      log({ status: 401 });
      return new Response(null, { status: 401 });
    }
    if (route === "forget") {
      await deps.forget(uid);
      log({ status: 204 });
      return noTip();
    }
    if (route === "report") return await report(req, uid, deps, log);
    return await tip(req, uid, deps, log);
  } catch (error) {
    log({ status: 503, why: whyOf(error) });
    return new Response(null, { status: 503 });
  }
}

/** Why something failed, for the log: the error's name and, when it has a
 * short code (Postgres' 42501, PostgREST's PGRST301…), that code. Never its
 * message, which can quote data. */
function whyOf(error: unknown): string {
  const name = error instanceof Error ? error.name : "error";
  const code = typeof error === "object" && error !== null ? (error as { code?: unknown }).code : undefined;
  return typeof code === "string" && /^[A-Za-z0-9_]{1,16}$/.test(code) ? `${name}:${code}` : name;
}

/** No signing key: the server can't give a tip a report could prove. */
function noKey(log: (line: Record<string, unknown>) => void): Response {
  log({ status: 503, why: "no_signing_key" });
  return new Response(null, { status: 503 });
}

async function tip(
  req: Request,
  uid: string,
  deps: Deps,
  log: (line: Record<string, unknown>) => void,
): Promise<Response> {
  const request = validRequest(await bodyOf(req));
  if (request === null) {
    log({ status: 400, why: "invalid_value" });
    return json(400, { code: "invalid_value" });
  }
  const settings = await deps.settings();
  if (settings === null) {
    log({ status: 204, why: "off" });
    return noTip();
  }
  // Outside the settings' region (or nowhere said): no tip, nothing
  // counted, no model asked. The app pins the region, so this is a guard.
  if (settings.region !== null && deps.region !== settings.region) {
    const where = deps.region ?? "unknown";
    log({ status: 204, why: "region", region: where });
    return noTip({ "x-tip-why": "region", "x-tip-region": where });
  }
  // Before anything is counted or asked.
  const signer = deps.signer;
  if (signer === null) return noKey(log);
  const take = await deps.takeTip(uid, deps.today());
  if (take !== "ok") {
    log({ status: 204, why: take });
    return noTip();
  }
  const answer = await deps.ask(request, settings);
  const usage = { in: answer.inputTokens ?? 0, out: answer.outputTokens ?? 0 };
  if (!answer.ok) {
    const model = answer.model ?? settings.model;
    log({ status: 204, why: answer.why, model, ...usage });
    return noTip(modelHeaders(model, usage, answer.why));
  }
  const verdict = checkTip(answer.text);
  if (!verdict.ok) {
    const why = `filter_${verdict.why}`;
    log({ status: 204, why, model: answer.model, ...usage });
    return noTip(modelHeaders(answer.model, usage, why));
  }
  // The app keeps the signature with the tip, for a report.
  const sig = await signer.sign(answer.model, verdict.tip);
  log({ status: 200, model: answer.model, ...usage });
  return json(200, { tip: verdict.tip, sig }, modelHeaders(answer.model, usage));
}

async function report(
  req: Request,
  uid: string,
  deps: Deps,
  log: (line: Record<string, unknown>) => void,
): Promise<Response> {
  const body = await bodyOf(req);
  const ok = typeof body === "object" && body !== null && !Array.isArray(body) &&
    Object.keys(body).every((k) => REPORT_KEYS.includes(k));
  const { tip, reason, model, sig } = (ok ? body : {}) as Record<string, unknown>;
  if (
    !ok ||
    typeof tip !== "string" || tip.length < 1 || tip.length > MAX_TIP_CHARS ||
    typeof reason !== "string" || !(REPORT_REASONS as readonly string[]).includes(reason) ||
    !isTipModel(model) ||
    typeof sig !== "string"
  ) {
    log({ status: 400, why: "invalid_value" });
    return json(400, { code: "invalid_value" });
  }
  const signer = deps.signer;
  if (signer === null) return noKey(log);
  // Only a tip this server gave, word for word: never text a client made up.
  if (!(await signer.verify(model, tip, sig))) {
    log({ status: 400, why: "bad_signature" });
    return json(400, { code: "invalid_value" });
  }
  const filed = await deps.fileReport(uid, deps.today(), { tip, reason, model });
  if (filed !== "ok") {
    log({ status: 429, why: filed });
    return json(429, { code: "rate_limited" });
  }
  log({ status: 204, reason, model });
  return noTip();
}
