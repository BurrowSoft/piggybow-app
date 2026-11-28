// Runs SQL files on a Supabase project through the Management API, with the
// project's scoped access token (Database: read-write). The database
// password is never needed, so it never comes near CI. The token is read
// from the environment and never printed.
//
//   SUPABASE_DEPLOY_TOKEN=… PROJECT_REF=… deno run \
//     --allow-net=api.supabase.com --allow-read=supabase/migrations \
//     --allow-env=SUPABASE_DEPLOY_TOKEN,PROJECT_REF \
//     supabase/scripts/sql.ts supabase/migrations/<file>.sql …

/** Runs [query] on project [ref]; throws with the API's status on failure. */
export async function runSql(ref: string, token: string, query: string): Promise<unknown> {
  const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ query }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 500)}`);
  return text ? JSON.parse(text) : null;
}

if (import.meta.main) {
  const token = Deno.env.get("SUPABASE_DEPLOY_TOKEN");
  const ref = Deno.env.get("PROJECT_REF");
  if (!token || !ref) {
    console.error("SUPABASE_DEPLOY_TOKEN and PROJECT_REF are needed");
    Deno.exit(2);
  }
  if (Deno.args.length === 0) {
    console.error("no SQL files given");
    Deno.exit(2);
  }
  for (const file of Deno.args) {
    try {
      await runSql(ref, token, await Deno.readTextFile(file));
      console.log(`${file}: applied`);
    } catch (error) {
      console.error(`${file}: ${error instanceof Error ? error.message : error}`);
      Deno.exit(1);
    }
  }
}
