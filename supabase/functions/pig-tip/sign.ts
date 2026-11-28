// Tip signatures. Every tip the function gives out is signed: HMAC-SHA256
// over a version, the model and the text, keyed by the project's
// TIP_REPORT_KEY secret. A report is kept only for a tip whose signature
// verifies, so a client can't make the server store text it made up.
// Rotating the key only refuses reports of tips given before the rotation.

export type Signer = {
  /** The signature of [tip] from [model]: base64url, no padding. */
  sign(model: string, tip: string): Promise<string>;
  /** Whether [sig] is this server's signature of [tip] from [model]. The
   * platform compares (crypto.subtle.verify): never `===` on strings. */
  verify(model: string, tip: string, sig: string): Promise<boolean>;
};

/** Shorter keys sign nothing: no signer, so no tips are given. */
export const MIN_KEY_LENGTH = 32;

const VERSION = "pig-tip-sig-1";
const encoder = new TextEncoder();

/** 32 bytes in base64url without padding. */
const SIG = /^[A-Za-z0-9_-]{43}$/;

function message(model: string, tip: string) {
  return encoder.encode(`${VERSION}\n${model}\n${tip}`);
}

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function fromBase64Url(text: string) {
  if (!SIG.test(text)) return null;
  const binary = atob(text.replaceAll("-", "+").replaceAll("_", "/") + "=");
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

/** A signer keyed by [secret], or null when it's missing or shorter than
 * [MIN_KEY_LENGTH]: then the function fails closed and gives no tips. */
export async function signerFor(secret: string | undefined): Promise<Signer | null> {
  if (!secret || secret.length < MIN_KEY_LENGTH) return null;
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
  return {
    async sign(model, tip) {
      const mac = await crypto.subtle.sign("HMAC", key, message(model, tip));
      return toBase64Url(new Uint8Array(mac));
    },
    async verify(model, tip, sig) {
      const mac = fromBase64Url(sig);
      if (mac === null) return false;
      return await crypto.subtle.verify("HMAC", key, mac, message(model, tip));
    },
  };
}
