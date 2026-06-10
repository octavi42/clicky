//
//  SimulationDemoEngine.swift
//  leanring-buddy
//
//  Deterministic state engine behind the presenter-only Clicky Memory Demo.
//  Owns reset-to-baseline and demo-profile loading over the SAME store
//  instances CompanionManager uses, so seeded memories immediately show up
//  in the Brain tab, prompt building, and routine detection without any
//  cross-instance cache drift.
//
//  Baseline = completely empty stores: a Clicky that hasn't learned anything
//  yet. Loading a profile always resets first, so the result of "load
//  Developer" is identical every single time, regardless of what ran before.
//

import Foundation
import Combine

/// Lifecycle of the scripted Skills demo run shown on the Skills feature card.
enum SkillsDemoRunState: Equatable {
    case notRun
    case running
    case finished(atTimeDescription: String)

    var isRunning: Bool {
        self == .running
    }
}

/// One conversation beat rendered on the demo stage. A demo run is a paced
/// sequence of these; the stage view renders each kind differently (user
/// bubble, Clicky bubble, system pill, time gap divider, recap strip).
///
/// The same beats are designed to be replayable onto the real cursor overlay
/// later ("theater mode") — only the renderer changes, never the script.
enum DemoConversationBeat: Equatable {
    /// Right-aligned user bubble, as if spoken via push-to-talk.
    case userSays(text: String)
    /// Left-aligned Clicky bubble. `matchedSkillBadge` renders a small
    /// "Matched: <skill name>" tag under the bubble when a saved skill
    /// informed this response.
    case clickyResponds(text: String, matchedSkillBadge: String?)
    /// Centered pill marking a real engine event (skill saved, no match…).
    case systemEvent(iconSystemName: String, label: String, detail: String?)
    /// Centered hairline divider with a label like "Next day…".
    case timeGap(label: String)
    /// Emphasized full-width summary strip closing the run.
    case recap(text: String)

    /// Whether the stage should show the typing indicator before this beat
    /// lands (only Clicky's bubbles "think" first).
    var showsTypingIndicatorFirst: Bool {
        if case .clickyResponds = self { return true }
        return false
    }
}

/// A stage beat with a stable identity for SwiftUI list rendering.
struct DemoStageBeat: Identifiable, Equatable {
    let id: Int
    let beat: DemoConversationBeat
}

/// One step of a demo script. Producing the beat runs the step's real side
/// effects (store writes, matcher runs, prompt builds, proof updates) inside
/// the closure, so each mutation fires at exactly its beat — never earlier,
/// never later. Beat content can therefore depend on side-effect results
/// (e.g. the matched-skill badge).
struct DemoScriptStep {
    let performSideEffectsAndProduceBeat: @MainActor () -> DemoConversationBeat
}

@MainActor
final class SimulationDemoEngine: ObservableObject {
    @Published private(set) var loadedDemoProfile: SimulationDemoProfile?
    @Published private(set) var demoSkillCount: Int = 0
    @Published private(set) var demoPreferenceCount: Int = 0
    @Published private(set) var demoRoutineMemoryCount: Int = 0
    @Published private(set) var simulatedAppContextDisplayName: String?
    @Published private(set) var lastRunStatusDescription: String = "Not run yet"

    // MARK: Skills demo run state

    @Published private(set) var skillsDemoRunState: SkillsDemoRunState = .notRun

    /// Skills-card proof fields, filled progressively as run steps complete.
    /// nil renders as an em dash placeholder in the cockpit.
    @Published private(set) var skillsDemoSavedSkillNameProof: String?
    @Published private(set) var skillsDemoSkillMatchedProof: String?
    @Published private(set) var skillsDemoPromptIncludedProof: String?
    @Published private(set) var skillsDemoTurnsToSuccessProof: String?

    // MARK: Demo stage playback state

    /// Beats currently on the stage, appended one at a time with pacing.
    @Published private(set) var stagePlaybackBeats: [DemoStageBeat] = []
    /// True while the stage shows Clicky's typing indicator (set just before
    /// each Clicky bubble lands).
    @Published private(set) var isClickyTypingOnStage: Bool = false
    /// Which demo currently owns the stage, e.g. "Skills · Xcode Commit Flow".
    @Published private(set) var stageDemoTitle: String?

    // MARK: Proof Panel fields (shared by all demo cards)

    @Published private(set) var lastMemoryWrittenDescription: String = "—"
    @Published private(set) var lastMatchedMemoryDescription: String = "—"
    @Published private(set) var promptSectionsIncludedDescription: String = "—"
    @Published private(set) var beforeAfterMetricDescription: String = "—"

