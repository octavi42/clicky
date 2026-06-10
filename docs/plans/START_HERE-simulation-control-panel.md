# Start Here: Simulation Control Panel Worktree

Branch: `feature/simulation-control-panel`
Worktree: `/Users/cristeaoctavian/Projects/clicky-simulation-control-panel`
Data home: `/tmp/clicky-simulation-control-panel`

## Mission

Build a presenter-only **Clicky Memory Demo** panel for showing the learning-companion fork clearly in a meeting.

Core line:

> Clicky already helps you once. This fork makes Clicky better the next time.

This is not an end-user feature. It is a deterministic demo cockpit so the meeting does not depend on live speech recognition, network timing, screen state, or macOS permissions.

## Product Story

The demo should prove that Clicky is becoming a local learning companion:

- **Skills** are what Clicky teaches.
- **Preferences** are how Clicky teaches.
- **Routines** are when Clicky should help.
- **Niche suggestions** are where the user starts.
- **Demo profiles** show what Clicky feels like after it has learned from a user.

## Screen Shape

Create one presenter-only screen, likely reachable from the existing panel in DEBUG or behind a local/demo flag.

Sections:

- **Demo State**: current profile, loaded memory counts, simulated app context, last run status, reset action.
- **Feature Demo Cards**: skills, preferences, routines, niche suggestions. Each card has a run action, a `?` explanation action, status, and proof fields.
- **Demo Profiles / Work Styles**: load Developer, Creator, Designer, Student, or clear profile.
- **Ask Clicky** quick actions: "What did you learn about me?", "Help me commit in Xcode again", "What should I do next in this app?"
- **Proof Panel**: last memory written, last matched memory, prompt sections included, simulated before/after metrics.

Important rule: the `?` explanation action must not mutate demo state. It only explains what the scenario proves.

## Required Demo Cases

### Skills: Xcode Commit Flow

Proves Clicky learns a successful screen workflow and reuses it.

Flow:

1. Simulate "Help me commit my current Xcode changes."
2. Simulate first-time guidance.
3. Simulate "Got it, thanks, that worked."
4. Save or update a demo skill.
5. Simulate "Help me commit in Xcode again."
6. Show the saved skill matched and the response became more specific.

Proof fields:

- `Skill saved: Xcode commit flow`
- `Skill matched: Yes`
- `Prompt included teaching skills: Yes`
- `Turns to success: 4 -> 1`

### Preferences: Short Answers + Keyboard Shortcuts

Proves Clicky learns how the user wants to be taught.

Flow:

1. Simulate "From now on, keep answers short and prefer keyboard shortcuts."
2. Save preference memory.
3. Ask a normal screen-help question.
4. Show Clicky answering in the preferred style.

### Routines: Linear -> Xcode

Proves Clicky notices repeated work patterns and can surface lightweight suggestions.

Flow:

1. Populate activity edges for repeated app transitions.
2. Simulate app context: user opens Xcode after Linear.
3. Show routine chip: `You often open Xcode after Linear`.
4. Optionally ask "What should I do next in this app?"

### Niche Suggestions: Developer + Xcode

Proves Clicky helps users know what to ask before it has learned much.

Show app-aware suggested asks such as:

- "Walk me through committing these changes"
- "Explain this build error"
- "Help me fix this SwiftUI preview"
- "Explain what changed in this file"

## Likely Implementation Areas

Prefer reusing existing local/demo seams:

- `CompanionPanelView.swift` for panel UI and cards.
- `CompanionManager.swift` for demo actions and prompt/simulation hooks.
- `ClickyPaths.swift` and `CLICKY_HOME` for isolated demo state.
- `TeachingSkillStore.swift` for demo skills.
- `AuxiliaryMemoryStore.swift` for demo preferences and routines.
- `ActivityStore.swift` and `RoutineDetector.swift` for routine chips.
- `NicheDiscoveryManager.swift` and niche resources for app-aware suggestions.
- `ClickyE2EConfiguration.swift` for launch flags if the panel should be demo-only.
- Existing `DS` design system for card styling.

## Guardrails

- Keep it deterministic and presenter-only.
- Label metrics as simulated demo metrics.
- Use "Demo Profiles" or "Work Styles", not psychological "personality" claims.
- Avoid cloud sync or broad surveillance.
- Do not put API keys in the app.
- Do not run `xcodebuild` from terminal; use Xcode Cmd+R/Cmd+U.
- Preserve the `leanring-buddy` project typo.

## Done Definition

- A future agent can open this worktree and implement the demo panel without needing old chat context.
- The demo can show skills, preferences, routines, niche suggestions, and profiles from deterministic local state.
- The presenter can reset the demo to a known baseline.
- The "what did you learn about me?" moment works from loaded demo memories.
