# Memory Diff Timeline — Demo & Test Guide

Branch: `feature/memory-diff-timeline`  
Product context: [START_HERE-memory-diff-timeline.md](./START_HERE-memory-diff-timeline.md)

## How to present this feature (30 seconds)

**One-liner:** Clicky now shows *how* a single memory changed over time — not just why it saved the latest version.

**Story arc (fits the brain roadmap):**

1. **Memory Receipts** — “Why did you save *this*?” (one moment)
2. **What did you learn about me?** — “What do you know overall?” (snapshot)
3. **Memory Diff Timeline** ← **this** — “How did your understanding of *this one memory* change?” (evolution)

**Demo script:**

1. Open **Memories** → **Preferences** → **Go deeper on code explanations**.
2. Point at the **summary at the top** — “This is what Clicky believes *now*.”
3. Tap **How this changed (2)** — “Earlier you asked for short answers; later you corrected Clicky. Here’s the Was → Now, with your exact words and why the save fired.”
4. Optional: tap **Ask Clicky why** on the latest receipt — still works; timeline is extra transparency, not a replacement.

**What to emphasize:**

- Local-first, read-only history — no rollback, latest preference/routine still wins for responses.
- Evidence-backed: every row ties to a real receipt (gate reason + user phrase), not invented version numbers.
- Skills get a lighter **Saved / Updated** activity timeline because they grow more than they flip.

**Known gap (mention if asked):** Manual edits in the library don’t create receipts yet, so they won’t appear in the timeline until a follow-up slice.

---

## How to test

### Prerequisites

- Build and run from **Xcode** (Cmd+R). Do **not** use terminal `xcodebuild` (invalidates TCC permissions).
- DEBUG build seeds dummy memories automatically (`DummyMemorySeeder`).

### Quick smoke (dummy data)

| Step | Action | Expected |
|------|--------|----------|
| 1 | Menu bar Clicky → Brain → **Memories** | Library opens |
| 2 | **Preferences** → **Go deeper on code explanations** | Detail opens |
| 3 | Look for **How this changed** | Section visible with badge **2**, collapsed |
| 4 | Tap header | Expands: newest first, **Was / Now**, gate reason, quoted phrase |
| 5 | **Preferences** → **Prefer concise answers** (1 receipt) | **No** timeline section |
| 6 | **Routines** → **Review a pull request** | Timeline with summary diff (title unchanged) |
| 7 | **Skills** → **Commit changes in Xcode** | Timeline shows **Saved / Updated** + app; no Was/Now, no quoted phrases |
| 8 | **Ask Clicky why** on any memory with receipts | Still works below timeline |

### Live path (optional, end-to-end)

1. In a session, state a preference (“keep answers short”).
2. In a later session, correct it (“go deeper when explaining code”) so dedup **updates** the same memory.
3. Open that memory in the library → timeline shows both saves with Was → Now and both phrases.

### Automated tests

- Xcode: **Cmd+U** (or run `MemoryDiffTimelineTests` only).
- Covers: snapshot capture, legacy JSON decode, 2+ saves rule, ordering, diff derivation, skill activity style.

### Regression checks

- [ ] Single-receipt memories: no timeline
- [ ] Timeline collapsed by default; chevron toggles expand
- [ ] Header shows pointer cursor and hover feedback
- [ ] Panel stays usable at 320pt width (no horizontal scroll)
- [ ] Receipt card (“Why Clicky saved this”) unchanged in behavior

---

## Files touched (for reviewers)

| Area | File |
|------|------|
| Snapshots on receipt | `MemoryReceipt.swift`, `CompanionManager.swift` |
| Timeline builder | `MemoryDiffTimeline.swift` |
| UI | `MemoriesLibraryView.swift` |
| Demo seeds | `DummyMemorySeeder.swift` |
| Tests | `leanring-buddyTests/MemoryDiffTimelineTests.swift` |