    private var skillsDemoRunTask: Task<Void, Never>?

    private let teachingSkillStore: TeachingSkillStore
    private let auxiliaryMemoryStore: AuxiliaryMemoryStore
    private let activityStore: ActivityStore

    /// Set by CompanionManager right after it creates the engine. Used to
    /// refresh the published memories/suggestions the rest of the UI binds to
    /// after the engine mutates the underlying stores.
    weak var companionManager: CompanionManager?

    private let lastRunTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init(
        teachingSkillStore: TeachingSkillStore,
        auxiliaryMemoryStore: AuxiliaryMemoryStore,
        activityStore: ActivityStore
    ) {
        self.teachingSkillStore = teachingSkillStore
        self.auxiliaryMemoryStore = auxiliaryMemoryStore
        self.activityStore = activityStore
    }

    // MARK: - Demo Actions

    /// Wipes all learned state (skills, preference/routine memories, activity
    /// edges, niche override) so the presenter starts from a known-empty
    /// Clicky. Safe to run any number of times.
    func resetDemoStateToBaseline() {
        wipeAllStores()
        loadedDemoProfile = nil
        simulatedAppContextDisplayName = nil
        clearSkillsDemoRunPresentation()
        clearProofPanel()
        refreshCompanionManagerAfterStoreMutation()
        companionManager?.clearUserNicheOverride()
        refreshDemoStateCounts()
        lastRunStatusDescription = "Reset · \(lastRunTimeFormatter.string(from: Date()))"
    }

    /// Resets to baseline, then seeds the profile's fixture set. Resetting
    /// first keeps profile loads deterministic — the loaded state never
    /// depends on what was in the stores before.
    func loadDemoProfile(_ demoProfile: SimulationDemoProfile) {
        wipeAllStores()
        clearSkillsDemoRunPresentation()
        clearProofPanel()

        for demoSkill in demoProfile.demoSkills {
            do {
                try teachingSkillStore.saveSkill(demoSkill)
            } catch {
                print("⚠️ Demo engine failed to seed skill \(demoSkill.id): \(error)")
            }
        }

        for demoMemory in demoProfile.demoAuxiliaryMemories {
            do {
                try auxiliaryMemoryStore.save(demoMemory)
            } catch {
                print("⚠️ Demo engine failed to seed memory \(demoMemory.id): \(error)")
            }
        }

        seedAppTransitions(demoProfile.demoAppTransitionSeeds)

        loadedDemoProfile = demoProfile
        simulatedAppContextDisplayName = demoProfile.simulatedAppContext.displayName
        refreshCompanionManagerAfterStoreMutation()
        companionManager?.setUserNiche(demoProfile.matchingNiche)
        refreshDemoStateCounts()
        lastRunStatusDescription = "Loaded \(demoProfile.displayName) · \(lastRunTimeFormatter.string(from: Date()))"
    }

    func clearLoadedDemoProfile() {
        resetDemoStateToBaseline()
        lastRunStatusDescription = "Cleared profile · \(lastRunTimeFormatter.string(from: Date()))"
    }

    /// Recomputes the Demo State tile values from the live stores. Called by
    /// the panel on appear so counts are accurate even when memories were
    /// created outside the demo engine (e.g. a real voice session).
    func refreshDemoStateCounts() {
        demoSkillCount = teachingSkillStore.skills.count
        demoPreferenceCount = auxiliaryMemoryStore.memories(for: .preference).count
        demoRoutineMemoryCount = auxiliaryMemoryStore.memories(for: .routine).count
    }

    // MARK: - Skills Demo Run

    /// Plays the full "learn then reuse" Xcode commit arc as a conversation
    /// on the demo stage:
    ///
    /// 1. First session — the REAL SkillMatcher finds no commit skill, so
    ///    Clicky teaches from scratch over a 4-turn exchange.
    /// 2. A REAL skill is written to TeachingSkillStore (save pill on stage,
    ///    Brain tab shows it).
    /// 3. "Next day" — the re-ask. The REAL matcher finds the skill, the
    ///    REAL TeachingPromptBuilder injects its prompt section, and Clicky
    ///    answers in a single turn with a matched badge.
    ///
    /// Only the conversation text is scripted (the demo must not depend on
    /// speech or network); the store write, matching, and prompt assembly
    /// are the production code paths. The demo commit skill is deleted up
    /// front so every run replays the identical arc, even right after
    /// loading the Developer profile (which seeds that same skill).
    /// Calling this again (the stage Replay chip) restarts the run.
    func runSkillsDemo() {
        guard !skillsDemoRunState.isRunning else { return }

        clearSkillsDemoRunPresentation()
        skillsDemoRunState = .running

        skillsDemoRunTask = Task { [weak self] in
            await self?.performSkillsDemoRun()
        }
    }

