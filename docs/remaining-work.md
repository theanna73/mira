# Mira completion plan

Technical changes may be published after verification. New visual changes must
have actual screenshots and Anna's approval before deploying to the phone Site.
Private owner-only hosting and existing personal data must be preserved.

## Nutrition

- Existing: 62 USDA ingredients, recipes, meal plans, diary snapshots, water,
  unknown-nutrient handling and food expiry.
- This draft: manually entered GTIN lookup through Open Food Facts, explicit
  confirmation, provenance, preservation of manually edited foods, shared
  server quota. Reject incomplete nutrition and non-mass/ambiguous packages.
- Still needed: real camera barcode scanner (manual entry is not scanning),
  products with values per 100 ml, branded text search, coverage checks for
  Russian products, recipe photos and diary visual refinement.
- Release checks: apply quota migration before deploying `food-lookup`; verify
  authenticated lookup, upstream errors and quota; approve actual UI screenshots.
  Do not send diary, account details or images to Open Food Facts. Only the
  requested barcode goes upstream. Data attribution: Open Food Facts, ODbL
  https://world.openfoodfacts.org/terms-of-use
  https://openfoodfacts.github.io/openfoodfacts-server/api/
  Do not redistribute a merged USDA/OFF catalogue. Keep source snapshots in the
  private diary. Do not upload user product photos to the public OFF database.

## Wardrobe

- Existing: private photos, saved outfits, outfit planning.
- Still needed: photo background removal/improvement with cancellable preview,
  preservation of original photo, outfit collages, occasion recommendations.
- AI image provider, price and transmission of photos require a concrete proposal
  and approval before enabling a paid integration.

## Personalization and visual design

- Still needed: day/work schedule, clothing sizes, sport settings, personal goals,
  meaningful statistics and achievements, completion of original photo-rich
  mockups. Do not display invented personal statistics or fake sample records in
  the live account.
- Review every new screen before publishing. Existing date display is dd/MM or
  dd/MM/yyyy; storage remains ISO.

## Assistant and calendars

- Existing: in-chat assistance and explicit confirmation of changes; single-event
  calendar export.
- Still needed: opt-in morning/evening reviews with timezone/quiet hours,
  notification deduplication, cancellation after logout; calendar import and
  two-way synchronization with conflict/deletion handling.
- Google requires an OAuth application and authorized account connection. Apple
  integration needs a chosen supported native/CalDAV path; do not request the
  user's ordinary Apple password or label an ICS download as synchronization.

## Telegram and iPhone

- Still needed: Telegram bot/Mini App, authenticated Telegram account linking,
  webhook verification and privacy controls; TestFlight signed distribution.
- Requires bot ownership/token through secure setup and Apple Developer access,
  signing and a distribution decision. Debug simulator builds are not TestFlight.

## Approval notifications

A GitHub PR event automation is configured in this conversation to notify Anna
when a new concrete result needs approval. It does not run development in the
background and does not approve or deploy visual changes itself.
