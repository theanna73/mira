import { conversationHistory, systemPrompt } from "./conversation.ts";
import { adminClient, authenticate, cors, json, limitedJson } from "../_shared/http.ts";
import { suggestionSchema, validSuggestion, validDate, groundedAction } from "./schema.ts";

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
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST", headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" }, signal: AbortSignal.timeout(45000),
      body: JSON.stringify({ model, store: false, max_completion_tokens: 5000,
        messages: [{ role: "system", content: systemPrompt },
          { role: "user", content: JSON.stringify({ context: body.context, today: body.date, profile, records, weather: body.weather }) },
          ...history,
          { role: "user", content: body.question }],
        response_format: { type: "json_schema", json_schema: { name: "mira_suggestion", strict: true, schema: suggestionSchema } },
      }),
    });
    if (!response.ok) return json({ error: "AI provider unavailable" }, 502, headers);
    const result = await response.json();
    const content = result.choices?.[0]?.message?.content;
    if (!content) return json({ error: "No suggestion returned" }, 502, headers);
    const suggestion = JSON.parse(content);
    if (!validSuggestion(suggestion)) return json({ error: "Invalid suggestion returned" }, 502, headers);
    const actions = suggestion.actions.filter((action: Record<string, unknown>) => groundedAction(action, records, profile.modules));
    if (actions.length !== suggestion.actions.length) {
      suggestion.message = actions.length === 0 ? "Не удалось подготовить изменения: предложение содержит недоступные данные. Ничего не сохранено. Попросите новый вариант из ваших вещей или рецепт с указанными ингредиентами." : "Подготовлены доступные действия ниже. Часть предложения ссылается на недоступные данные и исключена. Ничего не сохранено — подтвердите нужные карточки.";
    }
    return json({ message: suggestion.message, actions }, 200, headers);
  } catch { return json({ error: "Service unavailable" }, 503, headers); }
});
