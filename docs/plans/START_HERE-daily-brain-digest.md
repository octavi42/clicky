# Start Here: Daily Brain Digest

Branch: `feature/daily-brain-digest` (created from `main` after PR #16 merge, 2026-06-10)
Worktree: `/Users/cristeaoctavian/Projects/clicky-roadmap-ideas`
Parent roadmap: [START_HERE-roadmap-ideas.md](./START_HERE-roadmap-ideas.md)

## Status

Roadmap task **#4 — Next to implement**. Tasks 1–3 are merged to `main`:

| # | Task | Status | PR |
|---|------|--------|-----|
| 1 | Memory Receipts | **Done** | [#14](https://github.com/octavi42/clicky/pull/14) |
| 2 | What Did You Learn About Me? | **Done** | [#15](https://github.com/octavi42/clicky/pull/15) |
| 3 | Memory Diff Timeline | **Done** | [#16](https://github.com/octavi42/clicky/pull/16) |
| 4 | **Daily Brain Digest** | **Start here** | `feature/daily-brain-digest` |

## Product arc (why this feature exists)

Clicky is building a **trustworthy local learning brain**:

1. **Memory Receipts** — "Why did you save *this*?" (one moment)
2. **What did you learn about me?** — "What do you know overall?" (on demand)
3. **Memory Diff Timeline** — "How did *this one memory* change?" (per-memory history)
4. **Daily Brain Digest** ← **this task** — "What did you notice or learn *today*?" (time-bounded recap)

Same principles: **local-first, user-inspectable, evidence-backed** — not surveillance. The digest should feel like a helpful recap the user can skip, not a report card.

## Goal (one sentence)

Give the user a **short, grounded recap** of what Clicky learned or noticed **since the last digest** (default: today / since last app launch), delivered **on demand** first — opt-in before any automatic pop-up.

## UX design (agreed direction)

### Where it lives (first slice)

- **Brain tab** in `CompanionPanelView` — sibling to "What did you learn about me?" and the memories card.
- Optional **voice query** in a follow-up slice ("what's my brain digest?" / "what did you learn today?") — mirror `SelfKnowledgeSummary` intercept pattern.

### Trigger (first slice)

**Manual only:** a button like **"Today's digest"** or **"What happened today?"** on the Brain tab. No launch-time modal in v1.

### Content sections (prioritized)

| Section | Source | Notes |
|---------|--------|-------|
| New skills saved | `TeachingSkillStore` + receipt `savedAt` | Only skills whose **first** receipt falls in the window |
| Preferences / routines updated | `AuxiliaryMemoryStore` + receipts | Highlight **updates** (`updatedExistingMemory`) in window |
| Sessions distilled | `SessionStore` + `MemoryGate` outcomes | Count / one-line themes, not full transcripts |
| Routine suggestions (passive) | `RoutineDetector` / `ActivityStore` | Only if a suggestion is active — link to existing chips if any |
| Vault (opt-in) | `PersonalKnowledgeManager` | Only when vault is enabled and something was saved in window |

**Defer to later slices:** hygiene nags (stale skills, conflicts) — that's task #5 Memory Hygiene Coach.

### Tone & format

- **2–4 short paragraphs** or bullet groups, spoken or shown in panel — match voice companion style (warm, lowercase if spoken via TTS).
- Lead with **counts and titles**, not raw JSON. Quote user phrases only when already on receipts.
- Empty window: honest empty state ("nothing new to report today — keep teaching me when something clicks").

### Anti-patterns (do not ship)

- Full session transcript dump
- Automatic daily notification without opt-in
- Cloud sync or email export
- Surveillance framing ("Clicky watched you for 6 hours")
- Duplicating the full "what did you learn about me?" answer — digest is **time-bounded**, that query is **all-time active memory**

## Technical starting point (what already exists)

| Capability | File | Reuse |
|------------|------|-------|
| Session history (7-day retention) | `SessionStore.swift`, `PersistedSession.swift` | Filter by `startedAt` / `endedAt` in digest window |
| Memory saves with timestamps | `Memory.receipts`, `MemoryReceipt.savedAt` | Primary signal for "what changed today" |
| Skills / prefs / routines stores | `TeachingSkillStore`, `AuxiliaryMemoryStore` | Load active memories, filter receipts in window |
| Self-knowledge summary pattern | `SelfKnowledgeSummary.swift`, `CompanionManager.composeSelfKnowledgeSummaryText` | Template for grounded prompt + deterministic fallback |
| Brain tab UI | `CompanionPanelView.swift` | Add digest button next to existing brain actions |
| Activity / routine detection | `ActivityStore.swift`, `RoutineDetector.swift` | Optional section for passive routine chips |
| Vault | `PersonalKnowledgeManager.swift` | Opt-in section only |

### Digest window

- **Default:** calendar day in local timezone, or since `lastDigestViewedAt` if persisted.
- Persist `~/.clicky/last-digest-viewed-at` (or a small `digest-state.json`) so "today" doesn't re-list yesterday's items after midnight if user already saw them — exact behavior is an agent decision; document in plan.

## Implementation fork (agent must decide)

### Option A — Deterministic digest builder (recommended first slice)

**Idea:** Pure Swift aggregates receipts/sessions in the window → structured `BrainDigest` model → optional short Claude polish pass with **facts-only** prompt (same guardrails as receipts / self-knowledge).

**Pros:** Testable, no hallucination risk if LLM fails.
**Cons:** Copy may feel dry without a light LLM pass.

### Option B — LLM-first narrative

**Idea:** Dump structured facts into one Claude call.

**Pros:** Warmer prose.
**Cons:** Harder to test; must keep deterministic fallback.

**Recommendation:** **Option A** facts + optional single Claude "make it conversational" call with strict grounding, plus verbatim deterministic fallback.

## Likely touchpoints

| Area | File | Notes |
|------|------|-------|
| Model | `BrainDigest.swift` (new) | Sections, counts, fact lines |
| Builder | `BrainDigestBuilder.swift` (new) | Window filter over stores |
| Voice / panel | `CompanionManager.swift` | `speakBrainDigest()` parallel to `speakWhatClickyLearnedAboutMe` |
| UI | `CompanionPanelView.swift` | Brain tab button + loading state |
| Persistence | `ClickyPaths.swift` | Optional digest state path |
| Tests | `BrainDigestTests.swift` (new) | Window filtering, empty state, section assembly |
| Docs | `AGENTS.md` | After ship |

## Suggested build slices

1. **Model + builder** — `BrainDigest` + deterministic aggregation from receipts/sessions in window.
2. **Panel button** — Brain tab trigger, loading state, text display or TTS (match existing brain actions).
3. **Grounded prompt + fallback** — optional Claude polish with facts-only prompt.
4. **Voice intent** (optional slice) — intercept phrase like self-knowledge query.
5. **Tests + AGENTS.md** — no `xcodebuild` from terminal.

## Guardrails

- Manual / opt-in first. No launch modal in v1.
- Do not run `xcodebuild` from terminal (TCC).
- Preserve `leanring-buddy` project typo.
- Commit with `brain(digest):` prefix.
- Do not implement Memory Hygiene Coach (#5) inside this task.

## Prompt to paste after `/clear`

```
Implement roadmap task #4: Daily Brain Digest on branch feature/daily-brain-digest.

Read these first:
- docs/plans/START_HERE-daily-brain-digest.md
- docs/plans/START_HERE-roadmap-ideas.md
- AGENTS.md

Goal: On-demand recap of what Clicky learned/noticed in a time window (default: today). Brain tab button first; grounded in receipts and session distill outcomes. Deterministic builder + optional Claude polish with fallback. Opt-in, not surveillance.

Explore: SessionStore, Memory.receipts, SelfKnowledgeSummary pattern, CompanionPanelView Brain tab, CompanionManager speak helpers.

brain(digest): commits. No xcodebuild from terminal.
```

## Strongest demo flow (after ship)

1. User teaches Clicky a skill and states a preference in one day.
2. User opens Brain tab → taps **Today's digest**.
3. Clicky recaps: "today i saved one skill and updated a preference" with titles and receipt-grounded phrases.
4. User asks "what did you learn about me?" — gets the **full** active-memory answer, not the same as the digest.
