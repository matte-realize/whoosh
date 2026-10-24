// POST /functions/v1/delete-crash-audit — contract section 8.
import { handleDelete } from "../_shared/handlers.ts";
import { callerId, guarded, json, makeDeps, methodNotAllowed, unauthenticated } from "../_shared/runtime.ts";

Deno.serve((req) =>
  guarded(async () => {
    if (req.method !== "POST") return methodNotAllowed();
    const userId = await callerId(req);
    if (userId === null) return unauthenticated();
    return json(await handleDelete(makeDeps(), userId, await req.text()));
  }),
);
