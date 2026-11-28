// The function's admin key, for its Supabase client: the project's default
// secret key (Supabase's API keys: SUPABASE_SECRET_KEYS, a JSON dictionary of
// the project's secret keys by name), else the legacy service-role key
// (SUPABASE_SERVICE_ROLE_KEY, deprecated). Null with neither: the function
// then answers 503 and never builds a client with an empty key, which
// supabase-js refuses at start. The key itself is never logged.

export type AdminKey = { key: string; from: "secret_keys" | "service_role" };

export function adminKeyFrom(
  secretKeys: string | undefined,
  serviceRole: string | undefined,
): AdminKey | null {
  if (secretKeys) {
    try {
      const named: unknown = JSON.parse(secretKeys);
      const key = typeof named === "object" && named !== null
        ? (named as Record<string, unknown>).default
        : undefined;
      if (typeof key === "string" && key !== "") return { key, from: "secret_keys" };
    } catch {
      // Not JSON: as if it weren't there.
    }
  }
  if (serviceRole) return { key: serviceRole, from: "service_role" };
  return null;
}
