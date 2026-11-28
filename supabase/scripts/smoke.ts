// After a deploy: the pig-tip function answers, and refuses a call that has
// no user (401). No token or key is sent or needed.
//
//   PROJECT_REF=… deno run --allow-net --allow-env=PROJECT_REF supabase/scripts/smoke.ts

const ref = Deno.env.get("PROJECT_REF");
if (!ref) {
  console.error("PROJECT_REF is needed");
  Deno.exit(2);
}
const res = await fetch(`https://${ref}.supabase.co/functions/v1/pig-tip`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: "{}",
});
await res.body?.cancel();
console.log(`pig-tip with no user: ${res.status}`);
if (res.status !== 401) Deno.exit(1);
