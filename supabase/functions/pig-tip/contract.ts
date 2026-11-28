// A tip's request, checked against supabase/contracts/pig-tip-request.json:
// the same file the app's builder test reads, so the two can't drift. Only
// a body the contract allows exactly reaches the model.

import contract from "../../contracts/pig-tip-request.json" with { type: "json" };

/** The week's summary, as the app's builder sends it. */
export type TipRequest = {
  language: string;
  weekday: number;
  category_shares: Record<string, number>;
  feelings: Record<string, number>;
  saves: number;
  plan_percent?: number;
  goal_percent?: number;
  active_goals: number;
  picks: string[];
};

/** Your own categories' bucket: not one of the built-ins. */
const YOURS = "yours";

/** The most any count may be: plenty for a week, and junk is refused. */
const MAX_COUNT = 1000;

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function isInt(v: unknown, min: number, max: number): v is number {
  return typeof v === "number" && Number.isInteger(v) && v >= min && v <= max;
}

/** The body, when the contract allows it exactly; null otherwise. */
export function validRequest(body: unknown): TipRequest | null {
  if (!isObject(body)) return null;
  const allowed = new Set<string>([...contract.required, ...contract.optional]);
  for (const key of Object.keys(body)) if (!allowed.has(key)) return null;
  for (const key of contract.required) if (!(key in body)) return null;

  const { language, weekday, category_shares, feelings, saves, active_goals, picks } = body;
  if (typeof language !== "string" || !contract.languages.includes(language)) return null;
  if (!isInt(weekday, contract.weekday.min, contract.weekday.max)) return null;

  if (!isObject(category_shares)) return null;
  let builtIns = 0;
  for (const [key, share] of Object.entries(category_shares)) {
    if (!contract.category_keys.includes(key)) return null;
    if (!isInt(share, contract.percent.min, contract.percent.max)) return null;
    if (key !== YOURS) builtIns++;
  }
  if (builtIns > contract.max_built_in_categories) return null;

  if (!isObject(feelings)) return null;
  for (const [key, count] of Object.entries(feelings)) {
    if (!contract.feelings.includes(key)) return null;
    if (!isInt(count, 0, MAX_COUNT)) return null;
  }

  if (!isInt(saves, 0, MAX_COUNT)) return null;
  if (!isInt(active_goals, 0, MAX_COUNT)) return null;
  for (const key of ["plan_percent", "goal_percent"]) {
    if (key in body && !isInt(body[key], contract.percent.min, contract.percent.max)) {
      return null;
    }
  }

  if (!Array.isArray(picks)) return null;
  if (new Set(picks).size !== picks.length) return null;
  for (const pick of picks) {
    if (typeof pick !== "string" || !contract.picks.includes(pick)) return null;
  }

  return body as TipRequest;
}
