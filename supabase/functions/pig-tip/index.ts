// The pig-tip Edge Function: handler.ts with the real things
// it talks to. Supabase sets SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY for
// every function; ANTHROPIC_API_KEY is the project's own secret. None of
// them is ever logged.

import Anthropic from "@anthropic-ai/sdk";
import { createClient } from "@supabase/supabase-js";
import { handle, type Take } from "./handler.ts";
import { askModel, type Effort, isTipModel, type Reply } from "./model.ts";

const admin = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false, autoRefreshToken: false } },
);

// The key comes from ANTHROPIC_API_KEY. One retry, then no tip: the person
// waits at most about half a minute, and the app asks again only tomorrow.
const anthropic = new Anthropic({ maxRetries: 1, timeout: 15_000 });

const efforts: readonly Effort[] = ["low", "medium", "high"];

Deno.serve((req) =>
  handle(req, {
    async userId(authorization) {
      const jwt = authorization?.match(/^Bearer (.+)$/)?.[1];
      if (!jwt) return null;
      const { data, error } = await admin.auth.getUser(jwt);
      if (error || !data.user || !data.user.is_anonymous) return null;
      return data.user.id;
    },
    async settings() {
      const { data, error } = await admin
        .from("tip_settings")
        .select("enabled, model, effort")
        .eq("id", 1)
        .single();
      if (error) throw error;
      if (!data?.enabled || !isTipModel(data.model) || !efforts.includes(data.effort)) {
        return null;
      }
      return { model: data.model, effort: data.effort };
    },
    async takeTip(uid, today) {
      const { data, error } = await admin.rpc("take_tip", { uid, today });
      if (error) throw error;
      return data as Take;
    },
    ask: (request, settings) =>
      askModel(
        (params) => anthropic.beta.messages.create(params as never) as unknown as Promise<Reply>,
        request,
        settings,
      ),
    async report(report) {
      const { error } = await admin.from("tip_reports").insert(report);
      if (error) throw error;
    },
    async forget(uid) {
      const { error } = await admin.auth.admin.deleteUser(uid);
      if (error) throw error;
    },
    today: () => new Date().toISOString().slice(0, 10),
    log: (line) => console.log(JSON.stringify(line)),
  })
);
