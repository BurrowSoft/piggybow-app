import fixtures from "../../fixtures/tips-run.json" with { type: "json" };
import { type Deps, type Filed, handle, type Report, type Take, type TipSettings } from "./handler.ts";
import type { ModelAnswer } from "./model.ts";
import { MIN_KEY_LENGTH, signerFor } from "./sign.ts";
import { assert, assertEquals } from "./test_util.ts";

const week = fixtures.weeks[1].request;
const UID = "anon-user-1";
const TIP = "Food led your week so far. A home-cooked dinner could be a nice change.";
const SIGNER = (await signerFor("k".repeat(MIN_KEY_LENGTH)))!;
const SIG = await SIGNER.sign("claude-haiku-5-5", TIP);

/** Fake deps that record their calls and the log lines. */
function fake(over: Partial<Deps> = {}) {
  const calls: string[] = [];
  const logs: Array<Record<string, unknown>> = [];
  const reports: Report[] = [];
  const deps: Deps = {
    userId: async (auth) => (auth === "Bearer good" ? UID : null),
    settings: async (): Promise<TipSettings | null> => ({ model: "claude-haiku-5-5", effort: "low", region: null }),
    admin: true,
    region: "us-east-1",
    signer: SIGNER,
    takeTip: async (uid, today): Promise<Take> => {
      calls.push(`take ${uid} ${today}`);
      return "ok";
    },
    ask: async (): Promise<ModelAnswer> => {
      calls.push("ask");
      return { ok: true, text: TIP, model: "claude-haiku-5-5", inputTokens: 612, outputTokens: 88 };
    },
    fileReport: async (uid, today, r): Promise<Filed> => {
      calls.push(`file ${uid} ${today}`);
      reports.push(r);
      return "ok";
    },
    forget: async (uid) => {
      calls.push(`forget ${uid}`);
    },
    today: () => "2026-12-02",
    log: (line) => logs.push(line),
    ...over,
  };
  return { deps, calls, logs, reports };
}

