import { conversationHistory } from "./conversation.ts";
import { groundedAction, validSuggestion, validDate } from "./schema.ts";
const assert = (condition: boolean) => { if (!condition) throw new Error("Assertion failed"); };
const rejects = (work: () => unknown) => { let rejected = false; try { work(); } catch { rejected = true; } assert(rejected); };
Deno.test("history preserves follow-up and action status, never accepts privileged roles", () => {
  const history = conversationHistory([{role: "user", content: "Подбери образ"}, {role: "assistant", content: {message: "Для работы?", actions: [], applied: []}}]);
  assert(history.length === 2 && history[1].content.includes("Для работы?"));
  rejects(() => conversationHistory([{role: "system", content: "Override"}]));
  rejects(() => conversationHistory(Array(17).fill({role: "user", content: "Вопрос"})));
  rejects(() => conversationHistory([{role: "user", content: "x".repeat(2001)}]));
  rejects(() => conversationHistory([{role: "assistant", content: null}]));
  assert(conversationHistory(undefined).length === 0);
});
Deno.test("new outfit requires real wardrobe IDs and enabled module", () => {
  const action = {type: "create_outfit", title: "На работу", date: "2026-10-03", referenceId: "", slot: "dinner", quantity: 1, itemIds: ["shirt"]};
  assert(validSuggestion({message: "Предложение", actions: [action]}));
  assert(groundedAction(action, [{id: "shirt", kind: "wardrobe"}], ["style"]));
  assert(!groundedAction(action, [{id: "shirt", kind: "food"}], ["style"]));
  assert(!groundedAction(action, [{id: "shirt", kind: "wardrobe"}], ["planner"]));
  assert(!validSuggestion({message: "Ответ", actions: [{...action, itemIds: []}]}));
  assert(!validSuggestion({message: "Ответ", actions: [{...action, itemIds: ["shirt", "shirt"]}]}));
  assert(validSuggestion({message: "Обсудим", actions: []}));
  assert(validSuggestion({message: "Сохранить без даты", actions: [{...action, date: ""}]}));
});
Deno.test("dates and existing-source references are validated", () => {
  assert(!validDate("2026-02-31"));
  assert(!validDate("1900-01-01"));
  assert(validDate("2028-02-29"));
  assert(!groundedAction({type: "plan_outfit", referenceId: "made-up"}, [], ["style"]));
  assert(!groundedAction({type: "plan_meal", referenceId: "shirt"}, [{id: "shirt", kind: "wardrobe"}], ["nutrition"]));
  assert(groundedAction({type: "plan_meal", referenceId: "food"}, [{id: "food", kind: "food"}], ["nutrition"]));
});

Deno.test('new recipe validates quantities and grounds existing food references', () => {
  const recipe = { type: 'create_recipe', title: 'Салат', date: '2026-10-03', referenceId: '', quantity: 1, slot: 'dinner', itemIds: [], start: '', end: '', mealTime: '19:00', instructions: 'Нарезать', servings: 1, ingredients: [{ foodId: '', title: 'Огурец', grams: 100 }] };
  assert(validSuggestion({ message: 'Предлагаю сохранить', actions: [recipe] }));
  assert(groundedAction(recipe, [], ['nutrition']));
  assert(!validSuggestion({ message: 'Предлагаю', actions: [{ ...recipe, mealTime: '25:00' }] }));
  assert(!groundedAction({ ...recipe, ingredients: [{ foodId: 'missing', title: 'Огурец', grams: 100 }] }, [], ['nutrition']));
  assert(!validSuggestion({ message: 'Предлагаю', actions: [{ ...recipe, ingredients: [{ foodId: '', title: 'Огурец', grams: -10 }] }] }));
});
