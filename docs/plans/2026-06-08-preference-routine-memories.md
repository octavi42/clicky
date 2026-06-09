# Preference & Routine Memories — Generation Plan

**Branch / worktree (when implemented):** `feature/memory-routines` → bootstrap via `./scripts/new-worktree.sh feature/memory-routines`
**Created:** 2026-06-08
**Related:** unified memories UI (PR #10), `MemoryGate.swift`, `AuxiliaryMemoryStore.swift`

---

## Status today

The memories UI ships with three categories — **Skills**, **Preferences**, **Routines** — but only **Skills** are actually generated.

| Layer | Skills | Preferences | Routines |
|-------|--------|-------------|----------|
| `MemoryCategory` enum | ✅ | ✅ | ✅ |
| Gate emits category (`passedCategories`) | ✅ | ❌ | ❌ |
| Generator / synthesizer | ✅ `SkillSynthesizer` | ❌ | ❌ |
| Store | ✅ `TeachingSkillStore` | ⚠️ `AuxiliaryMemoryStore` (storage only) | ⚠️ `AuxiliaryMemoryStore` (storage only) |
| Library UI (browse/edit/delete) | ✅ | ✅ | ✅ |
| Production data | ✅ | ❌ DEBUG dummies only | ❌ DEBUG dummies only |

So the **plumbing is multi-category, but the brain only detects skills**. This plan adds the missing detection + generation for preferences and routines.

---

## Definitions (product decision)

- **Skill** — *how* to do a task in an app's UI (already built). Tied to a `bundleId` + task.
- **Preference** — a durable *how the user wants help*, app-agnostic or app-scoped. Examples: "keep answers short", "keyboard shortcuts over menus", "dark mode in dev tools".
- **Routine** — a recurring *multi-step thing the user does on a cadence*. Examples: "morning standup prep", "weekly export to YouTube".

Litmus test:
- Reusable UI steps for one task → **skill**
- A standing instruction about behavior/style → **preference**
- A repeated sequence the user runs again and again → **routine**

---

## Where it plugs in

Single integration point already exists: `CompanionManager.runMemoryGate(on:)` (runs once per finalized `PersistedSession`).

```
session finalize
      ↓
MemoryGate.evaluate(session, topicHistory, isLearningEnabled)
      ↓ passedCategories now may include .preference / .routine
distillSkill(...)            // existing — when .skill passes
distillPreference(...)       // NEW — when .preference passes
distillRoutine(...)          // NEW — when .routine passes
      ↓
AuxiliaryMemoryStore.save(Memory)   // preferences + routines
rebuildMemories()                   // already merges skills + auxiliary
```

No UI work needed — `MemoriesLibraryView` + `AuxiliaryMemoryStore` already render and persist these categories.

---

## Phase 1 — Gate rules (cheap, no LLM)

Extend `MemoryGate.evaluate(...)` so `passedCategories` can include `.preference` and `.routine`. Keep these independent of the skill decision (a session can produce more than one category).

**Preference signals (any 1–2):**
- Explicit preference language in a user turn: "always", "I prefer", "from now on", "stop doing X", "keep it short", "use the keyboard".
- Repeated correction of the assistant's style across turns.

**Routine signals:**
- `TeachingTopicHistoryStore.hasRepeatedTopic(...)` across **multiple distinct days** (not just within one session), AND
- the session is a multi-step sequence (≥2 pointed/ordered steps).

Add `GateReason` cases as needed (e.g. `.statedPreference`, `.recurringRoutine`). Return them under the right category key:

```swift
var passed: [MemoryCategory: [GateReason]] = [:]
if !skillReasons.isEmpty { passed[.skill] = skillReasons }
if !preferenceReasons.isEmpty { passed[.preference] = preferenceReasons }
if !routineReasons.isEmpty { passed[.routine] = routineReasons }
```

Add matching `BlockReason`s only if a category needs an explicit "considered but rejected" trace for analytics.

---

## Phase 2 — Generators

Mirror `SkillSynthesizer` (LLM via the existing `/chat` worker), producing a `Memory` instead of a `TeachingSkill`.

**`PreferenceSynthesizer`**
- Input: session trace + matched preference reasons.
- Output: short `Memory(category: .preference)` — `title`, `summary`, `body` (1–3 sentences, imperative).
- Dedup: if an existing preference with high text overlap exists, **patch** it instead of adding (reuse the patch-prompt pattern).

**`RoutineSynthesizer`**
- Input: session trace + topic-history evidence of recurrence.
- Output: `Memory(category: .routine)` with ordered steps in `body`, optional `bundleIds`.
- Dedup: match on topic + bundle, patch in place.

Both call `AuxiliaryMemoryStore.save(...)`, then `syncTeachingSkillsFromStore()` (which already calls `rebuildMemories()`), and fire the same save toast as skills (`memorySavedToastManager.showTransientMessage(...)` → deep-link to the memory).

---

## Phase 3 — Injection (use the memories)

Today only skills are injected into the voice system prompt (`TeachingPromptBuilder`). Extend it:
- **Preferences:** inject matched/active preferences every turn (tiny token cost, app-agnostic ones always; app-scoped when bundle matches).
- **Routines:** inject only when the routine's topic/app matches the current screen.

Keep the token budget small; cap counts per category.

---

## Files to add / touch

| File | Change |
|------|--------|
| `MemoryGate.swift` | preference/routine rules; new `GateReason` cases; multi-category `passedCategories` |
| **New** `PreferenceSynthesizer.swift` | session trace → preference `Memory` (+ patch) |
| **New** `RoutineSynthesizer.swift` | session trace → routine `Memory` (+ patch) |
| `CompanionManager.swift` | `distillPreference(...)`, `distillRoutine(...)`; call from `runMemoryGate` for passing categories; save toasts |
| `AuxiliaryMemoryStore.swift` | (likely none — already supports CRUD) |
| `TeachingPromptBuilder.swift` | inject preferences (always) + matched routines |
| `ClickyAnalytics.swift` | track preference/routine gate decisions + saves |
| `DummyMemorySeeder.swift` | keep DEBUG dummies; ensure still E2E-gated |

---

## E2E cases (mock-worker, mirror `teaching-skills.sh`)

1. **Preference write** — user says "from now on keep answers short" → after finalize, a `.preference` memory exists in `auxiliary-memories.json`.
2. **Preference patch** — a second related preference session updates the same memory instead of duplicating.
3. **Routine write** — same multi-step topic across 2+ simulated days → a `.routine` memory is created.
4. **Injection** — relaunch; assert preference text appears in `lastSystemPrompt`; routine text appears only when the matching app is frontmost.
5. **Block paths** — generic off-screen Q&A and `learningDisabled` produce no preference/routine.

---

## Scope guardrails (do NOT do here)

- No new UI — the library, edit, delete, and toast already handle all three categories.
- No new store — preferences/routines stay in `AuxiliaryMemoryStore` for now.
- Keep gate rules cheap/deterministic; only the synthesizers call the LLM.
- Don't touch skill behavior beyond sharing helpers.

## Open questions

1. **Preference scope** — app-agnostic by default, or always tie to a bundle? (Lean: agnostic unless the session is clearly app-specific.)
2. **Routine recurrence threshold** — 2 distinct days or 3? Within 7 or 14 days?
3. **Injection cap** — max preferences/routines per prompt before it gets noisy.
4. **Consent** — do preferences need a lighter bar than skills, given they're behavioral, not screen-derived?