function post(path: string, body?: unknown, auth = "Bearer good"): Request {
  return new Request(`http://localhost${path}`, {
    method: "POST",
    headers: { Authorization: auth, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

/** Nothing the person sent, nor the tip, its signature or their id, ever
 * reaches a log. */
function assertQuietLogs(logs: Array<Record<string, unknown>>) {
  const text = JSON.stringify(logs);
  for (const secret of [UID, TIP, SIG, "category_shares", "feelings", "picks"]) {
    assert(!text.includes(secret), `the logs hold ${secret}`);
  }
}

Deno.test("a tip: 200 with the tip, its signature, its model and its tokens", async () => {
  const { deps, calls, logs } = fake();
  const res = await handle(post("/pig-tip", week), deps);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(Object.keys(body).sort(), ["sig", "tip"]);
  assertEquals(body.tip, TIP);
  assertEquals(body.sig, SIG);
  assert(await SIGNER.verify("claude-haiku-5-5", body.tip, body.sig));
  assertEquals(res.headers.get("x-tip-model"), "claude-haiku-5-5");
  assertEquals(res.headers.get("x-tip-usage"), "in=612;out=88");
  assertEquals(calls, [`take ${UID} 2026-12-02`, "ask"]);
  assertEquals(logs, [{ route: "tip", status: 200, model: "claude-haiku-5-5", in: 612, out: 88 }]);
  assertQuietLogs(logs);
});

Deno.test("401 without a signed-in anonymous user; 405 for anything but POST", async () => {
  const { deps, calls } = fake();
  assertEquals((await handle(post("/pig-tip", week, "Bearer bad"), deps)).status, 401);
  assertEquals((await handle(post("/pig-tip", week, ""), deps)).status, 401);
  assertEquals((await handle(new Request("http://localhost/pig-tip"), deps)).status, 405);
  assertEquals(calls, []);
});

Deno.test("400 for a body the contract refuses, before anything is counted", async () => {
  const { deps, calls, logs } = fake();
  for (const body of [{ ...week, note: "Lunch at the market" }, "not json", undefined]) {
    const res = await handle(post("/pig-tip", body), deps);
    assertEquals(res.status, 400);
    assertEquals(await res.json(), { code: "invalid_value" });
  }
  assertEquals(calls, []);
  assertQuietLogs(logs);
  assert(!JSON.stringify(logs).includes("market"));
});

Deno.test("204 when tips are off: nothing counted, no model asked", async () => {
  const { deps, calls, logs } = fake({ settings: async () => null });
  assertEquals((await handle(post("/pig-tip", week), deps)).status, 204);
  assertEquals(calls, []);
  assertEquals(logs, [{ route: "tip", status: 204, why: "off" }]);
});

Deno.test("204 outside the settings' region, or where the runtime says none", async () => {
  const inUS = { model: "claude-sonnet-5-5", effort: "low", region: "us-east-1" } as const;
  for (const where of ["ap-southeast-1", null]) {
    const { deps, calls, logs } = fake({ settings: async () => inUS, region: where });
    const res = await handle(post("/pig-tip", week), deps);
    assertEquals(res.status, 204, String(where));
    assertEquals(res.headers.get("x-tip-why"), "region");
    assertEquals(res.headers.get("x-tip-region"), where ?? "unknown");
    assertEquals(res.headers.get("x-tip-model"), null);
    assertEquals(calls, [], `nothing counted, no model asked: ${where}`);
    assertEquals(logs, [{ route: "tip", status: 204, why: "region", region: where ?? "unknown" }]);
    assertQuietLogs(logs);
  }
  // In its own region, or with no region named, the tip goes on as usual.
  for (const [named, where] of [["us-east-1", "us-east-1"], [null, "ap-southeast-1"]] as const) {
    const { deps } = fake({ settings: async () => ({ ...inUS, region: named }), region: where });
    assertEquals((await handle(post("/pig-tip", week), deps)).status, 200, `${named} ${where}`);
  }
});

Deno.test("503 without an admin key, on every route: no user looked up, nothing counted or deleted", async () => {
  const looked: Array<string | null> = [];
  const { deps, calls, logs, reports } = fake({
    admin: false,
    userId: async (auth) => {
      looked.push(auth);
      return UID;
    },
  });
  const good = { tip: TIP, reason: "other", model: "claude-haiku-5-5", sig: SIG };
  assertEquals((await handle(post("/pig-tip", week), deps)).status, 503);
  assertEquals((await handle(post("/pig-tip/report", good), deps)).status, 503);
  assertEquals((await handle(post("/pig-tip/forget"), deps)).status, 503);
  assertEquals(looked, []);
  assertEquals(calls, []);
  assertEquals(reports, []);
  assertEquals(logs, [
    { route: "tip", status: 503, why: "no_admin_key" },
    { route: "report", status: 503, why: "no_admin_key" },
    { route: "forget", status: 503, why: "no_admin_key" },
  ]);
});

Deno.test("503 without a signing key: no tip, nothing counted, no model asked, no report kept", async () => {
  const { deps, calls, logs, reports } = fake({ signer: null });
  assertEquals((await handle(post("/pig-tip", week), deps)).status, 503);
  assertEquals(calls, []);
  assertEquals(logs, [{ route: "tip", status: 503, why: "no_signing_key" }]);
  const good = { tip: TIP, reason: "other", model: "claude-haiku-5-5", sig: SIG };
  assertEquals((await handle(post("/pig-tip/report", good), deps)).status, 503);
  assertEquals(reports, []);
  assertEquals(calls, []);
});

Deno.test("204 at the daily cap, or with today's tip used: no model asked", async () => {
  for (const take of ["cap", "used", "off"] as const) {
    const { deps, calls, logs } = fake({ takeTip: async () => take });
    assertEquals((await handle(post("/pig-tip", week), deps)).status, 204, take);
    assert(!calls.includes("ask"), take);
    assertEquals(logs, [{ route: "tip", status: 204, why: take }]);
  }
});

Deno.test("204 when the model gives no tip, or the filter holds it back", async () => {
  const noTip = fake({
    ask: async () => ({ ok: false, why: "stop_refusal", model: "claude-haiku-5-5", inputTokens: 600, outputTokens: 3 }),
  });
  assertEquals((await handle(post("/pig-tip", week), noTip.deps)).status, 204);
  assertEquals(noTip.logs, [{ route: "tip", status: 204, why: "stop_refusal", model: "claude-haiku-5-5", in: 600, out: 3 }]);

  const guilty = "You overspent on fun this week.";
  const held = fake({
    ask: async () => ({ ok: true, text: guilty, model: "claude-sonnet-5-5", inputTokens: 610, outputTokens: 40 }),
  });
  const res = await handle(post("/pig-tip", week), held.deps);
  assertEquals(res.status, 204);
  assertEquals(held.logs, [{ route: "tip", status: 204, why: "filter_guilt", model: "claude-sonnet-5-5", in: 610, out: 40 }]);
  assert(!JSON.stringify(held.logs).includes(guilty));
  // Why, as a code, for the staging run; never the text.
  assertEquals(res.headers.get("x-tip-why"), "filter_guilt");
  assertEquals(res.headers.get("x-tip-model"), "claude-sonnet-5-5");
  assertEquals(res.headers.get("x-tip-usage"), "in=610;out=40");
  assertEquals(await res.text(), "");
});

Deno.test("no model headers on a 204 that never asked the model", async () => {
  const { deps } = fake({ takeTip: async () => "cap" });
  const res = await handle(post("/pig-tip", week), deps);
  assertEquals(res.status, 204);
  assertEquals(res.headers.get("x-tip-model"), null);
});

Deno.test("503 when the database fails, and the error's text isn't logged", async () => {
  const { deps, logs } = fake({
    takeTip: async () => {
      throw new Error(`connection to ${UID} failed`);
    },
  });
  assertEquals((await handle(post("/pig-tip", week), deps)).status, 503);
  assertEquals(logs, [{ route: "tip", status: 503, why: "Error" }]);
});

Deno.test("report: a tip this server gave, a reason and its model are kept; any other body is refused", async () => {
  const { deps, reports, calls, logs } = fake();
  const good = { tip: TIP, reason: "unhelpful", model: "claude-haiku-5-5", sig: SIG };
  assertEquals((await handle(post("/pig-tip/report", good), deps)).status, 204);
  assertEquals(reports, [{ tip: TIP, reason: "unhelpful", model: "claude-haiku-5-5" }]);
  assertEquals(calls, [`file ${UID} 2026-12-02`]);
  for (
    const bad of [
      { ...good, reason: "boring" },
      { ...good, model: "claude-opus-5-5" },
      { ...good, tip: "" },
      { ...good, tip: "a".repeat(161) },
      { ...good, week },
      { tip: TIP, reason: "wrong", model: "claude-haiku-5-5" },
      { ...good, sig: 42 },
    ]
  ) {
    const res = await handle(post("/pig-tip/report", bad), deps);
    assertEquals(res.status, 400, JSON.stringify(bad).slice(0, 60));
    assertEquals(await res.json(), { code: "invalid_value" });
  }
  assertEquals(reports.length, 1);
  assertEquals(logs[0], { route: "report", status: 204, reason: "unhelpful", model: "claude-haiku-5-5" });
  assertQuietLogs(logs);
});

Deno.test("report: a tip changed by one character, another model's, or a forged signature: refused, nothing kept", async () => {
  const { deps, reports, calls, logs } = fake();
  const good = { tip: TIP, reason: "wrong", model: "claude-haiku-5-5", sig: SIG };
  for (
    const bad of [
      { ...good, tip: TIP.replace("Food", "Fool") },
      { ...good, model: "claude-sonnet-5-5" },
      { ...good, sig: (SIG[0] === "A" ? "B" : "A") + SIG.slice(1) },
      { ...good, sig: "not-a-signature" },
    ]
  ) {
    const res = await handle(post("/pig-tip/report", bad), deps);
    assertEquals(res.status, 400);
    assertEquals(await res.json(), { code: "invalid_value" });
  }
  assertEquals(reports, []);
  assertEquals(calls, [], "never counted");
  assertEquals(logs.map((l) => l.why), ["bad_signature", "bad_signature", "bad_signature", "bad_signature"]);
  assertQuietLogs(logs);
});

Deno.test("report: over the day's caps, for everyone or for this person: 429, not kept", async () => {
  for (const filed of ["cap", "used"] as const) {
    const { deps, logs } = fake({ fileReport: async () => filed });
    const good = { tip: TIP, reason: "advice", model: "claude-haiku-5-5", sig: SIG };
    const res = await handle(post("/pig-tip/report", good), deps);
    assertEquals(res.status, 429, filed);
    assertEquals(await res.json(), { code: "rate_limited" });
    assertEquals(logs, [{ route: "report", status: 429, why: filed }]);
  }
});

Deno.test("forget: the caller's anonymous user is deleted", async () => {
  const { deps, calls, logs } = fake();
  assertEquals((await handle(post("/pig-tip/forget"), deps)).status, 204);
  assertEquals(calls, [`forget ${UID}`]);
  assertQuietLogs(logs);
  const stranger = fake();
  assertEquals((await handle(post("/pig-tip/forget", undefined, "Bearer bad"), stranger.deps)).status, 401);
  assertEquals(stranger.calls, []);
});
