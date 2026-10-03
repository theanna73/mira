import { prepareSuggestion } from "./suggestion.ts";
const assert = (value: boolean) => { if (!value) throw new Error("Assertion failed"); };
const recipe = {
  type: "create_recipe", title: "Курица с овощами", date: "2026-10-03",
  referenceId: "", slot: "dinner", quantity: 1, itemIds: [], start: "", end: "",
  ingredients: [{ foodId: "", title: "Куриная грудка", grams: 200 }],
  instructions: "Приготовить до полной готовности", servings: 1, mealTime: "19:00",
};
Deno.test("empty catalogue repairs invented meal to a new named recipe", async () => {
  let calls = 0;
  const result = await prepareSuggestion(async (feedback) => {
    calls++;
    if (calls === 1) return { message: "Предлагаю", actions: [{ ...recipe, type: "plan_meal", referenceId: "invented" }] };
    assert(feedback!.includes("create_recipe") && feedback!.includes("invented"));
    return { message: "Подтвердите рецепт", actions: [recipe] };
  }, [], ["nutrition"]);
  assert(calls === 2 && result.actions[0].type === "create_recipe" && result.actions[0].mealTime === "19:00");
});
Deno.test("supply IDs cannot become nutrition food IDs during repair", async () => {
  let calls = 0;
  const result = await prepareSuggestion(async () => {
    calls++;
    return { message: "Сохранено", actions: [{ ...recipe, ingredients: [{ foodId: "package", title: "Курица", grams: 200 }] }] };
  }, [{ id: "package", kind: "supply" }], ["nutrition"]);
  assert(calls === 2 && result.actions.length === 0 && result.message.includes("Ничего не сохранено"));
});
Deno.test("disabled module cannot be bypassed by repair", async () => {
  const result = await prepareSuggestion(async () => ({ message: "Предлагаю", actions: [recipe] }), [], ["planner"]);
  assert(result.actions.length === 0);
});
Deno.test("valid recipe and real food reference need no retry", async () => {
  let calls = 0;
  const result = await prepareSuggestion(async () => {
    calls++;
    return { message: "Подтвердите", actions: [{ ...recipe, ingredients: [{ foodId: "food", title: "Курица", grams: 200 }] }] };
  }, [{ id: "food", kind: "food" }], ["nutrition"]);
  assert(calls === 1 && result.actions.length === 1);
});
Deno.test("provider failure during repair never exposes an invalid action", async () => {
  let calls = 0;
  const result = await prepareSuggestion(async () => {
    if (++calls === 2) throw new Error("Provider timeout");
    return { message: "Запланировал", actions: [{ ...recipe, type: "plan_meal", referenceId: "missing" }] };
  }, [], ["nutrition"]);
  assert(calls === 2 && result.actions.length === 0 && !result.message.includes("Запланировал"));
});
Deno.test("invalid correction cannot hide rejection or add actions", async () => {
  let calls = 0;
  const result = await prepareSuggestion(async () => {
    if (++calls === 2) return { message: "Запланировал", actions: [{ ...recipe, ingredients: [] }] };
    return { message: "Предлагаю", actions: [{ ...recipe, type: "plan_meal", referenceId: "missing" }] };
  }, [], ["nutrition"]);
  assert(calls === 2 && result.actions.length === 0);
});
