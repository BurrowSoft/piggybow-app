import { adminKeyFrom } from "./keys.ts";
import { assertEquals } from "./test_util.ts";

// Which admin key the function takes: the project's default secret key
// first, the legacy service-role key only as a fallback, and none at all
// rather than an empty one.

Deno.test("the default secret key first, from the new API keys' dictionary", () => {
  assertEquals(
    adminKeyFrom(JSON.stringify({ default: "sb_secret_one", other: "sb_secret_two" }), "legacy-jwt"),
    { key: "sb_secret_one", from: "secret_keys" },
  );
});

Deno.test("the legacy service-role key when there's no usable default secret key", () => {
  for (
    const secretKeys of [
      undefined,
      "",
      "not json",
      "null",
      "[]",
      JSON.stringify({ other: "sb_secret_two" }),
      JSON.stringify({ default: "" }),
      JSON.stringify({ default: 7 }),
    ]
  ) {
    assertEquals(
      adminKeyFrom(secretKeys, "legacy-jwt"),
      { key: "legacy-jwt", from: "service_role" },
      String(secretKeys),
    );
  }
});

Deno.test("neither: no key, never an empty one", () => {
  assertEquals(adminKeyFrom(undefined, undefined), null);
  assertEquals(adminKeyFrom("", ""), null);
  assertEquals(adminKeyFrom("{}", ""), null);
  assertEquals(adminKeyFrom(JSON.stringify({ default: "" }), undefined), null);
});