    private func performSkillsDemoRun() async {
        stageDemoTitle = "Skills · Xcode Commit Flow"

        // Deterministic restart: forget the commit skill if a previous run or
        // the Developer profile seeded it.
        if teachingSkillStore.skill(withID: SkillsDemoScript.commitSkillId) != nil {
            try? teachingSkillStore.deleteSkill(id: SkillsDemoScript.commitSkillId)
            refreshCompanionManagerAfterStoreMutation()
            refreshDemoStateCounts()
        }

        await playDemoScript(makeSkillsDemoScript())
        guard !Task.isCancelled else { return }

        let finishedAtDescription = lastRunTimeFormatter.string(from: Date())
        skillsDemoRunState = .finished(atTimeDescription: finishedAtDescription)
        lastRunStatusDescription = "Skills demo · \(finishedAtDescription)"
    }

    /// The Skills demo as a conversation script. Side effects (matcher runs,
    /// the skill write, prompt build, proof updates) execute inside the beat
    /// producers, so each real operation fires exactly when its beat lands
    /// on stage. Conversation text is scripted; the operations are real.
    private func makeSkillsDemoScript() -> [DemoScriptStep] {
        // Shared mutable state between steps. A reference type so closures
        // created upfront all see values written by earlier steps (the
        // matcher step writes this; the final bubble reads it for its badge).
        final class SkillsDemoRunContext {
            var savedSkillIsTopMatch = false
        }
        let runContext = SkillsDemoRunContext()

        return [
            // First session: the user has never asked this before.
            DemoScriptStep {
                .userSays(text: SkillsDemoScript.firstAskTranscript)
            },
            DemoScriptStep { [self] in
                // Real matcher over the live store: proves nothing matches yet.
                let matchesBeforeSave = SkillMatcher.matchSkills(
                    from: teachingSkillStore.skills,
                    bundleId: SkillsDemoScript.xcodeBundleId,
                    transcript: SkillsDemoScript.firstAskTranscript
                )
                let commitSkillIsAlreadyKnown = matchesBeforeSave.contains { match in
                    match.skill.id == SkillsDemoScript.commitSkillId
                }
                return .systemEvent(
                    iconSystemName: "magnifyingglass",
                    label: commitSkillIsAlreadyKnown
                        ? "Unexpected: a commit skill was already in memory"
                        : "No saved skill matched — teaching from scratch",
                    detail: "SkillMatcher ran over the real store"
                )
            },
            DemoScriptStep {
                .clickyResponds(text: SkillsDemoScript.firstGuidanceResponse, matchedSkillBadge: nil)
            },
            DemoScriptStep {
                .userSays(text: SkillsDemoScript.followUpQuestionTranscript)
            },
            DemoScriptStep {
                .clickyResponds(text: SkillsDemoScript.followUpGuidanceResponse, matchedSkillBadge: nil)
            },
            DemoScriptStep {
                .userSays(text: SkillsDemoScript.confirmationTranscript)
            },
            DemoScriptStep {
                .clickyResponds(text: SkillsDemoScript.confirmationAcknowledgement, matchedSkillBadge: nil)
            },
            DemoScriptStep { [self] in
                // Real store write — the skill is on disk from this beat on.
                let freshlyLearnedCommitSkill = SkillsDemoScript.makeFreshlyLearnedXcodeCommitSkill()
                do {
                    try teachingSkillStore.saveSkill(freshlyLearnedCommitSkill)
                } catch {
                    print("⚠️ Skills demo failed to save the commit skill: \(error)")
                }
                refreshCompanionManagerAfterStoreMutation()
                refreshDemoStateCounts()

                skillsDemoSavedSkillNameProof = freshlyLearnedCommitSkill.name
                lastMemoryWrittenDescription = "Skill · \(freshlyLearnedCommitSkill.name) · \(lastRunTimeFormatter.string(from: Date()))"

                return .systemEvent(
                    iconSystemName: "brain",
                    label: "Skill saved · \(freshlyLearnedCommitSkill.name)",
                    detail: "Real write to the skills store — open the Brain tab to see it"
                )
            },

            // Second session: same ask, after Clicky has learned.
            DemoScriptStep {
                .timeGap(label: "Next day")
            },
            DemoScriptStep {
                .userSays(text: SkillsDemoScript.reAskTranscript)
            },
            DemoScriptStep { [self] in
                // Real matcher + real prompt builder: proves the saved skill
                // is found and injected into the voice system prompt.
                let matchesAfterSave = SkillMatcher.matchSkills(
                    from: teachingSkillStore.skills,
                    bundleId: SkillsDemoScript.xcodeBundleId,
                    transcript: SkillsDemoScript.reAskTranscript
                )
                runContext.savedSkillIsTopMatch =
                    matchesAfterSave.first?.skill.id == SkillsDemoScript.commitSkillId

                let voicePromptWithSkills = TeachingPromptBuilder.buildVoiceResponsePrompt(
                    basePrompt: SkillsDemoScript.demoBasePrompt,
                    matchedSkills: matchesAfterSave.map(\.skill)
                )
                let promptIncludedTeachingSkillsSection =
                    voicePromptWithSkills.contains("teaching skills:")

                if runContext.savedSkillIsTopMatch,
                   let savedCommitSkill = teachingSkillStore.skill(withID: SkillsDemoScript.commitSkillId) {
                    _ = try? teachingSkillStore.markUsed(savedCommitSkill)
                    refreshCompanionManagerAfterStoreMutation()
                }

                skillsDemoSkillMatchedProof = runContext.savedSkillIsTopMatch ? "Yes (top match)" : "No"
                skillsDemoPromptIncludedProof = promptIncludedTeachingSkillsSection ? "Yes" : "No"

                lastMatchedMemoryDescription = runContext.savedSkillIsTopMatch
                    ? "Skill · Commit changes in Xcode (top match)"
                    : "No match"
                promptSectionsIncludedDescription = promptIncludedTeachingSkillsSection
                    ? "base + teaching skills"
                    : "base only"

                return .systemEvent(
                    iconSystemName: "checkmark.seal",
                    label: runContext.savedSkillIsTopMatch
                        ? "Skill matched · injected into the prompt"
                        : "Unexpected: the saved skill did not match",
                    detail: "SkillMatcher + TeachingPromptBuilder ran for real"
                )
            },
            DemoScriptStep {
                .clickyResponds(
                    text: SkillsDemoScript.reAskResponse,
                    // Badge reflects the real matcher result from the
                    // previous step, not a hardcoded claim.
                    matchedSkillBadge: runContext.savedSkillIsTopMatch
                        ? "Matched: Commit changes in Xcode"
                        : nil
                )
            },
            DemoScriptStep { [self] in
                skillsDemoTurnsToSuccessProof = "4 → 1 (simulated)"
                beforeAfterMetricDescription = "Turns to success: 4 → 1 (simulated demo metric)"
                return .recap(text: "First time: 4 turns → Next time: 1 turn (simulated demo metric)")
            },
        ]
    }

