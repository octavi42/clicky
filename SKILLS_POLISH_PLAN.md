# Skills Polish — Feature Plan

**Branch:** `feature/skills-polish`
**Worktree:** `/Users/cristeaoctavian/Projects/clicky-skills-polish`
**Status:** Implemented (roadmap doc skipped — not present in this worktree)

---

## What this feature is

A polish pass on the existing teaching-skills subsystem (capture → match → inject →
curate already ship). It makes learned skills fire at the right time, makes it visible
to the user when a learned skill is applied, and stops near-duplicate skills from piling
up. No new memory infrastructure — this sharpens what already exists.

## Scope decisions (what we build vs. skip)

Decided after researching 2026 agent-memory best practices, scoped down to a single-user,
local, menu-bar app.

### In scope (done)
1. **Trigger phrases as activation keys** — `triggers` YAML field, synthesizer emits phrases, matcher +20 boost.
2. **"Using what you learned" chip** — cursor overlay chip during `.responding` when skills matched.
3. **Patch over duplicate** — `findSkillForUpdate` uses trigger matching + overlap threshold 1.
4. **Recency + trust scoring** — recency boost from `lastUsed`, `confirmedSuccessCount` on confirm.
5. **Lightweight supersession** — `previousBody` + `supersededAt` marker in `SKILL.md` on patch/merge.

### Explicitly cut (overkill for this app's scale)
- Full progressive disclosure with `references/` sub-files and <500-line body machinery (skills are tiny; adopt only the spirit — good `name`/`description` + triggers).
- Full temporal-edge model (`validAt`/`invalidAt`, interval-tree indexes, "what was true in March").
- Knowledge graph / tri-store (vector + graph + episodic).
- RL-learned memory controllers (AgeMem/MemGPT) and async multi-queue extraction pipelines.

---

## Detailed implementation

### 1. Trigger phrases as activation keys
**Files:** `TeachingSkill.swift`, `SkillSynthesizer.swift`, `SkillMatcher.swift`

- Add a `triggers: [String]` field to `TeachingSkill`, parsed from YAML frontmatter
  (mirror how `usageCount` is parsed/serialized in `TeachingSkill.swift`).
- Have `SkillSynthesizer` ask Claude to emit a few natural trigger phrases when drafting
  a skill, written into the skill's frontmatter.
- In `SkillMatcher.matchSkills`, add a large score boost when a trigger phrase appears in
  the transcript (stronger signal than the current name/description/body token overlap).

### 2. "Using what you learned" chip
**Files:** `CompanionManager.swift`, `CompanionResponseOverlay.swift`, `OverlayWindow.swift`

- `CompanionManager` already computes `lastMatchedSkillNames` (~line 992). Promote it to a
  `@Published` value (or a dedicated "skill applied" flag).
- Render a small chip near the response bubble in the overlay (e.g. "✨ using what you
  learned") whenever a skill was applied to the current response. Fade it out with the
  response. UI-only addition; respect the `DS` design system.

### 3. Patch over duplicate
**Files:** `SkillMatcher.swift`, `SkillCurator.swift`, `CompanionManager.swift`

- At write time, `CompanionManager.maybeWriteTeachingSkill` already calls
  `SkillMatcher.findSkillForUpdate`. Tighten the update-vs-create decision (loosen the
  match threshold / reuse trigger-phrase matching) so near-duplicates patch the existing
  skill rather than creating a new one.
- Keep `SkillCurator.mergeOneDuplicatePairIfNeeded` as the after-the-fact safety net.

### 4. Recency + trust scoring (bolt-on)
**Files:** `SkillMatcher.swift`

- Blend a relevance score beyond raw `usageCount`: weight recently used skills and skills
  applied in sessions the user confirmed worked. Keep it cheap — no new storage beyond a
  success/confirmation signal already available in the session trace.

### 5. Lightweight supersession (bolt-on)
**Files:** `TeachingSkill.swift`, `SkillCurator.swift`

- When the curator patches or merges, do not hard-delete the old body. Keep one
  `previousBody` + a `supersededAt` date in the same `SKILL.md`. The 80/20 of temporal
  validity without timestamped edges or a graph.

---

## Suggested build sequence

1. Trigger phrases (#1) — foundation for matching and patch decisions.
2. Recency + trust scoring (#4) — small matcher change, pairs with #1.
3. "Using what you learned" chip (#2) — independent UI win.
4. Patch over duplicate (#3) + lightweight supersession (#5) — together in the curator/write path.

## Notes / constraints
- Do NOT run `xcodebuild` from the terminal (invalidates TCC permissions). Build via Xcode.
- Follow the repo naming/clarity conventions in `AGENTS.md` / `CLAUDE.md`.
- Roadmap doc update skipped — `docs/architecture/MEMORY_ROADMAP.md` not in this worktree.
