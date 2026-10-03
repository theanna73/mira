# Meal transition diagnostics

New meals created by `MiraStore.consumePlan` preserve the original plan ID in
`consumedFromPlanId`, the UTC execution time in `consumedAt`, and the calling
control in `consumedVia` (`nutrition`, `today`, or `unknown` for other callers).
These fields are saved atomically with the meal and plan removal using the
existing private document storage. No additional telemetry service, console
logging, identifiers, permissions, or visual elements are introduced.

The timestamp records execution, not the intended meal time. It does not change
the meal's date, `mealTime`, quantity, or nutrition values. Existing records are
not backfilled: a missing marker cannot identify the origin of an old record.
These markers identify the code path, not proof of a deliberate user gesture.

For a recurrence, inspect only the affected record's kind and these markers:
`today` points to the Today button, `nutrition` to the nutrition diary button.
No marker may indicate an old client or direct diary entry; it is not evidence
of automatic consumption. Avoid inspecting unrelated profile or chat content.

Tests cover both UI controls, cancellation and recipe confirmation, local write
failure, offline restart and reconnection, stale repeated consumption, and
conflict resolution across devices. They use simulated repositories and AI;
the previously reported iPhone behavior has not yet been reproduced.
