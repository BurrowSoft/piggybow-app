// The staging run: one tip per made-up week
// (supabase/fixtures/tips-run.json) from piggybow-staging's pig-tip, with
// the model chosen for this run. Fixtures only, never anyone's data.
//
// 1. Notes tip_settings, then sets the run's model, switches tips on, lifts
//    the per-person limit and names no region (Management API, the scoped
//    token).
// 2. Signs in one anonymous user (the anon key). Around it, counts only,
//    never a value: Auth's sessions, those that keep an IP address (what
//    the idle users' deletion takes away), and Auth's audit log rows in the
//    database, which a sign-up must not add to ("Write audit logs to the
//    database" off).
// 3. Asks for a tip per week: the status, the tip or why there's none, the
//    model that answered and its tokens.
// 4. Reports one tip as given (kept), and with one character changed
//    (refused: its signature doesn't match).
// 5. Checks the region guard: a region the function can't be in, then the
//    one it ran in, pinned with x-region.
// 6. Whatever happened: tip_settings back as they were, and the run's user
//    forgotten.
// 7. Prints a table for the job's log, with an estimated cost, the reports'
//    two answers, the guard's, the forget's and the retention counts. Then
//    it fails (exit 1) unless every check held: at least 16 of the 20 weeks
//    got a tip and none a 5xx, each week 200 or 204; the reports 204 then
//    400; the guard 204 "region" away and 200 at home; the run's user
//    forgotten (204); and no Auth audit log row added.
//
//   SUPABASE_DEPLOY_TOKEN=… PROJECT_REF=… ANON_KEY=… MODEL=… deno run \
//     --allow-net --allow-read=supabase/fixtures \
//     --allow-env=SUPABASE_DEPLOY_TOKEN,PROJECT_REF,ANON_KEY,MODEL \
//     supabase/scripts/tips-run.ts

import fixtures from "../fixtures/tips-run.json" with { type: "json" };
import { runSql } from "./sql.ts";

/** $ per million tokens, input and output (list prices; Haiku's for
 * prompts up to 100K tokens). */
const PRICES: Record<string, [number, number]> = {
  "claude-haiku-5-5": [0.1, 0.5],
  "claude-sonnet-5-5": [2, 10],
};
const MODELS = Object.keys(PRICES);

const token = Deno.env.get("SUPABASE_DEPLOY_TOKEN") ?? "";
const ref = Deno.env.get("PROJECT_REF") ?? "";
const anon = Deno.env.get("ANON_KEY") ?? "";
const model = Deno.env.get("MODEL") ?? "";
if (!token || !ref || !anon || !MODELS.includes(model)) {
  console.error(`SUPABASE_DEPLOY_TOKEN, PROJECT_REF, ANON_KEY and MODEL (${MODELS.join(" or ")}) are needed`);
  Deno.exit(2);
}
const base = `https://${ref}.supabase.co`;

type Row = { week: string; status: number; text: string; sig: string; model: string; inp: number; out: number };

const before = (await runSql(
  ref,
  token,
  "select enabled, model, per_person_daily, region from public.tip_settings where id = 1",
)) as Array<Record<string, unknown>>;
const was = before[0] ?? {};
const wasModel = MODELS.includes(String(was.model)) ? String(was.model) : "claude-sonnet-5-5";
const wasEnabled = was.enabled === true;
const wasPerPerson = Number.isInteger(was.per_person_daily) ? Number(was.per_person_daily) : 1;
/** A region name as the settings allow it: only these go into the SQL. */
const REGION = /^[a-z0-9-]{1,40}$/;
const wasRegion = typeof was.region === "string" && REGION.test(was.region) ? `'${was.region}'` : "null";

// MODEL is one of two fixed names (checked above), so it's safe in the SQL.
// No region named while the weeks run: the runner's calls land anywhere.
await runSql(
  ref,
  token,
  `update public.tip_settings set model = '${model}', enabled = true, region = null, ` +
    `per_person_daily = ${fixtures.weeks.length + 5}, updated_at = now() where id = 1`,
);

const rows: Row[] = [];
const guard: string[] = [];
const reports: string[] = [];
const retention: string[] = [];
/** What didn't hold: any of these fails the run, after it's printed. */
const failures: string[] = [];
/** A confirmation needs most weeks to get a tip: 16 of the 20. */
const MIN_TIPS = 16;
let auditGrew = false;
let forgotten: number | null = null;
let access = "";
/** Counts only, never a value: Auth's sessions, those that keep an IP
 * address, and Auth's audit log rows in the database. */
