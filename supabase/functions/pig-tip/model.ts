// One call to the model for one tip: the fixed system prompt, the week as
// the user's turn, effort from the settings, and a structured reply {tip}.
// No sampling parameters and no prefill (these models refuse both). The
// reply is read by block type (thinking can come first), and only after
// checking why it stopped.

import Anthropic from "@anthropic-ai/sdk";
import type { TipRequest } from "./contract.ts";
import { SYSTEM_PROMPT, TIP_SCHEMA, userTurn } from "./prompt.ts";

/** The models the settings may name. Anything else asks nothing. */
export const MODELS = ["claude-haiku-5-5", "claude-sonnet-5-5"] as const;
export type TipModel = (typeof MODELS)[number];
export type Effort = "low" | "medium" | "high";
export type ModelSettings = { model: TipModel; effort: Effort };

/** Thinking counts toward it; the staging run measures what's used. */
export const MAX_TOKENS = 1024;

/** The parts of a reply the function reads. */
export type Reply = {
  model: string;
  stop_reason: string | null;
  content: Array<{ type: string; text?: string }>;
  usage?: { input_tokens?: number; output_tokens?: number };
};

/** Sends one request: the SDK in production, a fake in tests. */
export type CreateMessage = (params: Record<string, unknown>) => Promise<Reply>;

export type Usage = { inputTokens: number; outputTokens: number };

export type ModelAnswer =
  | ({ ok: true; text: string; model: string } & Usage)
  | ({ ok: false; why: string; model?: string } & Partial<Usage>);

export function isTipModel(model: unknown): model is TipModel {
  return MODELS.includes(model as TipModel);
}

/** The request for [settings]: what the function sends, nothing else. */
export function tipParams(
  request: TipRequest,
  settings: ModelSettings,
): Record<string, unknown> {
  const params: Record<string, unknown> = {
    model: settings.model,
    max_tokens: MAX_TOKENS,
    system: SYSTEM_PROMPT,
    messages: [{ role: "user", content: userTurn(request) }],
    output_config: {
      effort: settings.effort,
      format: { type: "json_schema", schema: TIP_SCHEMA },
    },
  };
  // Sonnet 5.5: Anthropic's server-side refusal fallback, on by default.
  // Haiku 5.5 has none: a refusal there is no tip.
  if (settings.model === "claude-sonnet-5-5") {
    params.betas = ["server-side-fallback-2026-07-01"];
    params.fallbacks = "default";
  }
  return params;
}

/** Why a call failed, as a short code for the logs (never the message). */
export function errorKind(error: unknown): string {
  // Most specific first: in this SDK APIConnectionError (timeouts too) is
  // itself an APIError.
  if (error instanceof Anthropic.RateLimitError) return "rate_limited";
  if (error instanceof Anthropic.APIConnectionError) return "network";
  if (error instanceof Anthropic.APIError) return `api_${error.status ?? "error"}`;
  return "error";
}

/** One tip's text from the model, or why there's none. */
export async function askModel(
  create: CreateMessage,
  request: TipRequest,
  settings: ModelSettings,
): Promise<ModelAnswer> {
  let reply: Reply;
  try {
    reply = await create(tipParams(request, settings));
  } catch (error) {
    return { ok: false, why: errorKind(error) };
  }
  const usage: Usage = {
    inputTokens: reply.usage?.input_tokens ?? 0,
    outputTokens: reply.usage?.output_tokens ?? 0,
  };
  // Refusals, max_tokens and anything unexpected: no tip.
  if (reply.stop_reason !== "end_turn") {
    return { ok: false, why: `stop_${reply.stop_reason ?? "none"}`, model: reply.model, ...usage };
  }
  const text = reply.content.find((b) => b.type === "text")?.text;
  if (!text) return { ok: false, why: "no_text", model: reply.model, ...usage };
  let tip: unknown;
  try {
    tip = (JSON.parse(text) as { tip?: unknown }).tip;
  } catch {
    return { ok: false, why: "not_json", model: reply.model, ...usage };
  }
  if (typeof tip !== "string") return { ok: false, why: "no_tip", model: reply.model, ...usage };
  return { ok: true, text: tip, model: reply.model, ...usage };
}
