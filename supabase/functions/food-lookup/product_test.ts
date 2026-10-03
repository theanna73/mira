import {ProductError, productSnapshot, validBarcode} from "./product.ts";
function assert(value: unknown) { if (!value) throw new Error("Assertion failed"); }
function fixture() { return {product: {code:"3017624010701", product_name:"Product", quantity:"400 g", nutrition_data_per:"100g", nutriments:{"energy-kcal_100g":100,"energy-kcal_unit":"kcal",proteins_100g:2,proteins_unit:"g",fat_100g:0,fat_unit:"g",carbohydrates_100g:23,carbohydrates_unit:"g"}}}; }
Deno.test("GTIN checksum and leading zeros", () => {
  assert(validBarcode("3017624010701")); assert(validBarcode("0034000470693")); assert(validBarcode("034000470693"));
  for (const code of ["3017624010702", "https://example.org", "1", 3017624010701]) assert(!validBarcode(code));
});
Deno.test("complete snapshot preserves real zero and source units", () => {
  const result = productSnapshot(fixture(), "03017624010701"); assert(result.fat === 0); assert(result.calories === 100); assert(result.basisGrams === 100);
});
Deno.test("missing values, serving-only, millilitres, wrong code and units are rejected", () => {
  const cases = [
    (f: ReturnType<typeof fixture>) => { delete (f.product.nutriments as Record<string,unknown>).proteins_100g; },
    (f: ReturnType<typeof fixture>) => { f.product.nutrition_data_per = "serving"; },
    (f: ReturnType<typeof fixture>) => { f.product.nutrition_data_per = "100ml"; },
    (f: ReturnType<typeof fixture>) => { f.product.quantity = "1 l"; },
    (f: ReturnType<typeof fixture>) => { f.product.nutriments.fat_100g = -1; },
    (f: ReturnType<typeof fixture>) => { f.product.nutriments.fat_unit = "mg"; },
    (f: ReturnType<typeof fixture>) => { f.product.code = "0034000470693"; },
  ];
  for (const change of cases) { const f = fixture(); change(f); let rejected = false; try {productSnapshot(f, "3017624010701");} catch (e) {rejected = e instanceof ProductError;} assert(rejected); }
});