    // MARK: - Demo Script Player

    /// Plays a demo script beat by beat: runs the step's real side effects,
    /// shows the typing indicator before Clicky bubbles, appends the beat to
    /// the stage, and pauses so the presenter can narrate. Cancellation
    /// (reset / profile load / re-run) stops playback between beats.
    private func playDemoScript(_ demoScriptSteps: [DemoScriptStep]) async {
        for demoScriptStep in demoScriptSteps {
            guard !Task.isCancelled else { return }

            let beat = demoScriptStep.performSideEffectsAndProduceBeat()

            if beat.showsTypingIndicatorFirst {
                isClickyTypingOnStage = true
                await pause(nanoseconds: SkillsDemoScript.typingIndicatorNanoseconds)
                isClickyTypingOnStage = false
                guard !Task.isCancelled else { return }
            }

            stagePlaybackBeats.append(
                DemoStageBeat(id: stagePlaybackBeats.count, beat: beat)
            )

            await pause(nanoseconds: SkillsDemoScript.pacingAfterBeatNanoseconds)
        }
    }

    private func pause(nanoseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    private func clearSkillsDemoRunPresentation() {
        skillsDemoRunTask?.cancel()
        skillsDemoRunTask = nil
        skillsDemoRunState = .notRun
        skillsDemoSavedSkillNameProof = nil
        skillsDemoSkillMatchedProof = nil
        skillsDemoPromptIncludedProof = nil
        skillsDemoTurnsToSuccessProof = nil
        stagePlaybackBeats = []
        isClickyTypingOnStage = false
        stageDemoTitle = nil
    }

    private func clearProofPanel() {
        lastMemoryWrittenDescription = "—"
        lastMatchedMemoryDescription = "—"
        promptSectionsIncludedDescription = "—"
        beforeAfterMetricDescription = "—"
    }

    // MARK: - Store Mutation Helpers

    private func wipeAllStores() {
        // Reload first so the wipe also covers entries written by other code
        // paths (or a previous app run) that aren't in memory yet.
        teachingSkillStore.loadSkills()
        for skill in teachingSkillStore.skills {
            do {
                try teachingSkillStore.deleteSkill(id: skill.id)
            } catch {
                print("⚠️ Demo engine failed to delete skill \(skill.id): \(error)")
            }
        }

        auxiliaryMemoryStore.load()
        for memory in auxiliaryMemoryStore.memories {
            do {
                try auxiliaryMemoryStore.delete(id: memory.id)
            } catch {
                print("⚠️ Demo engine failed to delete memory \(memory.id): \(error)")
            }
        }

        activityStore.removeAllActivity()
    }

    /// Replays each transition seed across its distinct days, spread over the
    /// last `distinctDays` calendar days ending today. Timestamps are noon
    /// minus the day offset so they always fall inside ActivityStore's
    /// 30-day rolling window and never straddle a midnight boundary.
    private func seedAppTransitions(_ transitionSeeds: [SimulationDemoAppTransitionSeed]) {
        let calendar = Calendar.current
        let todayAtNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()

        for transitionSeed in transitionSeeds {
            for dayOffset in 0..<transitionSeed.distinctDays {
                guard let transitionDay = calendar.date(
                    byAdding: .day,
                    value: -dayOffset,
                    to: todayAtNoon
                ) else { continue }

                for _ in 0..<transitionSeed.transitionsPerDay {
                    activityStore.recordTransition(
                        from: transitionSeed.fromBundleId,
                        to: transitionSeed.toBundleId,
                        at: transitionDay
                    )
                }
            }
        }
    }

    /// Pushes the mutated store contents into CompanionManager's published
    /// state: teaching skills, the unified memories list, and routine chips.
    private func refreshCompanionManagerAfterStoreMutation() {
        companionManager?.refreshTeachingSkills()
        companionManager?.refreshRoutineSuggestions()
    }
}

/// The deterministic script behind the Skills demo run. All conversation
/// text is fixed so the demo never depends on speech recognition or network;
/// only the store write, matching, and prompt assembly are live.
private enum SkillsDemoScript {
    static let commitSkillId = "demo-skill-xcode-commit"
    static let xcodeBundleId = "com.apple.dt.Xcode"

