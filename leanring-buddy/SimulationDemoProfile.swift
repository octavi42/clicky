//
//  SimulationDemoProfile.swift
//  leanring-buddy
//
//  Demo profiles ("work styles") for the presenter-only Clicky Memory Demo.
//  Each profile is a deterministic fixture set: teaching skills, preference
//  and routine memories, and repeated app-transition edges. Loading a profile
//  shows what Clicky feels like after it has learned from that kind of user.
//
//  All IDs are prefixed "demo-" so demo state is clearly distinguishable from
//  organically learned memories, and all dates are relative to "now" so the
//  fixtures always land inside rolling retention windows.
//

import Foundation

/// One repeated app-to-app transition pattern to seed into the ActivityStore.
/// Seeded across multiple distinct days so RoutineDetector's recurrence rules
/// (minimum distinct days, minimum strength) treat it as a real habit.
struct SimulationDemoAppTransitionSeed {
    let fromBundleId: String
    let toBundleId: String
    let transitionsPerDay: Int
    let distinctDays: Int
}

/// The simulated frontmost-app context a demo profile starts in. Shown in the
/// Demo State section; later increments will feed it into routine chips and
/// app-aware niche suggestions.
struct SimulationDemoAppContext {
    let bundleId: String
    let displayName: String
}

enum SimulationDemoProfile: String, CaseIterable, Identifiable {
    case developer
    case contentCreator
    case designer
    case student

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .developer: return "Developer"
        case .contentCreator: return "Creator"
        case .designer: return "Designer"
        case .student: return "Student"
        }
    }

    /// The niche override applied when this profile loads, so the dropdown's
    /// niche suggestions align with the demo story.
    var matchingNiche: NicheDiscoveryManager.Niche {
        switch self {
        case .developer: return .developer
        case .contentCreator: return .contentCreator
        case .designer: return .designer
        case .student: return .student
        }
    }

    var simulatedAppContext: SimulationDemoAppContext {
        switch self {
        case .developer:
            return SimulationDemoAppContext(bundleId: "com.apple.dt.Xcode", displayName: "Xcode")
        case .contentCreator:
            return SimulationDemoAppContext(bundleId: "com.apple.FinalCut", displayName: "Final Cut Pro")
        case .designer:
            return SimulationDemoAppContext(bundleId: "com.figma.Desktop", displayName: "Figma")
        case .student:
            return SimulationDemoAppContext(bundleId: "com.apple.Notes", displayName: "Notes")
        }
    }

    /// The three Ask Clicky chips shown while this profile is loaded. Each
    /// profile reuses the universal recall + routine asks but swaps the
    /// middle chip for a workflow repeat that matches its primary skill.
    var askClickyQuickActionPrompts: [AskClickyQuickActionPrompt] {
        switch self {
        case .developer:
            return [
                .whatDidYouLearnAboutMe,
                AskClickyQuickActionPrompt(
                    kind: .repeatPrimaryWorkflow,
                    promptText: "Help me commit in Xcode again",
                    workflowBundleId: "com.apple.dt.Xcode",
                    primaryWorkflowSkillId: "demo-skill-xcode-commit",
                    primaryWorkflowScriptedAnswer: "Same as last time: ⌘2 for Source Control, check your files, write the message, hit ⌘⏎. You've got this."
                ),
                .whatShouldIDoNextInThisApp,
            ]
        case .contentCreator:
            return [
                .whatDidYouLearnAboutMe,
                AskClickyQuickActionPrompt(
                    kind: .repeatPrimaryWorkflow,
                    promptText: "Help me export this video in Final Cut again",
                    workflowBundleId: "com.apple.FinalCut",
                    primaryWorkflowSkillId: "demo-skill-finalcut-export",
                    primaryWorkflowScriptedAnswer: "Same as last time: ⌘E for Share Master File, pick the 4K preset, choose a destination, hit Save."
                ),
                .whatShouldIDoNextInThisApp,
            ]
        case .designer:
            return [
                .whatDidYouLearnAboutMe,
                AskClickyQuickActionPrompt(
                    kind: .repeatPrimaryWorkflow,
                    promptText: "Help me create a component in Figma again",
                    workflowBundleId: "com.figma.Desktop",
                    primaryWorkflowSkillId: "demo-skill-figma-component",
                    primaryWorkflowScriptedAnswer: "Same as last time: select the frame, ⌥⌘K to componentize, then drag instances from Assets (⌥2)."
                ),
                .whatShouldIDoNextInThisApp,
            ]
        case .student:
            return [
                .whatDidYouLearnAboutMe,
                AskClickyQuickActionPrompt(
                    kind: .repeatPrimaryWorkflow,
                    promptText: "Help me summarize this lecture in Notes again",
                    workflowBundleId: "com.apple.Notes",
                    primaryWorkflowSkillId: "demo-skill-notes-lecture-summary",
                    primaryWorkflowScriptedAnswer: "Same as last time: new note with the course and date, Key Ideas / Definitions / Questions headings, one sentence per bullet."
                ),
                .whatShouldIDoNextInThisApp,
            ]
        }
    }

    /// Generic Ask Clicky chips at baseline (no profile loaded). The middle
    /// chip stays vague because there is no primary workflow to repeat yet.
    static let baselineAskClickyQuickActionPrompts: [AskClickyQuickActionPrompt] = [
        .whatDidYouLearnAboutMe,
        AskClickyQuickActionPrompt(
            kind: .repeatPrimaryWorkflow,
            promptText: "Help me with that workflow again",
            workflowBundleId: nil,
            primaryWorkflowSkillId: nil,
            primaryWorkflowScriptedAnswer: nil
        ),
        .whatShouldIDoNextInThisApp,
    ]

    // MARK: - Fixtures

    var demoSkills: [TeachingSkill] {
        switch self {
        case .developer:
            return [
                TeachingSkill(
                    id: "demo-skill-xcode-commit",
                    name: "Commit changes in Xcode",
                    description: "Stage and commit current changes via the Source Control navigator",
                    bundleIds: ["com.apple.dt.Xcode"],
                    status: .active,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(2),
                    usageCount: 3,
                    isPinned: false,
                    taskSlug: "commit",
                    body: """
                    1. Open the **Source Control** navigator (⌘2).
                    2. Review changed files and check the ones to include.
                    3. Enter a commit message and press **⌘⏎** to commit.
                    """
                ),
                TeachingSkill(
                    id: "demo-skill-xcode-fix-preview",
                    name: "Fix a stuck SwiftUI preview in Xcode",
                    description: "Recover a SwiftUI preview that stopped updating",
                    bundleIds: ["com.apple.dt.Xcode"],
                    status: .active,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(4),
                    usageCount: 2,
                    isPinned: false,
                    taskSlug: "fix-preview",
                    body: """
                    1. Press **⌥⌘P** to resume the preview.
                    2. If it stays stuck, choose **Product → Clean Build Folder** (⇧⌘K).
                    3. Re-open the canvas with **⌥⌘⏎**.
                    """
                ),
            ]
        case .contentCreator:
            return [
                TeachingSkill(
                    id: "demo-skill-finalcut-export",
                    name: "Export a video in Final Cut Pro",
                    description: "Share the current project as a 4K master file",
                    bundleIds: ["com.apple.FinalCut"],
                    status: .active,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(1),
                    usageCount: 4,
                    isPinned: false,
                    taskSlug: "export",
                    body: """
                    1. Click **File → Share → Master File** (⌘E).
                    2. Pick the 4K preset in the Settings tab.
                    3. Click **Next**, choose a destination, and click **Save**.
                    """
                ),
                TeachingSkill(
                    id: "demo-skill-notes-script-outline",
                    name: "Outline a video script in Notes",
                    description: "Structure a new video script with sections and checklists",
                    bundleIds: ["com.apple.Notes"],
                    status: .active,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(3),
                    usageCount: 2,
                    isPinned: false,
                    taskSlug: "script-outline",
                    body: """
                    1. Create a new note (⌘N) and title it with the video name.
                    2. Add Hook / Intro / Body / Outro headings.
                    3. Use checklists (⇧⌘L) for shot ideas under each heading.
                    """
                ),
            ]
        case .designer:
            return [
                TeachingSkill(
                    id: "demo-skill-figma-component",
                    name: "Create a component in Figma",
                    description: "Turn a frame into a reusable component",
                    bundleIds: ["com.figma.Desktop"],
                    status: .active,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(1),
                    usageCount: 5,
                    isPinned: false,
                    taskSlug: "create-component",
                    body: """
                    1. Select the frame to reuse.
                    2. Press **⌥⌘K** to create the component.
                    3. Drag instances from the Assets panel (⌥2).
                    """
                ),
                TeachingSkill(
                    id: "demo-skill-figma-export-assets",
                    name: "Export assets from Figma",
                    description: "Export selected layers as PNG and SVG",
                    bundleIds: ["com.figma.Desktop"],
                    status: .active,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(5),
                    usageCount: 2,
                    isPinned: false,
                    taskSlug: "export-assets",
                    body: """
                    1. Select the layers to export.
                    2. In the right sidebar, click **+** next to Export.
                    3. Choose PNG or SVG and click **Export**.
                    """
                ),
            ]
        case .student:
            return [
                TeachingSkill(
                    id: "demo-skill-notes-lecture-summary",
                    name: "Summarize a lecture in Notes",
                    description: "Condense lecture notes into a structured summary",
                    bundleIds: ["com.apple.Notes"],
                    status: .active,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(1),
                    usageCount: 3,
                    isPinned: false,
                    taskSlug: "lecture-summary",
                    body: """
                    1. Create a new note (⌘N) titled with the course and date.
                    2. Add Key Ideas / Definitions / Questions headings.
                    3. Keep each bullet to one sentence.
                    """
                ),
                TeachingSkill(
                    id: "demo-skill-preview-annotate-pdf",
                    name: "Annotate a PDF in Preview",
                    description: "Highlight and add notes to a reading assignment",
                    bundleIds: ["com.apple.Preview"],
                    status: .active,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(3),
                    usageCount: 2,
                    isPinned: false,
                    taskSlug: "annotate-pdf",
                    body: """
                    1. Open the PDF and show the Markup toolbar (⇧⌘A).
                    2. Use the highlighter on key passages.
                    3. Add sticky notes with **Tools → Annotate → Note**.
                    """
                ),
            ]
        }
    }

    var demoAuxiliaryMemories: [Memory] {
        switch self {
        case .developer:
            return [
                Memory(
                    id: "demo-pref-short-answers",
                    category: .preference,
                    title: "Keep answers short",
                    summary: "Prefer 1-3 step answers over long explanations",
                    body: """
                    Favor short, numbered steps. Skip background explanation unless asked.
                    """,
                    usageCount: 3,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(2)
                ),
                Memory(
                    id: "demo-pref-keyboard-shortcuts",
                    category: .preference,
                    title: "Prefer keyboard shortcuts",
                    summary: "Lead with the shortcut, mention the menu path second",
                    body: """
                    When a task has a keyboard shortcut, give the shortcut first
                    (e.g. ⌘2 for Source Control) and the menu path as a fallback.
                    """,
                    usageCount: 2,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(2)
                ),
                Memory(
                    id: "demo-routine-linear-to-xcode",
                    category: .routine,
                    title: "Start coding from a Linear ticket",
                    summary: "Pick a ticket in Linear, then implement it in Xcode",
                    body: """
                    1. Pick the next ticket in Linear and read the acceptance criteria.
                    2. Switch to Xcode and create a branch named after the ticket.
                    3. Implement, then commit referencing the ticket ID.
                    """,
                    bundleIds: ["com.apple.dt.Xcode"],
                    usageCount: 4,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(1)
                ),
            ]
        case .contentCreator:
            return [
                Memory(
                    id: "demo-pref-step-by-step",
                    category: .preference,
                    title: "One step at a time",
                    summary: "Give a single step, wait for confirmation, then continue",
                    body: """
                    Walk through workflows one step at a time instead of listing
                    everything upfront. Wait for "done" before the next step.
                    """,
                    usageCount: 3,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(1)
                ),
                Memory(
                    id: "demo-routine-publish-checklist",
                    category: .routine,
                    title: "Publish-day checklist",
                    summary: "Export, thumbnail, upload, then schedule the post",
                    body: """
                    1. Export the master file from Final Cut Pro.
                    2. Finalize the thumbnail.
                    3. Upload, fill metadata, and schedule for 6 PM.
                    """,
                    bundleIds: ["com.apple.FinalCut"],
                    usageCount: 5,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(2)
                ),
            ]
        case .designer:
            return [
                Memory(
                    id: "demo-pref-point-on-screen",
                    category: .preference,
                    title: "Point at things on screen",
                    summary: "Show locations visually instead of describing them",
                    body: """
                    When explaining UI, point the cursor at the exact control
                    instead of describing where it is in words.
                    """,
                    usageCount: 4,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(1)
                ),
                Memory(
                    id: "demo-routine-design-handoff",
                    category: .routine,
                    title: "Friday design handoff",
                    summary: "Tidy layers, export assets, share the Figma link",
                    body: """
                    1. Rename and group changed layers.
                    2. Export updated assets for engineering.
                    3. Drop the Figma link and changelog in the handoff thread.
                    """,
                    bundleIds: ["com.figma.Desktop"],
                    usageCount: 3,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(4)
                ),
            ]
        case .student:
            return [
                Memory(
                    id: "demo-pref-explain-simply",
                    category: .preference,
                    title: "Explain it simply first",
                    summary: "Start with a plain-language explanation, then the details",
                    body: """
                    Open with a one-sentence plain explanation before any
                    technical terms. Define new terms on first use.
                    """,
                    usageCount: 2,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(1)
                ),
                Memory(
                    id: "demo-routine-study-block",
                    category: .routine,
                    title: "Evening study block",
                    summary: "Review readings in Preview, then summarize in Notes",
                    body: """
                    1. Re-read highlighted passages in Preview.
                    2. Summarize each reading in the course note.
                    3. Add open questions to ask in the next class.
                    """,
                    bundleIds: ["com.apple.Notes"],
                    usageCount: 3,
                    lastUsed: SimulationDemoFixtureDates.daysAgo(2)
                ),
            ]
        }
    }

    /// Repeated transitions seeded into the ActivityStore. Counts are chosen
    /// to clear RoutineDetector's bars (>= 2 distinct days, strength >= 0.4)
    /// so the routine chip reliably appears in the demo.
    var demoAppTransitionSeeds: [SimulationDemoAppTransitionSeed] {
        switch self {
        case .developer:
            return [
                SimulationDemoAppTransitionSeed(
                    fromBundleId: "com.linear",
                    toBundleId: "com.apple.dt.Xcode",
                    transitionsPerDay: 3,
                    distinctDays: 3
                )
            ]
        case .contentCreator:
            return [
                SimulationDemoAppTransitionSeed(
                    fromBundleId: "com.apple.Notes",
                    toBundleId: "com.apple.FinalCut",
                    transitionsPerDay: 3,
                    distinctDays: 3
                )
            ]
        case .designer:
            return [
                SimulationDemoAppTransitionSeed(
                    fromBundleId: "com.apple.Safari",
                    toBundleId: "com.figma.Desktop",
                    transitionsPerDay: 3,
                    distinctDays: 3
                )
            ]
        case .student:
            return [
                SimulationDemoAppTransitionSeed(
                    fromBundleId: "com.apple.Safari",
                    toBundleId: "com.apple.Notes",
                    transitionsPerDay: 3,
                    distinctDays: 3
                )
            ]
        }
    }
}

