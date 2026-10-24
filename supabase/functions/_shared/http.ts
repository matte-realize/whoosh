// http.ts — small JSON response helpers shared by the functions. No PII in error bodies.

export const SCHEMA_VERSION = 1;

export function requestId(): string {
  // Opaque, no PII. "req_" + random hex.
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `req_${hex}`;
}

export function jsonResponse(
  status: number,
  body: Record<string, unknown>,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

// A stable error body with a code and retryable flag (contract §13).
export function errorResponse(
  status: number,
  code: string,
  opts: { retryable?: boolean; scope?: string; retryAfterSeconds?: number } = {},
): Response {
  const body: Record<string, unknown> = {
    schemaVersion: SCHEMA_VERSION,
    requestId: requestId(),
    code,
    retryable: opts.retryable ?? false,
  };
  if (opts.scope) body.scope = opts.scope;
  const headers: Record<string, string> = {};
  if (opts.retryAfterSeconds !== undefined) {
    body.retryAfterSeconds = opts.retryAfterSeconds;
    headers["retry-after"] = String(opts.retryAfterSeconds);
  }
  return jsonResponse(status, body, headers);
}

export function serverTime(): string {
  return new Date().toISOString().replace(/\.\d+Z$/, "Z");
}