    // First session: 4 turns to success (simulated conversation).
    static let firstAskTranscript = "Help me commit my current Xcode changes"
    static let firstGuidanceResponse = "Sure — open the Source Control navigator with ⌘2. You'll see your changed files listed on the left."
    static let followUpQuestionTranscript = "Okay, I see them. Where do I write the message?"
    static let followUpGuidanceResponse = "Check the files you want included, then click the message field at the top and describe the change. When you're ready, press ⌘⏎ to commit."
    static let confirmationTranscript = "Got it, thanks, that worked"
    static let confirmationAcknowledgement = "Nice! I'll remember this flow for next time."

    // Second session: 1 turn, informed by the saved skill.
    static let reAskTranscript = "Help me commit in Xcode again"
    static let reAskResponse = "Same as last time: ⌘2 for Source Control, check your files, write the message, hit ⌘⏎. You've got this."

    /// Short stand-in for the production voice system prompt. The proof is
    /// about whether TeachingPromptBuilder appends the teaching-skills
    /// section, which works identically regardless of the base prompt text.
    static let demoBasePrompt = "you are clicky, a voice screen tutor. answer briefly."

    /// How long Clicky's typing indicator shows before each of its bubbles.
    static let typingIndicatorNanoseconds: UInt64 = 900_000_000
    /// Pause after each beat lands, so the presenter can narrate.
    static let pacingAfterBeatNanoseconds: UInt64 = 1_100_000_000

    static func makeFreshlyLearnedXcodeCommitSkill() -> TeachingSkill {
        TeachingSkill(
            id: commitSkillId,
            name: "Commit changes in Xcode",
            description: "Stage and commit current changes via the Source Control navigator",
            bundleIds: [xcodeBundleId],
            status: .active,
            lastUsed: Date(),
            usageCount: 1,
            isPinned: false,
            taskSlug: "commit",
            triggers: ["commit in xcode", "commit my changes", "commit these changes"],
            body: """
            1. Open the **Source Control** navigator (⌘2).
            2. Review changed files and check the ones to include.
            3. Enter a commit message and press **⌘⏎** to commit.
            """
        )
    }
}
