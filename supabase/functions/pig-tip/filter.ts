// The post-filter: the model's tip goes out only if it's short, kind, has no
// numbers, counts or money in it, none of the summary's own labels, isn't
// advice, and is English. Anything else and the person sees the app's own
// tip for the day. The no-guilt patterns are tool/no_guilt.dart's, shared
// through supabase/contracts/no-guilt.json.

import noGuilt from "../../contracts/no-guilt.json" with { type: "json" };

/** The prompt asks for 140 characters at most; 160 leaves a margin. */
export const MAX_TIP_CHARS = 160;

const guilt = noGuilt.patterns.map((p) => new RegExp(p.pattern, "i"));

/** Topics a tip never touches: tips, not advice. */
const advice = new RegExp(
  "\\b(" +
    [
      "invest(s|ed|ing|ment|ments)?",
      "stocks?",
      "stock market",
      "crypto(currency|currencies)?",
      "bitcoin",
      "loans?",
      "credit cards?",
      "debts?",
      "mortgages?",
      "tax(es)?",
      "legal",
      "lawyers?",
      "doctors?",
      "medic(al|ine|ines)",
      "gambl(e|ed|es|ing)",
      "betting",
      "casinos?",
      "lottery",
    ].join("|") +
    ")\\b",
  "i",
);

/** Money signs, and % (no figures at all). */
const money = /[$€£¥฿₩₹₫₱%]/;

/** Counts and shares in words; digits are caught on their own. "one",
 * "once", "first" and "second" stay allowed: in a tip they're rarely a
 * count ("one small thing", "once you've…", "a second look"). */
const numberWords = new RegExp(
  "\\b(" +
    [
      "zero",
      "two|three|four|five|six|seven|eight|nine|ten|eleven|twelve",
      "(thir|four|fif|six|seven|eigh|nine)teen",
      "(twen|thir|for|fif|six|seven|eigh|nine)ty",
      "hundreds?|thousands?|millions?|dozens?",
      "twice|thrice",
      "third|fourth|fifth|sixth|seventh|eighth|ninth|tenth",
      "half|halfway|quarter",
    ].join("|") +
    ")\\b",
  "i",
);

/** The summary's own field names and labels: the prompt asks for everyday
 * words instead. A tip never needs an underscore, so any is a field name. */
const label = /_|\bpicks\b|\bnot really\b/i;

export type Verdict = { ok: true; tip: string } | { ok: false; why: string };

/** The tip as shown (quotes and extra spaces gone), or why it's held back. */
export function checkTip(raw: string): Verdict {
  const tip = raw
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^["“”']+|["“”']+$/g, "")
    .trim();
  if (tip.length === 0) return { ok: false, why: "empty" };
  if (tip.length > MAX_TIP_CHARS) return { ok: false, why: "long" };
  if (/\d/.test(tip)) return { ok: false, why: "number" };
  if (money.test(tip)) return { ok: false, why: "money" };
  if (numberWords.test(tip)) return { ok: false, why: "number_word" };
  if (label.test(tip)) return { ok: false, why: "label" };
  if (guilt.some((r) => r.test(tip))) return { ok: false, why: "guilt" };
  if (advice.test(tip)) return { ok: false, why: "advice" };
  const letters = tip.match(/\p{L}/gu) ?? [];
  const latin = letters.filter((c) => /[A-Za-z]/.test(c)).length;
  if (letters.length === 0 || latin / letters.length < 0.9) {
    return { ok: false, why: "language" };
  }
  return { ok: true, tip };
}
