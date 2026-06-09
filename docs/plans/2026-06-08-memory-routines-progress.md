# Preference & Routine Memories — Progress & Next Steps

**Branch:** `feature/memory-routines`
**Last worked:** 2026-06-08 (evening)
**Status:** Core feature implemented and building. Known rough edges to polish before merge.

---

## What is DONE (this stage)

Detection + generation + injection for **Preference** and **Routine** memories is implemented end-to-end. The UI and store already existed; only Skills were generated before.

### Phase 1 — Gate rules (cheap, no LLM)
- `MemoryGate.swift` — `evaluate(...)` now returns multiple independent categories in `passedCategories`. Added `GateReason` cases `.statedPreference`, `.styleCorrection`, `.recurringRoutine`. Added `shouldDistillPreference` / `shouldDistillRoutine`.
- `PreferenceSignalDetector.swift` (new) — deterministic phrase matching for stated preferences and repeated style corrections.
- `TeachingTopicHistoryStore.swift` — added `hasRecurringTopicAcrossDays(...)` (routine = same topic on 2+ distinct calendar days within 7).

### Phase 2 — Generators
- `PreferenceSynthesizer.swift` (new) — session trace -> `Memory(category: .preference)`, create/patch prompts.
- `RoutineSynthesizer.swift` (new) — session trace -> `Memory(category: .routine)`, create/patch prompts.
- `AuxiliaryMemoryMatcher.swift` (new) — stable IDs, dedup lookup (`findMemoryForUpdate`), routine matching (`matchRoutines`).
- `CompanionManager.swift` — `distillPreference(...)` / `distillRoutine(...)` called from `runMemoryGate(on:)`; save toasts + deep-link to memory.

### Phase 3 — Injection
- `TeachingPromptBuilder.swift` — injects up to 3 active preferences (always; app-scoped only when bundle matches) and up to 2 matched routines (on app/topic match).
- `CompanionManager.swift` — `activePreferences(bundleId:)` and `matchedRoutines(for:)` helpers wired into the voice prompt call site.

### Analytics / docs / tests
- `ClickyAnalytics.swift` — `trackMemorySaved(category:memoryID:updatedExisting:)`; gate decision now logs per-category flags.
- `AGENTS.md` / `CLAUDE.md` — Key Files table updated with new files.
- `leanring-buddyTests/MemoryGateTests.swift` — added preference, routine, recurrence, and learning-disabled cases.

### Confirmed product decisions
- Routine recurrence: 2+ distinct calendar days within 7 days.
- Preference scope: app-agnostic by default; bundle-scoped only when clearly app-specific.
- Auto-save visibility: same as skills (implicit save + tap-to-open toast).
- Injection cap: 3 preferences + 2 routines.

### Dev-environment changes made today (not feature code)
- Added `-CLICKY_SKIP_SETUP=1` launch flag (`ClickyE2EConfiguration.shouldSkipSetup`) so the worktree skips onboarding/email.
- Scheme: `-CLICKY_DISABLE_GLOBAL_PTT=1` set to disabled so push-to-talk works in this worktree. NOTE: Xcode caches the scheme in memory — must fully quit/reopen Xcode for scheme edits to take effect.

---

## KNOWN ISSUES / IMPROVEMENTS TO DO (tomorrow)

### 1. Cursor response text — edge cases
The text displayed next to the cursor has display edge cases (formatting / clipping / wrapping under certain content). Reproduce specific cases and fix rendering.
- Likely area: `CompanionResponseOverlay.swift`, `OverlayWindow.swift`.

### 2. Preference save is too slow
Saving a new preference takes too long after the session ends.
- Cause: distillation runs at session finalize and makes a synchronous LLM call before the toast appears.
- Options to explore: optimistic/local draft first then enrich; smaller/faster model or lower `maxTokens` for preference synthesis; run earlier (mid-session) like proactive skill drafting; show a "saving..." state immediately.

### 3. Over-eager patch / override of similar preferences
A new preference overrides an existing one when they are only loosely similar (dedup matches too broadly), so distinct preferences get merged/overwritten.
- Cause: `AuxiliaryMemoryMatcher.findMemoryForUpdate` patches on token-overlap >= 1, which is too loose.
- Options to explore: raise overlap threshold; require category + bundle + stronger semantic match; prefer create-new unless high confidence; keep a short list rather than overwrite.

### 4. (Carryover) Other edge cases
User mentioned "some things we have to treat" — capture and triage these as they come up.

---

## Where to resume

1. Reproduce and fix issue #3 (over-eager override) first — it risks data loss of good preferences.
2. Then issue #2 (latency) — biggest UX annoyance.
3. Then issue #1 (cursor text edge cases).

### Files most likely to touch
- `AuxiliaryMemoryMatcher.swift` (dedup threshold)
- `PreferenceSynthesizer.swift` (speed / model / tokens)
- `CompanionManager.swift` (`distillPreference`, save timing/status)
- `CompanionResponseOverlay.swift` / `OverlayWindow.swift` (cursor text)

### Test reminders
- Unit tests: Cmd+U (`MemoryGateTests`).
- Manual: hold Ctrl+Option, say "from now on keep answers short", let session finalize, check `/tmp/clicky-memory-routines/auxiliary-memories.json` and the Brain > Preferences tab.
- Do NOT run `xcodebuild` from terminal (invalidates TCC permissions). Build via Xcode Cmd+R only.
