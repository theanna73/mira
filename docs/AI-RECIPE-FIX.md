# AI recipe grounding repair — 03/10/2026

The phone screenshot showed the 0.3 grounding rejection after asking for a new chicken recipe. A read-only aggregate of the cloud document confirmed that nutrition is enabled but the saved catalogue has no food or recipe entries. The raw rejected model response was not logged, so its exact invalid reference is unknown.

The server now explicitly distinguishes new recipes from existing meal references and food nutrition records from supply packages. It retries a rejected proposal once with grounding feedback, revalidates the result, and never bypasses missing-ID or disabled-module checks. Both provider attempts share the original 45-second deadline. Saving still requires client confirmation; the function itself writes no meal or recipe records.

Verification: 12 Deno tests passed, including six repair regressions. Deno type-check passed using locally installed @supabase/supabase-js 2.57.4. Published mira-ai revision 5 is ACTIVE and all five deployed source files match the local repair sources. OPTIONS returned 204 with the phone site origin; unauthenticated POST returned 401.

The user's later phone screenshots showed a generated recipe confirmation card and a saved dinner record. However, the record appeared under consumed meals even though the user reported not pressing the consumption button. The cause is not established. No user record was changed to repair this discrepancy.

Added `test/recipe_confirmation_test.dart`: a phone-sized widget scenario with the real nutrition page, chat sheet, confirmation dialog and persistence logic. Only the AI response and local/cloud repositories are simulated. It covers no save before confirmation, cancellation, a linked recipe/meal plan after confirmation, persistence across restart/sync, and consumption only via the separate button. This does not establish the behavior of iPhone Safari, Supabase or the real AI provider.

The previous Flutter SDK and package cache are missing from the refreshed workspace. Attempts to restore the official SDK returned HTTP 404, so the new Flutter regression must be validated in GitHub Actions before merging. Live browser verification remains blocked at the private site's ChatGPT login: the Google redirect returned 502 / Connection refused. The Supabase test account was created and verified separately.

The Supabase skill informed the previous deployment and verification; authentication and reference validation remain in place. This change synchronizes the existing revision 5 server repair with the repository and adds regression coverage; it does not claim to fix the unexplained consumed-meal report. No visual widgets or user records are modified.
