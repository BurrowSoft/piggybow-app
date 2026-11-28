import noGuilt from "../../contracts/no-guilt.json" with { type: "json" };
import { checkTip, MAX_TIP_CHARS } from "./filter.ts";
import { assert, assertEquals } from "./test_util.ts";

Deno.test("a kind, short tip passes, without its quotes and extra spaces", () => {
  assertEquals(
    checkTip('  "Food led your week so far.   A home-cooked dinner could be a nice change."  '),
    { ok: true, tip: "Food led your week so far. A home-cooked dinner could be a nice change." },
  );
  assertEquals(checkTip("You could keep one evening this week for something that feels worth it.").ok, true);
});

Deno.test("held back: empty, long, numbers, money, advice, another language", () => {
  const cases: Array<[string, string]> = [
    ["   ", "empty"],
    ["a".repeat(MAX_TIP_CHARS + 1), "long"],
    ["Try to keep 3 evenings free.", "number"],
    ["A $ saved is a $ earned.", "money"],
    ["Keep it under half of your spending, around fifty %.", "money"],
    ["Maybe put a little into stocks.", "advice"],
    ["Paying off a credit card first could help.", "advice"],
    ["You could look at your loans.", "advice"],
    ["A doctor could help with that.", "advice"],
    ["เก็บออมวันละนิดก็ดีนะ", "language"],
  ];
  for (const [tip, why] of cases) assertEquals(checkTip(tip), { ok: false, why }, tip);
});

Deno.test("held back: counts in words, and the summary's own labels", () => {
  const cases: Array<[string, string]> = [
    ["You saved twice this week, and that's lovely.", "number_word"],
    ["Two saves this week is a lovely start.", "number_word"],
    ["You saved three times, nice.", "number_word"],
    ["About half of your spending went to food.", "number_word"],
    ["You're more than halfway to your goal.", "number_word"],
    ["Twenty-something small treats add up to a lot of joy.", "number_word"],
    ["Since your picks lean toward saving, you could keep it gentle.", "label"],
    ["A few spends felt not really, so you could pause before buying.", "label"],
    ["Some spends felt worth_it this week.", "label"],
    ["Your plan_percent is close.", "label"],
  ];
  for (const [tip, why] of cases) assertEquals(checkTip(tip), { ok: false, why }, tip);
});

Deno.test("each no-guilt pattern holds a tip back", () => {
  // One sentence per pattern, in the contract's order.
  const samples = [
    "You went over budget.",
    "Running behind is fine.",
    "You missed a day.",
    "That failed.",
    "You should try it.",
    "You overspent.",
    "You're over your plan.",
    "You shouldn't have.",
    "Keep your streak going!",
    "Such a waste.",
    "No guilt here.",
    "No shame in that.",
    "That was too much.",
    "A bad habit.",
    "So careless.",
    "Don’t forget it!",
    "You only saved once.",
  ];
  assertEquals(samples.length, noGuilt.patterns.length, "a sample for each pattern");
  noGuilt.patterns.forEach((p, i) => {
    assert(new RegExp(p.pattern, "i").test(samples[i]), `sample ${i} fits ${p.pattern}`);
    assertEquals(checkTip(samples[i]), { ok: false, why: "guilt" }, samples[i]);
  });
});

Deno.test("words that only look like advice, guilt, counts or labels are fine", () => {
  for (
    const tip of [
      "Give yourself credit for the saves this week.", // credit, not a credit card
      "A taxi home now and then is fine.", // taxi, not tax
      "Sharing a meal with friends could feel worth it.",
      "You could keep one evening for something that feels worth it.", // one: not a count here
      "Once the weekend comes, a cozy night in could feel good.", // once: not a count here
      "You could take a second look before buying.", // second: not a count here
      "Listen to what felt worth it; you often know.", // ten inside listen and often
      "Someone else's treat can feel worth it too.", // one inside someone
      "Pick a small treat that feels worth it.", // pick, not picks
      "If you're not sure about a spend, you could note how it felt.", // everyday words
    ]
  ) {
    assertEquals(checkTip(tip).ok, true, tip);
  }
});
