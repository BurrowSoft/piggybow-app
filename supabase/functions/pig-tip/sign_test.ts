import { MIN_KEY_LENGTH, signerFor } from "./sign.ts";
import { assert, assertEquals } from "./test_util.ts";

const KEY = "k".repeat(MIN_KEY_LENGTH);
const TIP = "Food led your week so far. A home-cooked dinner could be a nice change.";
const MODEL = "claude-sonnet-5-5";

Deno.test("a tip's signature verifies, and only for that tip, that model and that key", async () => {
  const signer = (await signerFor(KEY))!;
  const sig = await signer.sign(MODEL, TIP);
  assert(/^[A-Za-z0-9_-]{43}$/.test(sig), sig);
  assert(await signer.verify(MODEL, TIP, sig));
  // One character changed in the tip: refused.
  assert(!(await signer.verify(MODEL, TIP.replace("Food", "Fool"), sig)));
  assert(!(await signer.verify(MODEL, `${TIP} `, sig)));
  // Another model, or one character changed in the signature: refused.
  assert(!(await signer.verify("claude-haiku-5-5", TIP, sig)));
  assert(!(await signer.verify(MODEL, TIP, (sig[0] === "A" ? "B" : "A") + sig.slice(1))));
  // Another key's signer: refused.
  const other = (await signerFor("x".repeat(MIN_KEY_LENGTH)))!;
  assert(!(await other.verify(MODEL, TIP, sig)));
  // The same tip signs the same way: no state, no time.
  assertEquals(await signer.sign(MODEL, TIP), sig);
});

Deno.test("a malformed signature is refused, never thrown on", async () => {
  const signer = (await signerFor(KEY))!;
  for (const bad of ["", "abc", "=".repeat(43), "a".repeat(44), "a+b/".repeat(11).slice(0, 43), "é".repeat(43)]) {
    assertEquals(await signer.verify(MODEL, TIP, bad), false, bad);
  }
});

Deno.test("no key, or a short one: no signer, so the function gives no tips", async () => {
  assertEquals(await signerFor(undefined), null);
  assertEquals(await signerFor(""), null);
  assertEquals(await signerFor("k".repeat(MIN_KEY_LENGTH - 1)), null);
});
