import { adminClient, authenticate, cors, json, limitedJson } from "../_shared/http.ts";
import { ProductError, productSnapshot, validBarcode } from "./product.ts";

Deno.serve(async (request) => {
  let headers: Headers;
  try { headers = cors(request); } catch { return new Response("Forbidden", {status:403}); }
  headers.set("Cache-Control", "no-store");
  if (request.method === "OPTIONS") return new Response(null, {status:204, headers});
  if (request.method !== "POST") return json({error:"Method not allowed"},405,headers);
  try {
    if (!await authenticate(request)) return json({error:"Authentication required"},401,headers);
    let body: Record<string,unknown>;
    try {body = await limitedJson(request,1024);} catch {return json({error:"invalid"},400,headers);}
    if (!validBarcode(body.code)) return json({error:"invalid"},400,headers);
    // Shared across isolates and users; never hold a DB transaction while
    // awaiting the upstream HTTP response. Missing quota fails closed.
    const quota = await adminClient().rpc("consume_food_lookup_request");
    if (quota.error) return json({error:"unavailable"},503,headers);
    if (quota.data !== true) return json({error:"rate_limit"},429,headers);
    const url = new URL(`https://world.openfoodfacts.org/api/v3.6/product/${body.code}.json`);
    url.searchParams.set("fields","code,product_name,product_name_ru,brands,nutriments,nutrition_data_per,quantity,last_modified_t");
    const response = await fetch(url,{headers:{"User-Agent":"Mira/0.3 (https://github.com/theanna73/mira)"},signal:AbortSignal.timeout(10000),redirect:"error"});
    if (response.status === 429 || response.status === 503) return json({error:"rate_limit"},429,headers);
    if (response.status === 404) return json({error:"not_found"},404,headers);
    if (!response.ok) return json({error:"unavailable"},502,headers);
    // Bound even an unexpectedly large upstream response.
    const payload = await limitedJson(new Request("https://mira.invalid",{method:"POST",body:response.body,duplex:"half"} as RequestInit),256000);
    return json({food:productSnapshot(payload,body.code)},200,headers);
  } catch (e) {
    if (e instanceof ProductError) return json({error:e.reason},e.status,headers);
    return json({error:"unavailable"},503,headers);
  }
});
