# Start Here: Roadmap Ideas Implementation Worktree

Branch: `feature/roadmap-ideas`
Worktree: `/Users/cristeaoctavian/Projects/clicky-roadmap-ideas`
Data home: `/tmp/clicky-roadmap-ideas`

## Status

| # | Task | Status | Branch / PR |
|---|------|--------|-------------|
| 1 | Memory Receipts | **Done** (merged 2026-06-10) | `feature/memory-receipts` → [PR #14](https://github.com/octavi42/clicky/pull/14) |
| 2 | What Did You Learn About Me? | **Done** (implemented 2026-06-10) | `feature/what-did-you-learn` |
| 3 | Memory Diff Timeline | **Next** | `feature/memory-diff-timeline` |
| 4 | Daily Brain Digest | Pending | `feature/daily-brain-digest` |
| 5 | Memory Hygiene Coach | Pending | `feature/memory-hygiene-coach` |
| 6 | Unique Stuff You Do | Pending | `feature/unique-behavior-insights` |
| 7 | Native Tasks / Timer | Pending | `feature/context-tasks-timer` |

## Mission

Implement the Brain roadmap ideas that deepen Clicky as a trustworthy local learning companion.

This worktree is for building the product ideas from the local brain note `~/.clicky/brain/CLICKY_FORK_ROADMAP.md`, not the presenter-only simulation panel.

Product thesis:

> Clicky should become a local learning brain for the Mac: it watches useful teaching moments, remembers them with proof, explains what it learned, and helps the user maintain that memory over time.

## Ranked Feature List

### 1. Memory Receipts — **DONE** (PR #14, 2026-06-10)

Working title: **Why did Clicky save this?**

**Shipped:** Receipt capture at distill time (`MemoryReceipt.swift`), persistence on skills (sidecar) and preferences/routines (JSON), receipt card in `MemoriesLibraryView`, voice-only **Ask Clicky why** with grounded Claude + fallbacks, unit tests in `MemoryReceiptTests.swift`.

Clicky should be able to explain how it concluded that a skill, preference, routine, or memory was worth saving.

For each saved memory, preserve or retrieve:

- Source session or transcript snippet.
- App or bundle ID.
- User phrase that triggered the save.
- Gate reason: user confirmed, repeated topic, stated preference, style correction, recurring routine, etc.
- Whether the user confirmed the help worked.
- Date learned and last used date.
- Confidence or evidence strength.
- Related memory or skill IDs.

Likely implementation areas:

- `PersistedSession.swift`
- `SessionStore.swift`
- `MemoryGate.swift`
- `TeachingSkillStore.swift`
- `AuxiliaryMemoryStore.swift`
- `Memory.swift`
- `TeachingSkill.swift`
- `MemoriesLibraryView.swift`
- `TeachingSkillsLibraryView.swift`

### 2. What Did You Learn About Me? — **DONE** (2026-06-10)

**Shipped:** Deterministic voice-intent detection + grounded summary prompt builder (`SelfKnowledgeSummary.swift`), shared composer with deterministic/empty-state fallbacks in `CompanionManager.composeSelfKnowledgeSummaryText`, voice intercept in the response pipeline (text-only, no screenshots, wins over vault retrieval), "What did you learn about me?" button in the Brain tab memories card, unit tests in `SelfKnowledgeSummaryTests.swift`. Voice-only delivery.

Add a voice query and Brain tab card that summarizes what Clicky currently knows about the user.

The answer must be grounded in active local data:

- Preferences.
- Teaching skills.
- Recurring routines.
- Niche profile.
- Connected vault signals, only when relevant and opted in.

Likely implementation areas:

- `CompanionManager.swift` for recognizing/responding to the query.
- `TeachingSkillStore.swift` and `AuxiliaryMemoryStore.swift` for retrieval.
- `NicheDiscoveryManager.swift` for niche context.
- `PersonalKnowledgeManager.swift` for opt-in vault signals.
- `MemoriesLibraryView.swift` or a Brain section in `CompanionPanelView.swift`.

### 3. Memory Diff Timeline

Show how memories changed over time, especially preferences and routines.

Example:

- Old preference: "keep answers short."
- New preference: "go deeper when explaining code."
- Reason: user corrected Clicky during a later session.
- Current behavior: latest preference wins.

Likely implementation areas:

- Store previous versions on memory update in `AuxiliaryMemoryStore.swift`.
- Extend `Memory.swift` with version or receipt metadata if needed.
- Show version history in `MemoriesLibraryView.swift`.
- Link each version to receipt/source evidence.

### 4. Daily Brain Digest

Create a daily or launch-time summary of what Clicky learned and noticed.

Possible digest sections:

- New skills learned.
- Preferences updated.
- Routines detected.
- Vault notes saved or referenced.
- Memories needing cleanup.
- Suggested next actions.

Likely implementation areas:

- `SessionStore.swift`
- `TeachingSkillStore.swift`
- `AuxiliaryMemoryStore.swift`
- `ActivityStore.swift`
- `RoutineDetector.swift`
- `PersonalKnowledgeManager.swift`
- A new digest model/store if the digest is persisted as Markdown.

Start manually triggered or opt-in. Do not make this feel like surveillance.

### 5. Memory Hygiene Coach

Clicky should help maintain its memory store.

Detect:

- Stale skills.
- Conflicting preferences.
- Duplicate memories.
- Routines that no longer occur.
- Low-confidence memories needing review.

Suggested actions:

- Keep.
- Archive.
- Merge.
- Edit.
- Delete.
- Ask Clicky to refresh this skill.

Likely implementation areas:

- `SkillCurator.swift`
- `SkillMatcher.swift`
- `AuxiliaryMemoryMatcher.swift`
- `PreferenceConflictDetector.swift`
- `MemorySimilarityScorer.swift`
- `TeachingSkillStore.swift`
- `AuxiliaryMemoryStore.swift`
- `MemoriesLibraryView.swift`
- `TeachingSkillsLibraryView.swift`

### 6. Unique Stuff You Do

Turn repeated local workflow patterns into explainable behavior insights.

Examples:

- "You usually open Terminal after Xcode when debugging."
- "You ask for keyboard shortcuts more often than menu walkthroughs."
- "You often return to the same export workflow in Final Cut."
- "You tend to ask for help after switching from browser docs to Xcode."

Likely implementation areas:

- `ActivityStore.swift`
- `RoutineDetector.swift`
- `TeachingTopicHistoryStore.swift`
- Skill and memory usage metadata.

Keep this local, reviewable, and evidence-backed.

### 7. Native Ready Apps: Task Manager Or Timer

Lower priority unless tied to Clicky's memory and workflow context.

Good version:

- Start a focus timer for the current app or workflow.
- Create a task from a Clicky teaching session.
- Convert a repeated routine into a checklist.
- Remind the user to finish an interrupted workflow.

Avoid building a generic task manager or timer that is not differentiated.

## Recommended Build Order

1. ~~Memory Receipts.~~ **Done**
2. ~~What Did You Learn About Me?~~ **Done**
3. Memory Diff Timeline. ← **start here**
4. Daily Brain Digest.
5. Memory Hygiene Coach.
6. Unique Behavior Insights.
7. Native Tasks or Timer, only if made context-aware.

## Strongest Demo Flow

1. User asks Clicky for help in an app.
2. Clicky teaches and points.
3. User confirms it worked.
4. Clicky saves a skill or preference.
5. User asks, "why did you save this?"
6. Clicky shows the receipt: transcript, app, gate reason, and confirmation.
7. User asks, "what did you learn about me?"
8. Clicky summarizes active memories with confidence and source evidence.

## Git Workflow

One roadmap task at a time. Keep `main` releasable and the commit graph readable.

1. `git checkout main && git pull`
2. `git checkout -b feature/<task-slug>`
3. Commit often with `brain(<slice>):` prefixes
4. When satisfied: `git merge --no-ff feature/<task-slug>` into `main`
5. Start the next task from updated `main`

Prefer `--no-ff` merges (not squash) so every commit stays visible inside a merge bubble per task.

| Task | Branch | Status |
|------|--------|--------|
| Memory Receipts | `feature/memory-receipts` | Done (PR #14) |
| What Did You Learn About Me? | `feature/what-did-you-learn` | Done (implemented 2026-06-10) |
| Memory Diff Timeline | `feature/memory-diff-timeline` | **Next** |
| Daily Brain Digest | `feature/daily-brain-digest` | Pending |
| Memory Hygiene Coach | `feature/memory-hygiene-coach` | Pending |
| Unique Stuff You Do | `feature/unique-behavior-insights` | Pending |
| Native Tasks / Timer | `feature/context-tasks-timer` | Pending |

Cursor rule: `.cursor/rules/roadmap-ideas-git-workflow.mdc`

## Guardrails

- Lead with the learning-companion product story, not implementation details.
- Keep memory local-first and user-inspectable.
- Avoid silent broad surveillance.
- Do not add cloud sync without explicit direction.
- Do not put API keys in the app.
- Do not run `xcodebuild` from terminal; use Xcode Cmd+R/Cmd+U.
- Preserve the `leanring-buddy` project typo.

## Done Definition For Future Agents

- Agents can start from this file and understand the roadmap implementation direction.
- ~~The first implementation slice should make saved memory explainable with evidence.~~ **Shipped** — see `MemoryReceipt.swift`, `MemoriesLibraryView` receipt section, `CompanionManager.explainWhyMemoryWasSaved`.
- ~~What Did You Learn About Me? — voice query + Brain tab summary grounded in active local memories.~~ **Shipped** — see `SelfKnowledgeSummary.swift`, `CompanionManager.speakWhatClickyLearnedAboutMe`, Brain tab button in `CompanionPanelView`.
- Features should build on existing stores and UI instead of inventing a parallel memory system.
- **Next task:** Memory Diff Timeline — version history on memory updates with receipt-linked evidence in `MemoriesLibraryView`.
