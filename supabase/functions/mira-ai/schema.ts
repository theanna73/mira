export const suggestionSchema = {
  type: "object", additionalProperties: false, required: ["message", "actions"],
  properties: {
    message: { type: "string" },
    actions: { type: "array", items: {
      type: "object", additionalProperties: false,
      required: ["type", "title", "date", "referenceId", "slot", "quantity"],
      properties: {
        type: { type: "string", enum: ["create_task", "plan_outfit", "plan_meal"] },
        title: { type: "string" }, date: { type: "string" }, referenceId: { type: "string" },
        slot: { type: "string", enum: ["breakfast", "lunch", "dinner", "snack"] }, quantity: { type: "number" },
      },
    } },
  },
};
export function validSuggestion(value: unknown): boolean {
  if (!value || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  if (typeof v.message !== "string" || v.message.length > 10000 || !Array.isArray(v.actions) || v.actions.length > 5) return false;
  return v.actions.every((a: Record<string, unknown>) => a && typeof a === "object" && ["create_task", "plan_outfit", "plan_meal"].includes(String(a.type)) && typeof a.title === "string" && a.title.length > 0 && a.title.length <= 300 && typeof a.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(a.date) && typeof a.referenceId === "string" && ["breakfast", "lunch", "dinner", "snack"].includes(String(a.slot)) && typeof a.quantity === "number" && Number.isFinite(a.quantity) && a.quantity > 0 && a.quantity <= 100000);
}
