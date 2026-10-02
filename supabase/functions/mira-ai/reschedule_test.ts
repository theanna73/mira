import { validSuggestion, groundedAction } from './schema.ts';
const assert = (condition: boolean) => { if (!condition) throw new Error('Assertion failed'); };
Deno.test('event move requires an existing event and coherent times', () => {
  const action = {type: 'reschedule_event', title: 'Встреча', date: '2026-10-03', referenceId: 'event', quantity: 1, slot: 'dinner', itemIds: [], start: '2026-10-03T10:00:00', end: '2026-10-03T11:00:00'};
  assert(validSuggestion({message: 'Перенесём?', actions: [action]}));
  assert(groundedAction(action, [{id: 'event', kind: 'event'}], ['planner']));
  assert(!validSuggestion({message: 'Перенесём?', actions: [{...action, end: '2026-10-03T09:00:00'}]}));
  assert(!validSuggestion({message: 'Перенесём?', actions: [{...action, start: '2026-02-31T10:00:00'}]}));
  assert(!groundedAction(action, [{id: 'event', kind: 'task'}], ['planner']));
});
