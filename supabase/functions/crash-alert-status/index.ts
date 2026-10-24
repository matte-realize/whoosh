// GET /functions/v1/crash-alert-status?crashEventId=<uuid>&kind=crash_alert — contract section 6.
import { handleStatus } from "../_shared/handlers.ts";
import { callerId, guarded, json, makeDeps, methodNotAllowed, unauthenticated } from "../_shared/runtime.ts";

Deno.serve((req) =>
  guarded(async () => {
    if (req.method !== "GET") return methodNotAllowed();
    const userId = await callerId(req);
    if (userId === null) return unauthenticated();
    const url = new URL(req.url);
    return json(await handleStatus(makeDeps(), userId, url.searchParams.get("crashEventId"), url.searchParams.get("kind")));
  }),
);
