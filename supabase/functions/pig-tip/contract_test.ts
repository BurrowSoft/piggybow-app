import fixtures from "../../fixtures/tips-run.json" with { type: "json" };
import { validRequest } from "./contract.ts";
import { assert, assertEquals } from "./test_util.ts";

/** Wednesday's week: every field, a plan, a goal, three built-ins and yours. */
const base = fixtures.weeks[1].request as Record<string, unknown>;

function without(key: string): Record<string, unknown> {
  return Object.fromEntries(Object.entries(base).filter(([k]) => k !== key));
}

Deno.test("every staging week passes the contract", () => {
  for (const week of fixtures.weeks) assert(validRequest(week.request) !== null, week.name);
});

Deno.test("without plan_percent and goal_percent too: they're optional", () => {
  const bare = Object.fromEntries(
    Object.entries(base).filter(([k]) => k !== "plan_percent" && k !== "goal_percent"),
  );
  assert(validRequest(bare) !== null);
});

Deno.test("refused: anything but the contract's fields and ranges", () => {
  const feelings = base.feelings as Record<string, number>;
  const cases: Array<[string, unknown]> = [
    ["not an object", [base]],
    ["null", null],
    ["text", "hello"],
    ["an extra field (a note)", { ...base, note: "Lunch" }],
    ["an extra field (an amount)", { ...base, amount: 1200 }],
    ["no picks", without("picks")],
    ["no weekday", without("weekday")],
    ["another language", { ...base, language: "fr" }],
    ["weekday 0", { ...base, weekday: 0 }],
    ["weekday 8", { ...base, weekday: 8 }],
    ["weekday as text", { ...base, weekday: "3" }],
    ["an unknown category", { ...base, category_shares: { food: 10, rent: 5 } }],
    ["four built-ins", { ...base, category_shares: { food: 10, fun: 10, home: 10, gifts: 10 } }],
    ["a share over 100", { ...base, category_shares: { food: 101 } }],
    ["a share not whole", { ...base, category_shares: { food: 10.5 } }],
    ["shares as a list", { ...base, category_shares: [10, 20] }],
    ["an unknown feeling", { ...base, feelings: { ...feelings, angry: 1 } }],
    ["a feeling count not whole", { ...base, feelings: { ...feelings, none: 1.5 } }],
    ["a negative count", { ...base, saves: -1 }],
    ["a huge count", { ...base, active_goals: 100000 }],
    ["plan over 100", { ...base, plan_percent: 120 }],
    ["goal under 0", { ...base, goal_percent: -5 }],
    ["an unknown pick", { ...base, picks: ["save", "spend"] }],
    ["a pick twice", { ...base, picks: ["save", "save"] }],
    ["picks not a list", { ...base, picks: "save" }],
  ];
  for (const [why, body] of cases) assertEquals(validRequest(body), null, why);
});

Deno.test("three built-ins and your own bucket together are allowed", () => {
  assert(
    validRequest({ ...base, category_shares: { food: 40, fun: 20, home: 10, yours: 30 } }) !== null,
  );
});
