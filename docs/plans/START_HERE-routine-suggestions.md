# START HERE — Routine Suggestions (activity logging + panel chips)

> Onboarding note for an agent working in this worktree. Read this first, then the
> canonical design in [`docs/architecture/MEMORY_PIPELINE.md`](../architecture/MEMORY_PIPELINE.md)
> (see the "Passive activity (routines)" and "Routines" sections) and
> [`docs/architecture/MEMORY_ROADMAP.md`](../architecture/MEMORY_ROADMAP.md) item 6.

## Goal

Build the **passive half of routines** — the part that `feature/memory-routines` does NOT cover.

`feature/memory-routines` handles routine **generation** (gate → synthesize a routine `Memory` from a
session → inject). This worktree handles **passive observation + UI surfacing**:

1. Log app-to-app transition edges to `~/.clicky/activity.json` (no LLM).
2. Detect when a chain repeats (e.g. "you often open Figma after Slack").
3. Surface a **suggestion chip** in the menu bar panel when a pattern repeats.

**Routines stay out of the system prompt — panel chips only** (see `DECISIONS.md`: "Routines in
system prompt → No — Panel chips only, avoid token bloat").

## Worktree facts

- **Branch:** `feature/routine-suggestions`
- **Based on:** `origin/main` @ `734cd20` (session persistence, MemoryGate #9, memories UI #10, skills polish #11)
- **Isolated data home / defaults:** `.clicky-worktree.env` — `CLICKY_HOME=/tmp/clicky-routine-suggestions`, global PTT disabled so it won't fight your primary build.
- **Build:** open `leanring-buddy.xcodeproj` in Xcode and Cmd+R. **Do NOT run `xcodebuild`** — it invalidates TCC permissions. Xcode caches the scheme in memory; fully quit/reopen Xcode if scheme edits don't take.

## Scope boundary vs `feature/memory-routines`

| | `feature/memory-routines` (other worktree) | `feature/routine-suggestions` (HERE) |
|---|---|---|
| What | Generate preference/routine memories from a session via the gate + synthesizer | Passively log app transitions + surface repeat chains as panel chips |
| Storage | `auxiliary-memories.json` (via `AuxiliaryMemoryStore`) | **New** `~/.clicky/activity.json` (transition edges) |
| LLM | Yes (synthesizers) | **No LLM at all** |
| UI | Memories library (already exists) | **New** routine suggestion chips in the panel |
| Prompt injection | Yes (preferences + routines into voice prompt) | **No** — chips only |

Keep these two from colliding: do **not** touch `AuxiliaryMemoryStore`, `MemoryGate`,
`PreferenceSynthesizer`, `RoutineSynthesizer`, or `TeachingPromptBuilder` here. This work is
self-contained in a new activity store + a new panel section.

## What already exists (verified against this worktree's code)

There is already an in-memory app-usage tracker you should **reuse the plumbing of, not duplicate**:

- **`AppUsageCollector.swift`** — tracks foreground app sessions to `~/.clicky/app-usage.json`
  (7-day rolling window). Has `recordFrontmostApplicationChange(to:)`, `weightedSecondsByBundleId()`,
  `mostRecentlyUsedBundleId(...)`. NOTE: it stores **per-app durations**, NOT **transition edges**.
  Routines need ordered A→B edges, which this does not capture today.
- **`CompanionManager.startFrontmostAppObservation()`** (~line 1191) — the single hook where every
  app activation already flows. Today it calls
  `nicheDiscoveryManager.handleFrontmostApplicationChanged(to:)` + `refreshNicheSuggestions()`.
  **This is where you add routine-edge logging** (record transition `previousBundleId → newBundleId`).
- **`CompanionManager.finalizeAndPersistSession()`** (~line 482) — computes
  `appsUsed = orderedUniqueBundleIds(turnsSnapshot)`. A second, coarser signal for app sequences if
  you'd rather log per-session instead of per-activation.
- **`ClickyPaths`** (`ClickyPaths.swift`) — central data-home paths (`home`, `skills`, `sessions`,
  `topicHistory`). **Add an `activity` URL here** so it respects `CLICKY_HOME` isolation:
  `static var activity: URL { home.appendingPathComponent("activity.json") }`.
- **Niche suggestion pattern to MIRROR for chips:**
  - `NicheDiscoveryManager.swift` — `NicheSuggestion` model + `suggestionSnapshot(...)` producing a
    snapshot the panel renders.
  - `CompanionPanelView.swift` — `nicheSuggestionsSection` (~line 941) iterates
    `companionManager.nicheSuggestions` and renders `nicheSuggestionCard(_:)` (~line 1031), a tappable
    `Button` styled with `DS` tokens + `.pointerCursor()`. Copy this card style for routine chips.
  - `CompanionManager.nicheSuggestions` / `nicheSuggestionContextLabel` are the `@Published`
    properties the panel binds to. Add analogous `routineSuggestions` published state.

## Build order (implement in slices)

1. **Phase 1 — Activity store (no UI, no LLM).**
   - New `ActivityStore.swift` (mirror `SessionStore` / `AppUsageCollector` file I/O patterns):
     model for transition edges `{ from: bundleId, to: bundleId, count, lastSeen }`, persisted to
     `ClickyPaths.activity` as JSON. Rolling 30-day (or 7-day to match `AppUsageCollector`) window.
   - Add `ClickyPaths.activity`.
   - Hook edge recording into `CompanionManager.startFrontmostAppObservation()` (track the previous
     frontmost bundleId, increment the `previous → new` edge on each activation; ignore Clicky's own
     bundleId and neutral apps the way `NicheDiscoveryManager` does).
   - Unit-test the edge counting / pruning in `leanring-buddyTests/` before any UI.

2. **Phase 2 — Recurrence detection.**
   - `RoutineDetector.swift` (pure, deterministic): given the edge store, surface chains that repeat
     above a threshold. Decide the threshold (suggested start: edge `count >= 3` within the window;
     align with memory-routines' "2+ distinct days in 7" if you want consistency — confirm below).
   - Produce a `RoutineSuggestion` model (id, fromBundleId, toBundleId, human label like
     "You often open Figma after Slack").

3. **Phase 3 — Panel chips.**
   - Add `@Published routineSuggestions: [RoutineSuggestion]` (+ context label) to `CompanionManager`,
     refreshed from the same activation hook (debounced) like `refreshNicheSuggestions()`.
   - Add a `routineSuggestionsSection` + `routineSuggestionCard(_:)` to `CompanionPanelView`,
     mirroring the niche card (DS tokens, `.pointerCursor()`, accessibility identifier
     `clicky.panel.routine-suggestions.*`). Decide tap behavior (dismiss / "don't suggest" / open the
     two apps) — keep v1 minimal.

## Files to add / touch

| File | Change |
|------|--------|
| **New** `leanring-buddy/ActivityStore.swift` | transition-edge model + JSON persistence + pruning |
| **New** `leanring-buddy/RoutineDetector.swift` | recurrence rules → `RoutineSuggestion`s (no LLM) |
| `leanring-buddy/ClickyPaths.swift` | add `activity` URL |
| `leanring-buddy/CompanionManager.swift` | record edges in `startFrontmostAppObservation()`; publish `routineSuggestions` |
| `leanring-buddy/CompanionPanelView.swift` | new `routineSuggestionsSection` + card (mirror niche card ~lines 941 / 1031) |
| `leanring-buddy/ClickyAnalytics.swift` | track routine suggestion shown / tapped / dismissed |
| **New** `leanring-buddyTests/ActivityStoreTests.swift` | edge counting, pruning, recurrence threshold |
| `docs/architecture/MEMORY_ROADMAP.md` | flip item 6 routine "activity logging + chips" to done when shipped |

## Scope guardrails

- **No LLM** anywhere in this feature.
- **No system-prompt injection** — chips only.
- Don't touch the memory-routines surface (`MemoryGate`, `AuxiliaryMemoryStore`, synthesizers,
  `TeachingPromptBuilder`) to avoid merge conflicts.
- Respect `CLICKY_HOME` isolation — always go through `ClickyPaths`, never hardcode `~/.clicky`
  (note `AppUsageCollector` currently hardcodes its path; do NOT copy that mistake for `activity.json`).
- Honor the learning/privacy toggle: if `isLearningFromSessionsEnabled` is off, consider whether to
  pause edge logging (confirm in open questions).

## Open questions to resolve before/while coding

1. **Recurrence threshold** — edge `count >= 3` in window, or align with memory-routines' "2+ distinct
   calendar days within 7"? (Lean: distinct-days to avoid one busy session inflating a chain.)
2. **Window length** — 7 days (match `AppUsageCollector`) or 30 (the pipeline spec says "rolling
   30-day")? Pick one and be consistent.
3. **Privacy** — does `isLearningFromSessionsEnabled = false` also pause passive activity logging?
4. **Chip tap behavior** — dismiss only, "don't suggest again", or actively help (open the next app)?
5. **Per-activation vs per-session edges** — log every app switch, or only the `appsUsed` sequence at
   session finalize? (Per-activation is richer but noisier.)

## Test reminders

- Unit tests: Cmd+U (add `ActivityStoreTests`).
- Manual: with `CLICKY_HOME=/tmp/clicky-routine-suggestions`, switch between two apps repeatedly,
  then inspect `/tmp/clicky-routine-suggestions/activity.json` and the panel for a chip.
- Do NOT run `xcodebuild` from terminal (invalidates TCC permissions). Build via Xcode Cmd+R only.
