// POST /functions/v1/send-crash-alert — contract section 5. Logic lives in ../_shared/handlers.ts.
import { handleSend } from "../_shared/handlers.ts";
import { callerId, guarded, json, makeDeps, methodNotAllowed, unauthenticated } from "../_shared/runtime.ts";

Deno.serve((req) =>
  guarded(async () => {
    if (req.method !== "POST") return methodNotAllowed();
    const userId = await callerId(req);
    if (userId === null) return unauthenticated();
    return json(await handleSend(makeDeps(), userId, await req.text()));
  }),
);
