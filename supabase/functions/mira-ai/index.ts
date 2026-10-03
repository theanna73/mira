import { conversationHistory, systemPrompt } from "./conversation.ts";
import { adminClient, authenticate, cors, json, limitedJson } from "../_shared/http.ts";
import { suggestionSchema, validDate } from "./schema.ts";
import { prepareSuggestion } from "./suggestion.ts";

Deno.serve(async (request) => {
  let headers: Headers;
  try { headers = cors(request); } catch { return new Response("Forbidden", { status: 403 }); }
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405, headers);
  try {
    const user = await authenticate(request);
    if (!user) return json({ error: "Authentication required" }, 401, headers);
    const apiKey = Deno.env.get("OPENAI_API_KEY");
    const model = Deno.env.get("OPENAI_MODEL");
    if (!apiKey || !model) return json({ error: "AI is not configured" }, 503, headers);
    let body: Record<string, unknown>;
    try { body = await limitedJson(request, 1048576); } catch { return json({ error: "Invalid request" }, 400, headers); }
    const document = body.document as { schemaVersion?: number; profile?: Record<string, unknown>; entries?: Record<string, unknown>[] };
    if (typeof body.question !== "string" || body.question.trim().length === 0 || body.question.length > 2000 || typeof body.date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(body.date) || document?.schemaVersion !== 1 || !Array.isArray(document.entries) || document.entries.length > 5000 || document.profile?.aiConsent !== true) return json({ error: "Invalid request or missing consent" }, 400, headers);
    let history;
    try { history = conversationHistory(body.history); } catch { return json({ error: "Invalid conversation history" }, 400, headers); }
    if (!validDate(body.date)) return json({ error: "Invalid date" }, 400, headers);
    const admin = adminClient();
    const { data: allowed, error: rateError } = await admin.rpc("consume_mira_ai_request", { actor: user.id });
    if (rateError) return json({ error: "Service unavailable" }, 503, headers);
    if (!allowed) return json({ error: "Hourly limit reached" }, 429, headers);
    // Explicit allowlist: never transmit photos, email addresses or arbitrary profile keys.
    const profile = Object.fromEntries(["modules", "preferences", "stylePreferences", "nutritionMode", "calorieGoal", "goal", "allergies", "dislikedFoods", "assistantMode"].map((key) => [key, document.profile?.[key]]));
    const records = document.entries.filter((e) => ["event", "task", "wardrobe", "outfit", "plannedOutfit", "food", "recipe", "meal", "mealPlan", "pantry"].includes(String(e.kind)) || (e.kind === "supply" && (e.data as Record<string, unknown> | undefined)?.category === "food")).slice(-400).map((entry) => {
      const data = entry.data as Record<string, unknown> | undefined;
      const fields = ["date", "start", "end", "done", "category", "color", "season", "items", "occasion", "outfitId", "worn", "sourceId", "slot", "quantity", "calories", "protein", "fat", "carbs", "servings", "ingredients", "amount", "unit", "expiry", "opened", "openMonths", "usedUp", "nutritionKnown", "mealTime"];
      return { id: entry.id, kind: entry.kind, title: entry.title, data: Object.fromEntries(fields.filter((k) => data?.[k] !== undefined).map((k) => [k, data![k]])) };
    });
    const deadline = Date.now() + 45000;
    let suggestion;
    try {
    suggestion = await prepareSuggestion(async (feedback) => {
    const remaining = deadline - Date.now();
    if (remaining <= 0) throw new Error("AI deadline exceeded");
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST", headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" }, signal: AbortSignal.timeout(remaining),
      body: JSON.stringify({ model, store: false, max_completion_tokens: 5000,
        messages: [{ role: "system", content: systemPrompt + "\nПустой каталог продуктов и рецептов не запрещает новый рецепт: используй create_recipe, foodId: пустая строка для ингредиентов без записи kind=food. ID упаковки supply/pantry нельзя использовать как foodId. Для ещё не сохранённого блюда нельзя использовать plan_meal; не ссылайся на выдуманные рецепты из истории." },
          { role: "user", content: JSON.stringify({ context: body.context, today: body.date, profile, records, weather: body.weather }) },
          ...history,
          { role: "user", content: body.question },
          ...(feedback ? [{ role: "user", content: feedback }] : [])],
        response_format: { type: "json_schema", json_schema: { name: "mira_suggestion", strict: true, schema: suggestionSchema } },
      }),
    });
    if (!response.ok) throw new Error("AI provider unavailable");
    const result = await response.json();
    const content = result.choices?.[0]?.message?.content;
    if (!content) throw new Error("No suggestion returned");
    return JSON.parse(content);
    }, records, profile.modules);
    } catch { return json({ error: "AI provider unavailable or invalid suggestion" }, 502, headers); }
    return json(suggestion, 200, headers);
  } catch { return json({ error: "Service unavailable" }, 503, headers); }
});
