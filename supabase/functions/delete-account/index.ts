import { adminClient, authenticate, cors, json } from "../_shared/http.ts";
Deno.serve(async (request) => {
  let headers: Headers;
  try { headers = cors(request); } catch { return new Response("Forbidden", { status: 403 }); }
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405, headers);
  try {
    const user = await authenticate(request);
    if (!user) return json({ error: "Authentication required" }, 401, headers);
    const admin = adminClient();
    // Remove private storage objects before deleting their owner. Retry is safe.
    while (true) {
      const { data, error } = await admin.storage.from("wardrobe").list(user.id, { limit: 100 });
      if (error) throw error;
      if (!data?.length) break;
      const { error: deletion } = await admin.storage.from("wardrobe").remove(data.map((item) => `${user.id}/${item.name}`));
      if (deletion) throw deletion;
    }
    const { error } = await admin.auth.admin.deleteUser(user.id);
    if (error) throw error;
    return json({ deleted: true }, 200, headers);
  } catch { return json({ error: "Could not delete account. Try again." }, 503, headers); }
});
