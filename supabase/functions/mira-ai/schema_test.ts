import { validSuggestion } from "./schema.ts";
const assert = (condition: boolean) => { if (!condition) throw new Error("Assertion failed"); };
Deno.test("AI output validator rejects destructive or malformed actions", () => {
  const action = { type: "create_task", title: "Задача", date: "2026-10-02", referenceId: "", slot: "dinner", quantity: 1 };
  assert(validSuggestion({ message: "Предложение", actions: [action] }));
  assert(!validSuggestion({ message: "Предложение", actions: [{ ...action, type: "delete_all" }] }));
  assert(!validSuggestion({ message: "Предложение", actions: [{ ...action, quantity: -1 }] }));
  assert(!validSuggestion({ message: "Предложение", actions: Array(6).fill(action) }));
  assert(!validSuggestion(null));
});
