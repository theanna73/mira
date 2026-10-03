type ObjectMap = Record<string, unknown>;
function object(value: unknown): ObjectMap {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as ObjectMap : {};
}
export function validBarcode(code: unknown): code is string {
  if (typeof code !== "string" || !/^(?:\d{8}|\d{12}|\d{13}|\d{14})$/.test(code)) return false;
  let sum = 0;
  for (let i = code.length - 2, weight = 3; i >= 0; i--, weight = 4 - weight) sum += Number(code[i]) * weight;
  return (10 - sum % 10) % 10 === Number(code.at(-1));
}
function canonical(code: string): string {
  const stripped = code.replace(/^0+/, "") || "0";
  return stripped.length <= 8 ? stripped.padStart(8, "0") : stripped.length <= 13 ? stripped.padStart(13, "0") : stripped;
}
export class ProductError extends Error {
  constructor(readonly reason: "not_found" | "incomplete" | "liquid" | "invalid", readonly status = 422) { super(reason); }
}
export function productSnapshot(payload: unknown, requestedCode: string) {
  const root = object(payload), product = object(root.product);
  if (object(root.result).id === "product_not_found" || root.status === 0 || !Object.keys(product).length) throw new ProductError("not_found", 404);
  const code = product.code;
  if (!validBarcode(code) || canonical(code) !== canonical(requestedCode)) throw new ProductError("invalid");
  const title = product.product_name_ru || product.product_name;
  if (typeof title !== "string" || !title.trim()) throw new ProductError("incomplete");
  // OFF's *_100g can mean 100 ml for drinks. Mira currently uses grams only.
  // Reject liquids/ambiguous bases instead of assuming that 1 ml weighs 1 g.
  if (product.nutrition_data_per !== "100g") throw new ProductError("liquid");
  // The field above is ambiguous in OFF. Require an explicitly mass-labelled
  // package too, so beverages reported as *_100g are not treated as grams.
  if (typeof product.quantity !== "string" || !/^\s*\d+(?:[.,]\d+)?\s*(?:g|kg|г|кг)\s*$/i.test(product.quantity)) throw new ProductError("liquid");
  const nutrients = object(product.nutriments);
  const values: Record<string, number> = {};
  for (const [target, source] of Object.entries({calories: "energy-kcal", protein: "proteins", fat: "fat", carbs: "carbohydrates"})) {
    const value = nutrients[`${source}_100g`];
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0) throw new ProductError("incomplete");
    values[target] = value;
  }
  if (nutrients["energy-kcal_unit"] !== "kcal" || ["proteins", "fat", "carbohydrates"].some(key => nutrients[`${key}_unit`] !== "g")) throw new ProductError("incomplete");
  return {code, title: title.trim().slice(0, 300), brand: typeof product.brands === "string" ? product.brands.slice(0, 300) : "", modified: typeof product.last_modified_t === "number" ? String(product.last_modified_t) : "", basisGrams: 100, calories: values.calories, protein: values.protein, fat: values.fat, carbs: values.carbs};
}
