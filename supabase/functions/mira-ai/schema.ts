export const suggestionSchema = {
  type: "object", additionalProperties: false, required: ["message", "actions"],
  properties: {
    message: { type: "string" },
    actions: { type: "array", items: {
      type: "object", additionalProperties: false,
      required: ["type", "title", "date", "referenceId", "slot", "quantity", "itemIds", "start", "end", "ingredients", "instructions", "servings", "mealTime"],
      properties: {
        type: { type: "string", enum: ["create_task", "plan_outfit", "create_outfit", "plan_meal", "reschedule_event", "create_recipe"] },
        ingredients: { type: "array", items: { type: "object", additionalProperties: false, required: ["foodId", "title", "grams"], properties: { foodId: { type: "string" }, title: { type: "string" }, grams: { type: "number" } } } },
        instructions: { type: "string" }, servings: { type: "number" }, mealTime: { type: "string" },
        start: { type: "string" }, end: { type: "string" },
        title: { type: "string" }, date: { type: "string" }, referenceId: { type: "string" },
        slot: { type: "string", enum: ["breakfast", "lunch", "dinner", "snack"] }, quantity: { type: "number" },
        itemIds: { type: "array", items: { type: "string" } },
      },
    } },
  },
};
export function validDate(value: unknown): boolean {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(value + "T00:00:00Z");
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value && date.getUTCFullYear() >= 2000 && date.getUTCFullYear() <= 2100;
}
export function validSuggestion(value: unknown): boolean {
  if (!value || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  if (typeof v.message !== "string" || !v.message.trim() || v.message.length > 10000 || !Array.isArray(v.actions) || v.actions.length > 5) return false;
  return v.actions.every((a: Record<string, unknown>) => a && typeof a === "object"
    && ["create_task", "plan_outfit", "create_outfit", "plan_meal", "reschedule_event", "create_recipe"].includes(String(a.type))
    && typeof a.title === "string" && a.title.trim().length > 0 && a.title.length <= 300
    && (validDate(a.date) || (["create_outfit", "create_recipe"].includes(String(a.type)) && a.date === ""))
    && typeof a.referenceId === "string"
    && ["breakfast", "lunch", "dinner", "snack"].includes(String(a.slot))
    && typeof a.quantity === "number" && Number.isFinite(a.quantity) && a.quantity > 0 && a.quantity <= 100000
    && (a.itemIds === undefined || (Array.isArray(a.itemIds) && a.itemIds.length <= 20 && a.itemIds.every((id) => typeof id === "string") && new Set(a.itemIds).size === a.itemIds.length))
    && (a.mealTime === undefined || a.mealTime === "" || (typeof a.mealTime === "string" && /^(?:[01]\d|2[0-3]):[0-5]\d$/.test(a.mealTime)))
    && (a.type !== "create_recipe" || (typeof a.instructions === "string" && a.instructions.trim().length > 0 && a.instructions.length <= 5000 && typeof a.servings === "number" && Number.isFinite(a.servings) && a.servings > 0 && a.servings <= 1000 && Array.isArray(a.ingredients) && a.ingredients.length > 0 && a.ingredients.length <= 30 && a.ingredients.every((i: Record<string, unknown>) => i && typeof i.foodId === "string" && typeof i.title === "string" && i.title.trim().length > 0 && i.title.length <= 300 && typeof i.grams === "number" && Number.isFinite(i.grams) && i.grams > 0 && i.grams <= 100000)))
    && (a.type !== "reschedule_event" || (typeof a.start === "string" && typeof a.end === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(a.start) && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(a.end) && validDate(a.start.slice(0, 10)) && validDate(a.end.slice(0, 10)) && a.start.slice(0, 10) === a.date && Number.isFinite(Date.parse(a.start)) && Date.parse(a.end) > Date.parse(a.start)))
    && (a.type !== "create_outfit" || (Array.isArray(a.itemIds) && a.itemIds.length > 0)));
}

export function groundedAction(action: Record<string, unknown>, records: Record<string, unknown>[], modules: unknown): boolean {
  const type = action.type;
  const module = ["create_task", "reschedule_event"].includes(String(type)) ? "planner" : ["plan_outfit", "create_outfit"].includes(String(type)) ? "style" : "nutrition";
  if (!Array.isArray(modules) || !modules.includes(module)) return false;
  const find = (id: unknown) => records.find((r) => r.id === id);
  if (type === "reschedule_event") return find(action.referenceId)?.kind === "event";
  if (type === "plan_outfit") return find(action.referenceId)?.kind === "outfit";
  if (type === "create_recipe") return Array.isArray(action.ingredients) && action.ingredients.every((i) => i.foodId === "" || find(i.foodId)?.kind === "food");
  if (type === "plan_meal") return ["food", "recipe"].includes(String(find(action.referenceId)?.kind));
  if (type === "create_outfit") return Array.isArray(action.itemIds) && action.itemIds.every((id) => find(id)?.kind === "wardrobe");
  return type === "create_task";
}