const authCounts = async () => {
  const [c] = (await runSql(
    ref,
    token,
    "select (select count(*) from auth.sessions) as sessions, " +
      "(select count(ip) from auth.sessions) as with_ip, " +
      "(select count(*) from auth.audit_log_entries) as audit",
  )) as Array<Record<string, unknown>>;
  return { sessions: Number(c?.sessions), withIp: Number(c?.with_ip), audit: Number(c?.audit) };
};
const askTip = (request: unknown, extra: Record<string, string> = {}) =>
  fetch(`${base}/functions/v1/pig-tip`, {
    method: "POST",
    headers: {
      apikey: anon,
      Authorization: `Bearer ${access}`,
      "Content-Type": "application/json",
      ...extra,
    },
    body: JSON.stringify(request),
  });
try {
  const auth0 = await authCounts();
  const signup = await fetch(`${base}/auth/v1/signup`, {
    method: "POST",
    headers: { apikey: anon, "Content-Type": "application/json" },
    body: "{}",
  });
  if (!signup.ok) throw new Error(`anonymous sign-in: HTTP ${signup.status}`);
  access = String((await signup.json()).access_token ?? "");
  if (!access) throw new Error("anonymous sign-in: no access token");
  const auth1 = await authCounts();
  // Unreadable counts fail too: never "none added" unless counted.
  auditGrew = !(auth1.audit <= auth0.audit);
  const auditSaid = !auditGrew
    ? "none added, as it should be"
    : Number.isNaN(auth0.audit) || Number.isNaN(auth1.audit)
    ? "couldn't be counted"
    : 'grew: "Write audit logs to the database" is on';
  retention.push(
    `- Auth sessions: ${auth0.sessions} → ${auth1.sessions}; keeping an IP address: ` +
      `${auth0.withIp} → ${auth1.withIp} (what the idle users' deletion takes away).`,
    `- Auth audit log rows in the database: ${auth0.audit} → ${auth1.audit} (${auditSaid}).`,
  );
  // The daily jobs' runs so far, by status: counts only.
  const runs = (await runSql(
    ref,
    token,
    "select j.jobname, d.status, count(*) as runs from cron.job_run_details d " +
      "join cron.job j using (jobid) where j.jobname in ('pig-tips-clean-up', 'pig-tips-forget-idle') " +
      "group by j.jobname, d.status order by 1, 2",
  )) as Array<Record<string, unknown>>;
  retention.push(
    `- The daily jobs' runs: ${
      runs.map((r) => `${r.jobname} ${r.status} ${Number(r.runs)}`).join("; ") || "none yet"
    }.`,
  );

  for (const week of fixtures.weeks) {
    const res = await askTip(week.request);
    const usage = Object.fromEntries(
      (res.headers.get("x-tip-usage") ?? "")
        .split(";")
        .map((part) => part.split("="))
        .filter((kv) => kv.length === 2)
        .map(([k, v]) => [k, Number(v)]),
    );
    let text: string;
    let sig = "";
    if (res.status === 200) {
      const body = await res.json();
      text = String(body.tip ?? "");
      sig = String(body.sig ?? "");
    } else {
      await res.body?.cancel();
      text = `(no tip: ${res.headers.get("x-tip-why") ?? res.status})`;
    }
    rows.push({
      week: week.name,
      status: res.status,
      text,
      sig,
      model: res.headers.get("x-tip-model") ?? "",
      inp: usage.in ?? 0,
      out: usage.out ?? 0,
    });
  }

  const tipsGiven = rows.filter((r) => r.status === 200).length;
  const fiveHundreds = rows.filter((r) => r.status >= 500).length;
  const neither = rows.filter((r) => r.status !== 200 && r.status !== 204).map((r) => r.status);
  if (fiveHundreds > 0) failures.push(`${fiveHundreds} of the ${rows.length} weeks got a 5xx`);
  if (neither.length > 0) failures.push(`weeks answered neither 200 nor 204: ${neither.join(", ")}`);
  if (tipsGiven < MIN_TIPS) {
    failures.push(`${tipsGiven} tips out of ${rows.length}, fewer than ${MIN_TIPS}`);
  }

  // Reports, end to end: a tip as given, with its signature, is kept (204);
  // the same tip with one character changed is refused (400). The kept one
  // is the model's words for a made-up week, gone after 90 days.
  const shown = rows.find((r) => r.status === 200 && r.sig);
  if (shown) {
    const send = async (tip: string) => {
      const res = await fetch(`${base}/functions/v1/pig-tip/report`, {
        method: "POST",
        headers: { apikey: anon, Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
        body: JSON.stringify({ tip, reason: "other", model: shown.model, sig: shown.sig }),
      });
      await res.body?.cancel();
      return res.status;
    };
    const changed = shown.text.endsWith(".") ? `${shown.text.slice(0, -1)}!` : `${shown.text}.`;
    const kept = await send(shown.text);
    const refused = await send(changed);
    reports.push(`- Its own tip, as given: ${kept} (204 expected).`);
    reports.push(`- One character changed: ${refused} (400 expected).`);
    if (kept !== 204) failures.push(`a report of a tip as given: ${kept}, not 204`);
    if (refused !== 400) failures.push(`a report of a changed tip: ${refused}, not 400`);
  } else {
    failures.push("no tip to report, so the reports weren't checked");
  }

  // The region guard, end to end. A region the function can't be in gets no
  // tip, and the 204 says where it ran; pinned there with x-region, a tip
  // goes on as usual.
  await runSql(ref, token, "update public.tip_settings set region = 'nowhere-0' where id = 1");
  const away = await askTip(fixtures.weeks[0].request);
  await away.body?.cancel();
  const ranIn = away.headers.get("x-tip-region") ?? "";
  const awayWhy = away.headers.get("x-tip-why") ?? "none";
  guard.push(
    `- A region it can't be in: ${away.status}, why ${awayWhy}; ` +
      `it ran in ${ranIn || "?"} (the platform's x-sb-edge-region: ` +
      `${away.headers.get("x-sb-edge-region") ?? "?"}).`,
  );
  if (away.status !== 204 || awayWhy !== "region") {
    failures.push(`the guard, away: ${away.status} why ${awayWhy}, not 204 region`);
  }
  if (REGION.test(ranIn) && ranIn !== "unknown") {
    await runSql(ref, token, `update public.tip_settings set region = '${ranIn}' where id = 1`);
    const home = await askTip(fixtures.weeks[0].request, { "x-region": ranIn });
    await home.body?.cancel();
    guard.push(
      `- Its own region, pinned with x-region: ${home.status}, why ` +
        `${home.headers.get("x-tip-why") ?? "none"} (ran in ${home.headers.get("x-sb-edge-region") ?? "?"}).`,
    );
    if (home.status !== 200) failures.push(`the guard, at home: ${home.status}, not 200`);
  } else {
    failures.push(`the guard didn't say where it ran (${ranIn || "nothing"}), so home wasn't checked`);
  }
} finally {
  // Back as it was, whatever happened above.
  await runSql(
    ref,
    token,
    `update public.tip_settings set model = '${wasModel}', enabled = ${wasEnabled}, ` +
      `per_person_daily = ${wasPerPerson}, region = ${wasRegion}, updated_at = now() where id = 1`,
  );
  if (access) {
    const forget = await fetch(`${base}/functions/v1/pig-tip/forget`, {
      method: "POST",
      headers: { apikey: anon, Authorization: `Bearer ${access}` },
    });
    await forget.body?.cancel();
    forgotten = forget.status;
  }
}

const cell = (s: string) => s.replaceAll("|", "\\|").replaceAll("\n", " ");
let cost = 0;
for (const r of rows) {
  const [pin, pout] = PRICES[r.model] ?? PRICES[model];
  cost += (r.inp * pin + r.out * pout) / 1_000_000;
}
const tips = rows.filter((r) => r.status === 200).length;
console.log(`# Pig tips staging run: ${model}\n`);
console.log("| # | Week | Status | Tip | Model | In | Out |");
console.log("|---|---|---|---|---|---|---|");
rows.forEach((r, i) => {
  console.log(`| ${i + 1} | ${cell(r.week)} | ${r.status} | ${cell(r.text)} | ${r.model} | ${r.inp} | ${r.out} |`);
});
console.log(
  `\n${tips} tips out of ${rows.length}. Tokens: ${rows.reduce((s, r) => s + r.inp, 0)} in, ` +
    `${rows.reduce((s, r) => s + r.out, 0)} out. Estimated cost at list prices: $${cost.toFixed(4)}.`,
);
console.log(`\nReports:\n${reports.join("\n") || "- no tip to report"}`);
console.log(`\nThe region guard:\n${guard.join("\n") || "- not reached"}`);
console.log(
  `\ntip_settings put back: model ${wasModel}, enabled ${wasEnabled}, per person ${wasPerPerson}, ` +
    `region ${wasRegion}.`,
);
console.log(`\nRetention (counts only):\n${retention.join("\n") || "- not reached"}`);
console.log(`\nThe run's user forgotten: ${forgotten ?? "not asked"} (204 expected).`);
if (forgotten !== 204) failures.push(`the run's user forgotten: ${forgotten ?? "not asked"}, not 204`);
if (auditGrew) {
  failures.push(
    "Auth's audit log in the database grew with the sign-up, or couldn't be counted: turn off " +
      '"Write audit logs to the database" in the project\'s Auth settings',
  );
}
console.log(`\nChecks: ${failures.length === 0 ? "all held" : `${failures.length} failed`}`);
for (const f of failures) console.log(`- ${f}`);
if (failures.length > 0) Deno.exit(1);
