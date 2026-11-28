import fixtures from "../../fixtures/tips-run.json" with { type: "json" };
import { validRequest } from "./contract.ts";
import { askModel, isTipModel, MAX_TOKENS, type Reply, tipParams } from "./model.ts";
import { SYSTEM_PROMPT, TIP_SCHEMA, userTurn } from "./prompt.ts";
import { assert, assertEquals } from "./test_util.ts";

// The week as the function sees it: through the contract's own check.
const checked = validRequest(fixtures.weeks[1].request);
if (!checked) throw new Error("the second staging week breaks the contract");
const week = checked;
const haiku = { model: "claude-haiku-5-5", effort: "low" } as const;
const sonnet = { model: "claude-sonnet-5-5", effort: "low" } as const;

Deno.test("the request: the prompt, the week, effort and {tip}, and nothing else", () => {
  const p = tipParams(week, haiku);
  assertEquals(Object.keys(p).sort(), ["max_tokens", "messages", "model", "output_config", "system"]);
  assertEquals(p.model, "claude-haiku-5-5");
  assertEquals(p.max_tokens, MAX_TOKENS);
  assertEquals(p.system, SYSTEM_PROMPT);
  assertEquals(p.messages, [{ role: "user", content: userTurn(week) }]);
  assertEquals(p.output_config, {
    effort: "low",
    format: { type: "json_schema", schema: TIP_SCHEMA },
  });
});

Deno.test("the user's turn is the week exactly as the app sent it", () => {
  assertEquals(userTurn(week), `This week so far: ${JSON.stringify(week)}`);
});

Deno.test("Sonnet 5.5 asks for Anthropic's refusal fallback; Haiku 5.5 has none", () => {
  const s = tipParams(week, sonnet);
  assertEquals(s.betas, ["server-side-fallback-2026-07-01"]);
  assertEquals(s.fallbacks, "default");
  const h = tipParams(week, haiku);
  assert(!("betas" in h) && !("fallbacks" in h));
});

Deno.test("only the two models", () => {
  assert(isTipModel("claude-haiku-5-5") && isTipModel("claude-sonnet-5-5"));
  for (const m of ["claude-opus-5-5", "", null, 1]) assert(!isTipModel(m), String(m));
});

function reply(r: Partial<Reply>): Reply {
  return {
    model: "claude-haiku-5-5",
    stop_reason: "end_turn",
    content: [],
    usage: { input_tokens: 600, output_tokens: 90 },
    ...r,
  };
}

function ask(answer: Reply | Error) {
  return askModel(async () => {
    if (answer instanceof Error) throw answer;
    return answer;
  }, week, haiku);
}

Deno.test("the tip, read after a thinking block, with the model and tokens", async () => {
  const content = [{ type: "thinking" }, { type: "text", text: '{"tip":"A calm week so far."}' }];
  assertEquals(await ask(reply({ content })), {
    ok: true,
    text: "A calm week so far.",
    model: "claude-haiku-5-5",
    inputTokens: 600,
    outputTokens: 90,
  });
});

Deno.test("no tip: a refusal, max_tokens, no text, not JSON, no tip field, an error", async () => {
  const text = (t: string) => [{ type: "text", text: t }];
  const cases: Array<[string, Reply | Error]> = [
    ["stop_refusal", reply({ stop_reason: "refusal", content: text('{"tip":"x"}') })],
    ["stop_max_tokens", reply({ stop_reason: "max_tokens" })],
    ["no_text", reply({ content: [{ type: "thinking" }] })],
    ["not_json", reply({ content: text("A tip without JSON.") })],
    ["no_tip", reply({ content: text('{"advice":"x"}') })],
    ["error", new Error("boom")],
  ];
  for (const [why, answer] of cases) {
    const got = await ask(answer);
    assert(!got.ok, why);
    assertEquals(got.ok ? "" : got.why, why);
  }
});
