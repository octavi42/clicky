# Start Here: Memory Diff Timeline

Branch: `feature/memory-diff-timeline` (created from `main` after PR #15 merge, 2026-06-10)
Worktree: `/Users/cristeaoctavian/Projects/clicky-roadmap-ideas`
Parent roadmap: [START_HERE-roadmap-ideas.md](./START_HERE-roadmap-ideas.md)

## Status

Roadmap task **#3 — Implemented 2026-06-10** on this branch, following the recommended Option A (receipts-first + title/summary snapshots on each receipt at capture). Manual library edits still don't append receipts — follow-up slice if needed.

**Demo & test guide:** [memory-diff-timeline-demo.md](./memory-diff-timeline-demo.md) — how to present the feature and step-by-step manual QA.

| # | Task | Status | PR |
|---|------|--------|-----|
| 1 | Memory Receipts | **Done** | [#14](https://github.com/octavi42/clicky/pull/14) |
| 2 | What Did You Learn About Me? | **Done** | [#15](https://github.com/octavi42/clicky/pull/15) |
| 3 | **Memory Diff Timeline** | **Done** (implemented 2026-06-10) | `feature/memory-diff-timeline` |

## Product arc (why this feature exists)

Clicky is building a **trustworthy local learning brain**:

1. **Memory Receipts** — "Why did you save *this*?" (one moment, one receipt)
2. **What did you learn about me?** — "What do you know about me overall?" (snapshot of all active memories)
3. **Memory Diff Timeline** ← **this task** — "How did your understanding of *this one memory* change?" (evolution over time)

Same principles throughout: **local-first, user-inspectable, evidence-backed** — not surveillance.

## Goal (one sentence)

In the memories library **detail view**, show how a single memory changed over time — especially **preferences** and **routines** — with the **current value on top** and a **collapsible history** below, each entry grounded in **receipt evidence**.

**Behavior rule (unchanged):** latest preference/routine still wins for Clicky's responses (last-write-wins dedup already in place). The timeline is for **transparency**, not for rolling back behavior automatically.

## UX design (agreed direction)

### Where it lives

Inside the existing **memory detail** screen in `MemoriesLibraryView` — same place as "Why Clicky saved this" and "Ask Clicky why". Do **not** add a new top-level panel section or a separate library.

### Layout (top → bottom)

```
┌─ [Memory title] ─────────────────────┐
│  Category · relative date            │
│                                      │
│  CURRENT                             │
│  Summary / body (what Clicky uses)   │
│                                      │
│  ┌─ How this changed (2) ─────────┐  │  ← collapsed by default if 2+ versions
│  │  ● Today                       │  │
│  │    Was: "keep answers short"   │  │
│  │    Now:  "go deeper on code"   │  │
│  │    You corrected Clicky's style│  │
│  │    "actually explain more…"   │  │
│  │                                │  │
│  │  ○ 2 weeks ago                 │  │
│  │    "keep answers short"        │  │
│  │    You stated a preference     │  │
│  │    "keep it short from now on" │  │
│  └────────────────────────────────┘  │
│                                      │
│  Why Clicky saved this (latest)      │  ← existing receipt section
│  [Ask Clicky why]                    │
│  Body markdown                       │
└──────────────────────────────────────┘
```

### UX principles

| Principle | Detail |
|-----------|--------|
| **Current first** | Day-to-day users see what Clicky believes *now* without scrolling. |
| **Vertical timeline, newest first** | Familiar pattern (git log, settings history). |
| **Show the diff, not a dump** | For preferences/routines: one-line **Was → Now** when text changed. Avoid showing two full markdown bodies unless the user expands. |
| **Receipt = the "why"** | Each entry: date, gate reason (`GateReason.userFacingExplanation`), verbatim `triggerPhrase` or `userAsk`, optional app name. Same evidence model as receipts — no invented reasons. |
| **Collapsed by default** | 0–1 versions → **hide** timeline entirely. 2+ → show chevron **"Changed N times"** / **"How this changed"**, expand on tap. |
| **Category nuance** | **Preferences & routines:** before/after diff is the hero. **Skills:** lighter "activity" timeline (saved → updated → confirmed) — skills grow more than flip. |
| **Panel constraints** | Memories library lives in a **320pt-wide** menu bar panel with `maxHeight: 320` scroll on detail. Keep rows compact; no wide tables or horizontal scroll. |
| **Design system** | Reuse `DS.Colors`, `DS.CornerRadius`, `.pointerCursor()`, `.buttonStyle(.plain)` — match `memoryReceiptSection` and `askClickyWhyButton` styling. |

### Anti-patterns (do not ship)

- Raw version numbers ("Version 3")
- Timeline on the list row (only in detail)
- History for every category with equal weight (skills are secondary)
- Cloud sync or export
- Changing which memory is "active" from the timeline (read-only history)

## Technical starting point (what already exists)

### Multiple receipts per memory (not yet shown in UI)

- `Memory.receipts: [MemoryReceipt]` — oldest first, capped at 10 (`MemoryReceipt.maximumReceiptsPerMemory`)
- Every distill save appends via `MemoryReceipt.appendReceipt` in `CompanionManager` (preference ~1147, routine ~1231, skill ~1030)
- `MemoryReceipt.updatedExistingMemory` — `true` when a save **updated** an existing memory (key signal for timeline entries)
- Detail UI today only shows **`memory.latestReceipt`** in `MemoriesLibraryView.memoryReceiptSection` (~314–363)

### Receipt fields useful per timeline row

From `MemoryReceipt.swift`: `savedAt`, `gateReasons`, `appBundleId`, `userAsk`, `triggerPhrase`, `assistantAnswerSummary`, `updatedExistingMemory`

### Skill-only versioning fields (reference, not yet for prefs/routines)

`TeachingSkill` has `previousBody` and `supersededAt` — skills may already snapshot body on some updates; preferences/routines in `AuxiliaryMemoryStore` do **not** yet store previous title/summary/body on update.

### Store update path

`AuxiliaryMemoryStore.save(_:)` overwrites in place (~53–70) — no version history persisted beyond receipts today.

## Implementation fork (agent must decide, then document in plan)

### Option A — Receipts-only timeline (recommended first slice)

**Idea:** Each receipt = one timeline event. For entries where `updatedExistingMemory == true`, derive "what changed" by comparing consecutive receipts' `triggerPhrase` / memory title at save time — *or* store a snapshot of `title`+`summary` on each receipt at capture time (small schema extension).

**Pros:** Builds on shipped receipt pipeline; no parallel version store.
**Cons:** Manual **Edit** in the library does not create a receipt — user edits won't appear unless you also append a receipt on manual save.

### Option B — Explicit `MemoryVersion` snapshots

**Idea:** On every memory update (distill **or** manual edit), push `{ savedAt, title, summary, body, receiptId? }` onto a `versions: [MemoryVersion]` array (or sidecar JSON like skills' `receipts.json`).

**Pros:** Complete history including manual edits.
**Cons:** More schema + migration work; must dedup with receipts to avoid duplicate rows.

**Recommendation:** Start with **Option A** plus **snapshot title/summary on each new receipt at capture** (extend `MemoryReceipt` or parallel lightweight struct) so diffs are possible without guessing from trigger phrases alone. Add manual-edit versions in a follow-up slice if needed.

## Likely touchpoints

| Area | File | Notes |
|------|------|-------|
| Receipt capture | `MemoryReceipt.swift`, `CompanionManager.swift` | May need snapshot fields on receipt for before/after text |
| Persistence | `AuxiliaryMemoryStore.swift`, `TeachingSkillStore.swift` | Decode tolerant of new optional keys |
| Model | `Memory.swift` | Optional `versions` or enriched receipts |
| UI | `MemoriesLibraryView.swift` | New `memoryTimelineSection` below current summary, above receipt section |
| Tests | `leanring-buddyTests/MemoryDiffTimelineTests.swift` (new) | Timeline row building, collapse rules, diff copy |
| Docs | `AGENTS.md` | Key Files entry after ship |

## Suggested build slices

1. **Model + capture** — ensure each receipt (or version) carries enough text to diff; backward-compatible decode.
2. **Timeline builder** — pure Swift: `[MemoryReceipt]` → `[TimelineEntry]` (date, was, now, why, app).
3. **UI** — collapsible section in detail view; hidden when ≤1 entry.
4. **Tests + AGENTS.md** — no `xcodebuild` from terminal (Xcode Cmd+U).

## Guardrails

- Lead with the learning-companion story, not implementation details.
- Do not run `xcodebuild` from terminal (invalidates TCC permissions).
- Preserve `leanring-buddy` project typo.
- Do not add features beyond timeline scope (no digest, no hygiene coach).
- Commit with `brain(timeline):` prefix; open PR when user asks.

## Prompt to paste after `/clear`

```
Implement roadmap task #3: Memory Diff Timeline on branch feature/memory-diff-timeline.

Read these first:
- docs/plans/START_HERE-memory-diff-timeline.md (UX + technical context)
- docs/plans/START_HERE-roadmap-ideas.md
- AGENTS.md

Goal: In MemoriesLibraryView memory detail, show how a memory changed over time (especially preferences and routines). Current value on top; collapsible "How this changed" vertical timeline when 2+ versions. Each entry: date, before/after when text changed, gate reason + user phrase from receipt evidence. Hide timeline when only one version. Skills: lighter activity-style timeline.

Explore: Memory.receipts, MemoryReceipt (updatedExistingMemory, triggerPhrase), CompanionManager receipt append paths, MemoriesLibraryView memoryReadOnlyDetail / memoryReceiptSection.

Follow START_HERE-memory-diff-timeline.md for the receipts-first approach; propose a short plan before coding if snapshot-on-receipt needs schema changes. Match DS styling and pointer cursors. brain(timeline): commits. No xcodebuild from terminal.
```

## Strongest demo flow (after ship)

1. User states preference: "keep answers short" → Clicky saves with receipt.
2. Later: "go deeper when explaining code" → dedup updates same memory, new receipt with `updatedExistingMemory: true`.
3. User opens memory in library → sees **current** preference + **"Changed 1 time"** timeline with Was/Now and both user phrases.
4. User taps **Ask Clicky why** on latest receipt → still works as today.
