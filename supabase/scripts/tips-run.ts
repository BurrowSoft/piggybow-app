// The staging run: one tip per made-up week
// (supabase/fixtures/tips-run.json) from piggybow-staging's pig-tip, with
// the model chosen for this run. Fixtures only, never anyone's data.
//
// 1. Notes tip_settings, then sets the run's model, switches tips on and
//    lifts the per-person limit (Management API, the scoped token).
// 2. Signs in one anonymous user (the anon key).
// 3. Asks for a tip per week: the status, the tip or why there's none, the
//    model that answered and its tokens.
// 4. Whatever happened: tip_settings back as they were, and the run's user
//    forgotten.
// 5. Prints a table for the job's log, with an estimated cost.
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

type Row = { week: string; status: number; text: string; model: string; inp: number; out: number };

const before = (await runSql(
  ref,
  token,
  "select enabled, model, per_person_daily from public.tip_settings where id = 1",
)) as Array<Record<string, unknown>>;
const was = before[0] ?? {};
const wasModel = MODELS.includes(String(was.model)) ? String(was.model) : "claude-sonnet-5-5";
const wasEnabled = was.enabled === true;
const wasPerPerson = Number.isInteger(was.per_person_daily) ? Number(was.per_person_daily) : 1;

// MODEL is one of two fixed names (checked above), so it's safe in the SQL.
await runSql(
  ref,
  token,
  `update public.tip_settings set model = '${model}', enabled = true, ` +
    `per_person_daily = ${fixtures.weeks.length + 5}, updated_at = now() where id = 1`,
);

const rows: Row[] = [];
let access = "";
try {
  const signup = await fetch(`${base}/auth/v1/signup`, {
    method: "POST",
    headers: { apikey: anon, "Content-Type": "application/json" },
    body: "{}",
  });
  if (!signup.ok) throw new Error(`anonymous sign-in: HTTP ${signup.status}`);
  access = String((await signup.json()).access_token ?? "");
  if (!access) throw new Error("anonymous sign-in: no access token");

  for (const week of fixtures.weeks) {
    const res = await fetch(`${base}/functions/v1/pig-tip`, {
      method: "POST",
      headers: {
        apikey: anon,
        Authorization: `Bearer ${access}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(week.request),
    });
    const usage = Object.fromEntries(
      (res.headers.get("x-tip-usage") ?? "")
        .split(";")
        .map((part) => part.split("="))
        .filter((kv) => kv.length === 2)
        .map(([k, v]) => [k, Number(v)]),
    );
    let text: string;
    if (res.status === 200) {
      text = String((await res.json()).tip ?? "");
    } else {
      await res.body?.cancel();
      text = `(no tip: ${res.headers.get("x-tip-why") ?? res.status})`;
    }
    rows.push({
      week: week.name,
      status: res.status,
      text,
      model: res.headers.get("x-tip-model") ?? "",
      inp: usage.in ?? 0,
      out: usage.out ?? 0,
    });
  }
} finally {
  // Back as it was, whatever happened above.
  await runSql(
    ref,
    token,
    `update public.tip_settings set model = '${wasModel}', enabled = ${wasEnabled}, ` +
      `per_person_daily = ${wasPerPerson}, updated_at = now() where id = 1`,
  );
  if (access) {
    const forget = await fetch(`${base}/functions/v1/pig-tip/forget`, {
      method: "POST",
      headers: { apikey: anon, Authorization: `Bearer ${access}` },
    });
    await forget.body?.cancel();
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
console.log(`tip_settings put back: model ${wasModel}, enabled ${wasEnabled}, per person ${wasPerPerson}.`);
