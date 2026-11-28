// The pig-tip Edge Function: handler.ts with the real things
// it talks to. Supabase sets SUPABASE_URL and the project's keys for every
// function (SUPABASE_SECRET_KEYS; the legacy SUPABASE_SERVICE_ROLE_KEY on
// older projects); ANTHROPIC_API_KEY and TIP_REPORT_KEY are the project's
// own secrets. None of them is ever logged.

import Anthropic from "@anthropic-ai/sdk";
import { createClient } from "@supabase/supabase-js";
import { type Filed, handle, type Take } from "./handler.ts";
import { adminKeyFrom } from "./keys.ts";
import { askModel, type Effort, isTipModel, type Reply } from "./model.ts";
import { signerFor } from "./sign.ts";

// The admin key: the project's default secret key, else the legacy
// service-role key (keys.ts). Without one there's no client (supabase-js
// refuses an empty key at start, and the function wouldn't run at all), and
// every request gets 503.
const adminKey = adminKeyFrom(
  Deno.env.get("SUPABASE_SECRET_KEYS"),
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
);
const admin = adminKey === null ? null : createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  adminKey.key,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

// The key comes from ANTHROPIC_API_KEY. One retry, then no tip: the person
// waits at most about half a minute, and the app asks again only tomorrow.
const anthropic = new Anthropic({ maxRetries: 1, timeout: 15_000 });

const efforts: readonly Effort[] = ["low", "medium", "high"];

// Where this function runs: the platform's own variable on hosted Edge
// Functions. Unset, a region the settings name is never matched.
const region = Deno.env.get("SB_REGION") ?? null;

// Signs every tip given; a report must bring its tip's signature back.
// Missing or shorter than 32 characters, and no tips are given (503): never
// one whose report couldn't be proved.
const signer = await signerFor(Deno.env.get("TIP_REPORT_KEY"));

// At start, names only: which of the variables this function expects are
// set, which admin key it uses and whether it can sign. Never a value.
console.log(JSON.stringify({
  start: "pig-tip",
  set: Object.fromEntries(
    [
      "SUPABASE_URL",
      "SUPABASE_SECRET_KEYS",
      "SUPABASE_SERVICE_ROLE_KEY",
      "ANTHROPIC_API_KEY",
      "TIP_REPORT_KEY",
      "SB_REGION",
    ].map((name) => [name, (Deno.env.get(name) ?? "") !== ""]),
  ),
  adminKey: adminKey?.from ?? "none",
  signingKey: signer !== null,
}));

const filed: readonly Filed[] = ["ok", "cap", "used"];

Deno.serve((req) =>
  handle(req, {
    async userId(authorization) {
      const jwt = authorization?.match(/^Bearer (.+)$/)?.[1];
      if (!jwt) return null;
      const { data, error } = await admin!.auth.getUser(jwt);
      if (error || !data.user || !data.user.is_anonymous) return null;
      return data.user.id;
    },
    async settings() {
      const { data, error } = await admin!
        .from("tip_settings")
        .select("enabled, model, effort, region")
        .eq("id", 1)
        .single();
      if (error) throw error;
      // Checked here, whatever the client's types say: an unknown model,
      // effort or region asks nothing.
      const row = data as unknown as
        | { enabled?: unknown; model?: unknown; effort?: unknown; region?: unknown }
        | null;
      const effort = efforts.find((e) => e === row?.effort);
      if (!row || row.enabled !== true || !isTipModel(row.model) || !effort) return null;
      const only = row.region ?? null;
      if (only !== null && typeof only !== "string") return null;
      return { model: row.model, effort, region: only };
    },
    admin: admin !== null,
    region,
    signer,
    async takeTip(uid, today) {
      const { data, error } = await admin!.rpc("take_tip", { uid, today });
      if (error) throw error;
      return data as Take;
    },
    ask: (request, settings) =>
      askModel(
        (params) => anthropic.beta.messages.create(params as never) as unknown as Promise<Reply>,
        request,
        settings,
      ),
    // The caps and the report in one transaction (file_report); the report
    // row holds no one's id.
    async fileReport(uid, today, report) {
      const { data, error } = await admin!.rpc("file_report", { uid, today, ...report });
      if (error) throw error;
      const answer = filed.find((f) => f === data);
      if (!answer) throw new Error("file_report: an unexpected answer");
      return answer;
    },
    async forget(uid) {
      const { error } = await admin!.auth.admin.deleteUser(uid);
      if (error) throw error;
    },
    today: () => new Date().toISOString().slice(0, 10),
    log: (line) => console.log(JSON.stringify(line)),
  })
);