enum SimulationDemoFixtureDates {
    static func daysAgo(_ dayCount: Int, from now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: -dayCount, to: now) ?? now
    }
}

/// Semantic kind behind one Ask Clicky chip. The spoken prompt text and
/// matcher inputs vary by loaded demo profile; the kind selects which
/// read-only answer path the engine runs.
enum AskClickyQuickActionKind: String, Equatable {
    case whatDidYouLearnAboutMe
    case repeatPrimaryWorkflow
    case whatShouldIDoNextInThisApp
}

/// One Ask Clicky chip: the prompt the presenter taps and the metadata the
/// engine needs to match skills / routines for that profile's story.
struct AskClickyQuickActionPrompt: Identifiable, Equatable {
    let kind: AskClickyQuickActionKind
    let promptText: String
    /// Bundle id fed to SkillMatcher for the workflow-repeat ask. nil at
    /// baseline when no profile defines a primary app yet.
    let workflowBundleId: String?
    /// When the top match has this skill id, the profile's scripted shortcut
    /// answer is spoken instead of the generic matched-skill line.
    let primaryWorkflowSkillId: String?
    let primaryWorkflowScriptedAnswer: String?

    var id: String { "\(kind.rawValue)-\(promptText)" }

    static let whatDidYouLearnAboutMe = AskClickyQuickActionPrompt(
        kind: .whatDidYouLearnAboutMe,
        promptText: "What did you learn about me?",
        workflowBundleId: nil,
        primaryWorkflowSkillId: nil,
        primaryWorkflowScriptedAnswer: nil
    )

    static let whatShouldIDoNextInThisApp = AskClickyQuickActionPrompt(
        kind: .whatShouldIDoNextInThisApp,
        promptText: "What should I do next in this app?",
        workflowBundleId: nil,
        primaryWorkflowSkillId: nil,
        primaryWorkflowScriptedAnswer: nil
    )
}
