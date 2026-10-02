export const suggestionSchema = {
  type: "object", additionalProperties: false, required: ["message", "actions"],
  properties: {
    message: { type: "string" },
    actions: { type: "array", items: {
      type: "object", additionalProperties: false,
      required: ["type", "title", "date", "referenceId", "slot", "quantity", "itemIds", "start", "end"],
      properties: {
        type: { type: "string", enum: ["create_task", "plan_outfit", "create_outfit", "plan_meal", "reschedule_event"] },
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
    && ["create_task", "plan_outfit", "create_outfit", "plan_meal", "reschedule_event"].includes(String(a.type))
    && typeof a.title === "string" && a.title.trim().length > 0 && a.title.length <= 300
    && (validDate(a.date) || (a.type === "create_outfit" && a.date === ""))
    && typeof a.referenceId === "string"
    && ["breakfast", "lunch", "dinner", "snack"].includes(String(a.slot))
    && typeof a.quantity === "number" && Number.isFinite(a.quantity) && a.quantity > 0 && a.quantity <= 100000
    && (a.itemIds === undefined || (Array.isArray(a.itemIds) && a.itemIds.length <= 20 && a.itemIds.every((id) => typeof id === "string") && new Set(a.itemIds).size === a.itemIds.length))
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
  if (type === "plan_meal") return ["food", "recipe"].includes(String(find(action.referenceId)?.kind));
  if (type === "create_outfit") return Array.isArray(action.itemIds) && action.itemIds.every((id) => find(id)?.kind === "wardrobe");
  return type === "create_task";
}
