import { groundedAction, validSuggestion } from "./schema.ts";

type Suggestion = { message: string; actions: Record<string, unknown>[] };

// A model-generated ID is never repaired by guessing or bypassing validation.
// Ask for one corrected proposal, then validate it against the same records.
export async function prepareSuggestion(
  generate: (feedback?: string) => Promise<unknown>,
  records: Record<string, unknown>[],
  modules: unknown,
): Promise<Suggestion> {
  const first = await generate();
  if (!validSuggestion(first)) throw new Error("Invalid suggestion returned");
  let suggestion = first as Suggestion;
  const rejected = suggestion.actions.filter((a) => !groundedAction(a, records, modules));
  if (rejected.length === 0) return suggestion;
  const feedback = JSON.stringify({
    instruction: "Предыдущее предложение не прошло проверку. Верни исправленное предложение для последнего запроса пользователя. Ничего не было сохранено. Используй только реальные ID из текущих records, не ID и названия из истории. Для нового блюда используй create_recipe с составом и инструкцией; foodId должен быть ID записи kind=food или пустой строкой, если продукта в каталоге нет (в том числе если есть только упаковка supply/pantry). Пустой каталог не запрещает создавать новый рецепт. Не используй plan_meal для ещё не сохранённого рецепта. Соблюдай включённые modules; если необходимый модуль выключен, объясни это без действий. Не обещай сохранение до подтверждения.",
    rejectedActions: rejected,
  });
  try {
    const corrected = await generate(feedback);
    if (validSuggestion(corrected)) suggestion = corrected as Suggestion;
  } catch {
    // Provider failure during repair must not expose the initial invalid action.
  }
  const actions = suggestion.actions.filter((a) => groundedAction(a, records, modules));
  if (actions.length !== suggestion.actions.length) {
    return {
      message: actions.length === 0
        ? "Не удалось подготовить корректное предложение. Ничего не сохранено. Проверьте, включён ли нужный раздел, и уточните состав нового рецепта."
        : "Подготовлены доступные действия ниже. Некорректные ссылки исключены. Ничего не сохранено — подтвердите нужные карточки.",
      actions,
    };
  }
  return suggestion;
}
