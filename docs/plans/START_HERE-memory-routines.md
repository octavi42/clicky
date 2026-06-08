# START HERE — Preference & Routine Memory Generation

> Onboarding note for an agent working in this worktree. Read this first, then the full plan:
> [`2026-06-08-preference-routine-memories.md`](./2026-06-08-preference-routine-memories.md)

## Goal

The memories UI already ships three categories — **Skills**, **Preferences**, **Routines** — but the brain only **generates Skills**. This work adds detection + generation for **Preferences** and **Routines**. No new UI and no new store are required; the plumbing (`AuxiliaryMemoryStore`, `MemoriesLibraryView`, `Memory`) already exists.

## Worktree facts

- **Branch:** `feature/memory-routines`
- **Based on:** `origin/main` @ `734cd20` (includes session persistence #8, MemoryGate #9, unified memories UI #10, skills polish #11)
- **Isolated data home / defaults:** see `.clicky-worktree.env` (its own `CLICKY_HOME`, global PTT disabled so it won't fight your primary build)
- **Build:** open `leanring-buddy.xcodeproj` in Xcode and Cmd+R. **Do NOT run `xcodebuild`** — it invalidates TCC permissions.

## Current state (verified against this worktree's code)

- `MemoryGate.swift`
  - `enum MemoryCategory { case skill, preference, routine }` already exists (line ~11)
  - `MemoryGateDecision.passedCategories: [MemoryCategory: [GateReason]]` (line ~34)
  - `evaluate(...)` currently only ever returns `[.skill: skillGateReasons]` (line ~60–97)
  - `enum GateReason` (line ~17) — add new cases here
- `CompanionManager.swift`
  - `runMemoryGate(on:)` is the single integration point (line ~536). Today it only calls `distillSkill(...)` when `.skill` passes.
- `Memory.swift` / `AuxiliaryMemoryStore.swift` — model + CRUD store for preferences/routines (already used by the UI; production data is currently DEBUG dummies only).
- `TeachingPromptBuilder.swift` — injects skills into the voice prompt; preferences/routines are NOT injected yet.

## Build order (implement in slices)

1. **Phase 1 — Gate rules (no LLM).** Extend `MemoryGate.evaluate(...)` so `passedCategories` can independently include `.preference` and `.routine`. Add `GateReason` cases (e.g. `.statedPreference`, `.recurringRoutine`). Unit-test in `leanring-buddyTests/MemoryGateTests.swift` before wiring anything else.
2. **Phase 2 — Generators.** New `PreferenceSynthesizer.swift` + `RoutineSynthesizer.swift` (mirror `SkillSynthesizer`, output a `Memory` not a `TeachingSkill`, support patch-over-duplicate). Add `distillPreference(...)` / `distillRoutine(...)` in `CompanionManager` and call them from `runMemoryGate` for each passing category.
3. **Phase 3 — Injection.** Extend `TeachingPromptBuilder` to inject active preferences (small, app-agnostic always; app-scoped on bundle match) and matched routines. Keep the token budget tight; cap per-category counts.

## Files to add / touch (from the plan)

| File | Change |
|------|--------|
| `MemoryGate.swift` | preference/routine rules; new `GateReason` cases; multi-category `passedCategories` |
| **New** `PreferenceSynthesizer.swift` | session trace → preference `Memory` (+ patch) |
| **New** `RoutineSynthesizer.swift` | session trace → routine `Memory` (+ patch) |
| `CompanionManager.swift` | `distillPreference(...)`, `distillRoutine(...)`; call from `runMemoryGate`; save toasts |
| `TeachingPromptBuilder.swift` | inject preferences (always) + matched routines |
| `ClickyAnalytics.swift` | track preference/routine gate decisions + saves |

## Scope guardrails

- No new UI, no new store.
- Gate rules stay cheap/deterministic; only the synthesizers call the LLM (via existing `/chat` worker).
- Don't change skill behavior beyond sharing helpers.

## Open questions to resolve before/while coding

1. **Preference scope** — app-agnostic by default, or always tied to a bundle? (Lean: agnostic unless clearly app-specific.)
2. **Routine recurrence threshold** — 2 vs 3 distinct days? within 7 vs 14 days?
3. **Injection cap** — max preferences/routines per prompt before it gets noisy.
4. **Consent bar** — lighter than skills for behavioral preferences?
