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

/// Lifecycle of a scripted feature demo run, shown as the status dot on its
/// feature card. Each card owns one of these; a fresh run resets it.
enum FeatureDemoRunState: Equatable {
    case notRun
    case running
    case finished(atTimeDescription: String)

    var isRunning: Bool {
        self == .running
    }
}

/// Which feature demo a run belongs to. The comparison window uses this to
/// pick its lane headers and to restart the right script on Replay.
enum FeatureDemoKind: Equatable {
    case skills
    case preferences
    case routines
    case nicheSuggestions
}

/// The three presenter quick asks in the cockpit's Ask Clicky section. Each
/// is answered read-only from whatever demo state is currently loaded, then
/// spoken aloud by the real Clicky overlay (no comparison window). Asks
/// recall, match, and prompt-build over the live stores but never write to
/// them, so asking never changes the loaded demo state.
enum AskClickyQuickAction: String, CaseIterable, Identifiable, Equatable {
    case whatDidYouLearnAboutMe
    case helpMeCommitInXcodeAgain
    case whatShouldIDoNextInThisApp

    var id: String { rawValue }

    /// The ask exactly as the simulated user "speaks" it. Also the chip
    /// title in the cockpit and the user bubble text in the run.
    var promptText: String {
        switch self {
        case .whatDidYouLearnAboutMe: return "What did you learn about me?"
        case .helpMeCommitInXcodeAgain: return "Help me commit in Xcode again"
        case .whatShouldIDoNextInThisApp: return "What should I do next in this app?"
        }
    }
}

/// One conversation beat rendered in the comparison window. A demo run is a
/// paced sequence of these; the view renders each kind differently (user
/// bubble, Clicky bubble, system pill).
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

    /// Whether the comparison column should show the typing indicator before
    /// this beat lands (only Clicky's bubbles "think" first).
    var showsTypingIndicatorFirst: Bool {
        if case .clickyResponds = self { return true }
        return false
    }
}

/// Which side of the before/after comparison a beat plays in. The lane
/// switch itself is the "time gap": the second-session column header carries
/// the "Next day" label, so no divider beat is needed.
enum DemoComparisonLane: Equatable {
    /// Left column — the user asks for the first time, Clicky teaches from scratch.
    case firstSession
    /// Right column — the re-ask after Clicky has learned.
    case secondSession
}

/// A played beat with a stable identity for SwiftUI list rendering.
struct DemoStageBeat: Identifiable, Equatable {
    let id: Int
    let beat: DemoConversationBeat
}

/// One step of a demo script. Producing the beat runs the step's real side
/// effects (store writes, matcher runs, prompt builds, proof updates) inside
/// the closure, so each mutation fires at exactly its beat — never earlier,
/// never later. Beat content can therefore depend on side-effect results
/// (e.g. the matched-skill badge).
///
/// Returning nil renders nothing: the step only runs side effects (used by
/// the closing recap step, which publishes the recap strip text instead of
/// appending a conversation row).
struct DemoScriptStep {
    /// The comparison column this step's beat (and typing indicator) plays in.
    let lane: DemoComparisonLane
    let performSideEffectsAndProduceBeat: @MainActor () -> DemoConversationBeat?
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

    @Published private(set) var skillsDemoRunState: FeatureDemoRunState = .notRun

    /// Skills-card proof fields, filled progressively as run steps complete.
    /// nil renders as an em dash placeholder in the cockpit.
    @Published private(set) var skillsDemoSavedSkillNameProof: String?
    @Published private(set) var skillsDemoSkillMatchedProof: String?
    @Published private(set) var skillsDemoPromptIncludedProof: String?
    @Published private(set) var skillsDemoTurnsToSuccessProof: String?

    // MARK: Preferences demo run state

    @Published private(set) var preferencesDemoRunState: FeatureDemoRunState = .notRun

    /// Preferences-card proof fields, filled progressively as run steps
    /// complete. nil renders as an em dash placeholder in the cockpit.
    @Published private(set) var preferencesDemoSignalDetectedProof: String?
    @Published private(set) var preferencesDemoSavedPreferenceTitleProof: String?
    @Published private(set) var preferencesDemoPromptIncludedProof: String?
    @Published private(set) var preferencesDemoAnswerLengthProof: String?

    // MARK: Routines demo run state

    @Published private(set) var routinesDemoRunState: FeatureDemoRunState = .notRun

    /// Routines-card proof fields, filled progressively as run steps
    /// complete. nil renders as an em dash placeholder in the cockpit.
    @Published private(set) var routinesDemoEdgesSeededProof: String?
    @Published private(set) var routinesDemoChipShownProof: String?
    @Published private(set) var routinesDemoChipLabelProof: String?
    @Published private(set) var routinesDemoAnswerStyleProof: String?

    // MARK: Niche Suggestions demo run state

    @Published private(set) var nicheSuggestionsDemoRunState: FeatureDemoRunState = .notRun

    /// Niche-Suggestions-card proof fields, filled progressively as run
    /// steps complete. nil renders as an em dash placeholder in the cockpit.
    @Published private(set) var nicheSuggestionsDemoNichePickedProof: String?
    @Published private(set) var nicheSuggestionsDemoSimulatedFrontmostAppProof: String?
    @Published private(set) var nicheSuggestionsDemoSuggestionModeProof: String?
    @Published private(set) var nicheSuggestionsDemoSuggestionsShownProof: String?

    // MARK: Ask Clicky quick action run state

    /// One lifecycle shared by all three quick asks — asks play one at a
    /// time, so a single state is enough for re-press guarding.
    @Published private(set) var askClickyRunState: FeatureDemoRunState = .notRun

    /// Which quick ask currently owns `askClickyRunState`, used to ignore
    /// re-presses of the same chip while it is still speaking.
    private var activeAskClickyQuickAction: AskClickyQuickAction?

    // MARK: Comparison playback state

    /// Which feature demo's script currently owns the comparison window.
    /// Drives the window's lane headers and what Replay restarts.
    @Published private(set) var activeFeatureDemoKind: FeatureDemoKind?

    /// Beats played so far in the left "first time" column, appended one at
    /// a time with pacing.
    @Published private(set) var firstSessionLaneBeats: [DemoStageBeat] = []
    /// Beats played so far in the right "next day" column. Stays empty until
    /// the first session finishes, which is what makes the right column sit
    /// in its waiting state during the first half of the run.
    @Published private(set) var secondSessionLaneBeats: [DemoStageBeat] = []
    /// Which column is showing Clicky's typing indicator right now (set just
    /// before each Clicky bubble lands). nil = no typing indicator anywhere.
    @Published private(set) var clickyTypingLane: DemoComparisonLane?
    /// Closing summary strip spanning both columns, published by the final
    /// script step. nil until the run reaches its recap.
    @Published private(set) var comparisonRecapText: String?
    /// Which demo currently owns the comparison window, e.g.
    /// "Skills · Xcode Commit Flow". nil when no run has started.
    @Published private(set) var stageDemoTitle: String?

    // MARK: Proof Panel fields (shared by all demo cards)

    @Published private(set) var lastMemoryWrittenDescription: String = "—"
    @Published private(set) var lastMatchedMemoryDescription: String = "—"
    @Published private(set) var promptSectionsIncludedDescription: String = "—"
    @Published private(set) var beforeAfterMetricDescription: String = "—"

    /// One task drives whichever feature demo is currently playing — demos
    /// share the comparison window, so two can never play at once.
    private var featureDemoRunTask: Task<Void, Never>?

    /// Run state of whichever demo owns the comparison window right now.
    /// Used by the window's Replay chip.
    var activeFeatureDemoRunState: FeatureDemoRunState {
        switch activeFeatureDemoKind {
        case .skills: return skillsDemoRunState
        case .preferences: return preferencesDemoRunState
        case .routines: return routinesDemoRunState
        case .nicheSuggestions: return nicheSuggestionsDemoRunState
        case nil: return .notRun
        }
    }

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
        clearFeatureDemoRunPresentations()
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
        clearFeatureDemoRunPresentations()
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

    /// Plays the full "learn then reuse" Xcode commit arc as a before/after
    /// conversation in the comparison window:
    ///
    /// 1. Left column — the REAL SkillMatcher finds no commit skill, so
    ///    Clicky teaches from scratch over a 4-turn exchange, ending with a
    ///    REAL skill write to TeachingSkillStore (save pill, Brain tab
    ///    shows it).
    /// 2. Right column ("Next day") — the re-ask. The REAL matcher finds
    ///    the skill, the REAL TeachingPromptBuilder injects its prompt
    ///    section, and Clicky answers in a single turn with a matched badge.
    /// 3. A recap strip spanning both columns lands last.
    ///
    /// Only the conversation text is scripted (the demo must not depend on
    /// speech or network); the store write, matching, and prompt assembly
    /// are the production code paths. The demo commit skill is deleted up
    /// front so every run replays the identical arc, even right after
    /// loading the Developer profile (which seeds that same skill).
    /// Calling this again (the window's Replay chip) restarts the run.
    func runSkillsDemo() {
        // Re-pressing Run mid-run is ignored; starting a DIFFERENT demo is
        // allowed — the clear below cancels the other demo's task first.
        guard !skillsDemoRunState.isRunning else { return }

        clearFeatureDemoRunPresentations()
        skillsDemoRunState = .running

        featureDemoRunTask = Task { [weak self] in
            await self?.performSkillsDemoRun()
        }
    }

    /// Restarts whichever demo currently owns the comparison window. Wired
    /// to the window's Replay chip.
    func replayActiveFeatureDemo() {
        switch activeFeatureDemoKind {
        case .skills: runSkillsDemo()
        case .preferences: runPreferencesDemo()
        case .routines: runRoutinesDemo()
        case .nicheSuggestions: runNicheSuggestionsDemo()
        case nil: break
        }
    }

    private func performSkillsDemoRun() async {
        activeFeatureDemoKind = .skills
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
    /// in its column. Conversation text is scripted; the operations are real.
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
            DemoScriptStep(lane: .firstSession) {
                .userSays(text: SkillsDemoScript.firstAskTranscript)
            },
            DemoScriptStep(lane: .firstSession) { [self] in
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
            DemoScriptStep(lane: .firstSession) {
                .clickyResponds(text: SkillsDemoScript.firstGuidanceResponse, matchedSkillBadge: nil)
            },
            DemoScriptStep(lane: .firstSession) {
                .userSays(text: SkillsDemoScript.followUpQuestionTranscript)
            },
            DemoScriptStep(lane: .firstSession) {
                .clickyResponds(text: SkillsDemoScript.followUpGuidanceResponse, matchedSkillBadge: nil)
            },
            DemoScriptStep(lane: .firstSession) {
                .userSays(text: SkillsDemoScript.confirmationTranscript)
            },
            DemoScriptStep(lane: .firstSession) {
                .clickyResponds(text: SkillsDemoScript.confirmationAcknowledgement, matchedSkillBadge: nil)
            },
            DemoScriptStep(lane: .firstSession) { [self] in
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

            // Second session: same ask, after Clicky has learned. The lane
            // switch wakes up the right "Next day" column.
            DemoScriptStep(lane: .secondSession) {
                .userSays(text: SkillsDemoScript.reAskTranscript)
            },
            DemoScriptStep(lane: .secondSession) { [self] in
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
            DemoScriptStep(lane: .secondSession) {
                .clickyResponds(
                    text: SkillsDemoScript.reAskResponse,
                    // Badge reflects the real matcher result from the
                    // previous step, not a hardcoded claim.
                    matchedSkillBadge: runContext.savedSkillIsTopMatch
                        ? "Matched: Commit changes in Xcode"
                        : nil
                )
            },
            DemoScriptStep(lane: .secondSession) { [self] in
                skillsDemoTurnsToSuccessProof = "4 → 1 (simulated)"
                beforeAfterMetricDescription = "Turns to success: 4 → 1 (simulated demo metric)"
                // Side-effect-only step: publishes the recap strip spanning
                // both columns instead of appending a conversation row.
                comparisonRecapText = "First time: 4 turns → Next time: 1 turn (simulated demo metric)"
                return nil
            },
        ]
    }

    // MARK: - Preferences Demo Run

    /// Plays the "Short Answers + Shortcuts" arc as a before/after
    /// conversation in the comparison window:
    ///
    /// 1. Left column ("Before") — a screen-help question gets a verbose,
    ///    menu-path answer. The user then states the preference; the REAL
    ///    PreferenceSignalDetector recognizes it and a REAL preference
    ///    memory is written to AuxiliaryMemoryStore (save pill, Brain tab
    ///    and the Preferences count tile show it).
    /// 2. Right column ("After") — the exact same question. The REAL
    ///    TeachingPromptBuilder injects the saved preference into the
    ///    prompt's `user preferences:` section, and Clicky answers in one
    ///    short shortcut-first line with an applied badge.
    /// 3. A recap strip compares the two answer lengths.
    ///
    /// Only the conversation text is scripted (the demo must not depend on
    /// speech or network); the signal detection, store write, and prompt
    /// assembly are the production code paths. The demo preference (and the
    /// Developer profile's two overlapping style preferences) are deleted up
    /// front so the "before" state is honest on every run.
    /// Calling this again (the window's Replay chip) restarts the run.
    func runPreferencesDemo() {
        // Re-pressing Run mid-run is ignored; starting a DIFFERENT demo is
        // allowed — the clear below cancels the other demo's task first.
        guard !preferencesDemoRunState.isRunning else { return }

        clearFeatureDemoRunPresentations()
        preferencesDemoRunState = .running

        featureDemoRunTask = Task { [weak self] in
            await self?.performPreferencesDemoRun()
        }
    }

    private func performPreferencesDemoRun() async {
        activeFeatureDemoKind = .preferences
        stageDemoTitle = "Preferences · Short Answers + Shortcuts"

        // Deterministic restart: forget the demo preference if a previous
        // run wrote it, and the Developer profile's two style preferences —
        // they state the same preference, which would make the verbose
        // "before" answer dishonest right after loading that profile.
        let preferenceIdsToForget = [
            PreferencesDemoScript.shortAnswersPreferenceId,
            "demo-pref-short-answers",
            "demo-pref-keyboard-shortcuts",
        ]
        var deletedAnySeededPreference = false
        for preferenceId in preferenceIdsToForget where auxiliaryMemoryStore.memory(withID: preferenceId) != nil {
            try? auxiliaryMemoryStore.delete(id: preferenceId)
            deletedAnySeededPreference = true
        }
        if deletedAnySeededPreference {
            refreshCompanionManagerAfterStoreMutation()
            refreshDemoStateCounts()
        }

        await playDemoScript(makePreferencesDemoScript())
        guard !Task.isCancelled else { return }

        let finishedAtDescription = lastRunTimeFormatter.string(from: Date())
        preferencesDemoRunState = .finished(atTimeDescription: finishedAtDescription)
        lastRunStatusDescription = "Preferences demo · \(finishedAtDescription)"
    }

    /// The Preferences demo as a conversation script. Side effects (signal
    /// detection, the preference write, prompt build, proof updates) execute
    /// inside the beat producers, so each real operation fires exactly when
    /// its beat lands in its column.
    private func makePreferencesDemoScript() -> [DemoScriptStep] {
        // Shared mutable state between steps. A reference type so closures
        // created upfront all see values written by earlier steps (the
        // prompt-build step writes this; the final bubble reads it for its
        // applied badge).
        final class PreferencesDemoRunContext {
            var savedPreferenceWasInjectedIntoPrompt = false
        }
        let runContext = PreferencesDemoRunContext()

        return [
            // Before: a normal screen-help question, answered verbosely
            // because no style preference exists yet.
            DemoScriptStep(lane: .firstSession) {
                .userSays(text: PreferencesDemoScript.screenHelpQuestionTranscript)
            },
            DemoScriptStep(lane: .firstSession) {
                .clickyResponds(text: PreferencesDemoScript.verboseAnswerResponse, matchedSkillBadge: nil)
            },
            DemoScriptStep(lane: .firstSession) {
                .userSays(text: PreferencesDemoScript.statedPreferenceTranscript)
            },
            DemoScriptStep(lane: .firstSession) { [self] in
                // Real detector over the scripted statement: this is the same
                // deterministic gate the production memory pipeline uses to
                // decide a session contained a stated preference.
                let statementRegisteredAsPreferenceSignal =
                    PreferenceSignalDetector.containsAnyPreferenceSignal(
                        in: PreferencesDemoScript.statedPreferenceTranscript
                    )

                preferencesDemoSignalDetectedProof =
                    statementRegisteredAsPreferenceSignal ? "Yes" : "No (unexpected)"

                return .systemEvent(
                    iconSystemName: "waveform.and.magnifyingglass",
                    label: statementRegisteredAsPreferenceSignal
                        ? "Preference signal detected"
                        : "Unexpected: no preference signal detected",
                    detail: "PreferenceSignalDetector ran for real"
                )
            },
            DemoScriptStep(lane: .firstSession) { [self] in
                // Real store write — the preference is on disk from this
                // beat on.
                let freshlySavedPreference = PreferencesDemoScript.makeShortAnswersPreferenceMemory()
                do {
                    try auxiliaryMemoryStore.save(freshlySavedPreference)
                } catch {
                    print("⚠️ Preferences demo failed to save the preference: \(error)")
                }
                refreshCompanionManagerAfterStoreMutation()
                refreshDemoStateCounts()

                preferencesDemoSavedPreferenceTitleProof = freshlySavedPreference.title
                lastMemoryWrittenDescription = "Preference · \(freshlySavedPreference.title) · \(lastRunTimeFormatter.string(from: Date()))"

                return .systemEvent(
                    iconSystemName: "brain",
                    label: "Preference saved · \(freshlySavedPreference.title)",
                    detail: "Real write to the memory store — open the Brain tab to see it"
                )
            },
            DemoScriptStep(lane: .firstSession) {
                .clickyResponds(text: PreferencesDemoScript.preferenceAcknowledgement, matchedSkillBadge: nil)
            },

            // After: the exact same question, now answered through the
            // saved preference. The lane switch wakes up the right column.
            DemoScriptStep(lane: .secondSession) {
                .userSays(text: PreferencesDemoScript.screenHelpQuestionTranscript)
            },
            DemoScriptStep(lane: .secondSession) { [self] in
                // Real prompt assembly: collect active preferences with the
                // same filter the production voice pipeline applies
                // (CompanionManager.activePreferences is private), then
                // prove TeachingPromptBuilder injects the section.
                let activePreferencesForPrompt = Array(
                    auxiliaryMemoryStore.memories(for: .preference)
                        .filter { preferenceMemory in
                            guard preferenceMemory.status == .active else { return false }
                            if preferenceMemory.bundleIds.isEmpty { return true }
                            return preferenceMemory.bundleIds.contains(PreferencesDemoScript.xcodeBundleId)
                        }
                        .prefix(3)
                )

                let savedPreferenceIsActive = activePreferencesForPrompt.contains { preferenceMemory in
                    preferenceMemory.id == PreferencesDemoScript.shortAnswersPreferenceId
                }

                let voicePromptWithPreferences = TeachingPromptBuilder.buildVoiceResponsePrompt(
                    basePrompt: PreferencesDemoScript.demoBasePrompt,
                    matchedSkills: [],
                    activePreferences: activePreferencesForPrompt
                )
                let promptIncludedPreferencesSection =
                    voicePromptWithPreferences.contains("user preferences:")

                runContext.savedPreferenceWasInjectedIntoPrompt =
                    savedPreferenceIsActive && promptIncludedPreferencesSection

                preferencesDemoPromptIncludedProof =
                    runContext.savedPreferenceWasInjectedIntoPrompt ? "Yes" : "No"

                lastMatchedMemoryDescription = savedPreferenceIsActive
                    ? "Preference · \(PreferencesDemoScript.shortAnswersPreferenceTitle) (active)"
                    : "No match"
                promptSectionsIncludedDescription = promptIncludedPreferencesSection
                    ? "base + user preferences"
                    : "base only"

                return .systemEvent(
                    iconSystemName: "checkmark.seal",
                    label: runContext.savedPreferenceWasInjectedIntoPrompt
                        ? "Preference injected into the prompt"
                        : "Unexpected: the saved preference was not injected",
                    detail: "TeachingPromptBuilder ran for real"
                )
            },
            DemoScriptStep(lane: .secondSession) {
                .clickyResponds(
                    text: PreferencesDemoScript.shortAnswerResponse,
                    // Badge reflects the real prompt-build result from the
                    // previous step, not a hardcoded claim.
                    matchedSkillBadge: runContext.savedPreferenceWasInjectedIntoPrompt
                        ? "Preference applied: short + shortcuts"
                        : nil
                )
            },
            DemoScriptStep(lane: .secondSession) { [self] in
                // Word counts are computed from the script constants so the
                // recap can never drift from the copy actually shown above.
                let verboseAnswerWordCount = PreferencesDemoScript.wordCount(
                    of: PreferencesDemoScript.verboseAnswerResponse
                )
                let shortAnswerWordCount = PreferencesDemoScript.wordCount(
                    of: PreferencesDemoScript.shortAnswerResponse
                )

                preferencesDemoAnswerLengthProof =
                    "\(verboseAnswerWordCount) → \(shortAnswerWordCount) words (simulated)"
                beforeAfterMetricDescription =
                    "Answer length: \(verboseAnswerWordCount) → \(shortAnswerWordCount) words (simulated demo metric)"
                comparisonRecapText =
                    "Same question: \(verboseAnswerWordCount) words → \(shortAnswerWordCount) words (simulated demo metric)"
                return nil
            },
        ]
    }

    // MARK: - Routines Demo Run

    /// Plays the "Linear → Xcode" routine arc as a before/after conversation
    /// in the comparison window:
    ///
    /// 1. Left column ("Earlier this week") — repeated Linear → Xcode
    ///    switches are recorded as REAL backdated ActivityStore transitions,
    ///    day by day. After the first day, the REAL RoutineDetector proves
    ///    nothing qualifies yet, and the user's "what should I do next?"
    ///    gets a generic answer.
    /// 2. Right column ("Today") — one more real switch lands now, the REAL
    ///    RoutineDetector clears its recurrence bars and produces the chip
    ///    ("You often open Xcode after Linear"), the real companion panel
    ///    chips refresh, and the same ask is answered routine-aware with a
    ///    matched badge.
    /// 3. A recap strip contrasts the two answers.
    ///
    /// Only the conversation text is scripted (the demo must not depend on
    /// speech or network); the activity recording and recurrence detection
    /// are the production code paths. This demos the routine CHIP pipeline
    /// (activity edges → recurrence rules → chip) — it deliberately writes
    /// no routine Memory, which belongs to the session-distillation
    /// pipeline. The Linear → Xcode edge is removed up front so every run
    /// replays the identical arc, even right after loading the Developer
    /// profile (which seeds that same edge).
    /// Calling this again (the window's Replay chip) restarts the run.
    func runRoutinesDemo() {
        // Re-pressing Run mid-run is ignored; starting a DIFFERENT demo is
        // allowed — the clear below cancels the other demo's task first.
        guard !routinesDemoRunState.isRunning else { return }

        clearFeatureDemoRunPresentations()
        routinesDemoRunState = .running

        featureDemoRunTask = Task { [weak self] in
            await self?.performRoutinesDemoRun()
        }
    }

    private func performRoutinesDemoRun() async {
        activeFeatureDemoKind = .routines
        stageDemoTitle = "Routines · Linear → Xcode"

        // Deterministic restart: forget the Linear → Xcode edge (and any
        // suppression of it) if a previous run or the Developer profile
        // seeded it. Removal is targeted so other recorded activity — e.g.
        // another loaded profile's edge — stays intact. The refresh clears
        // any already-visible chip from the real companion panel, so the
        // chip appearing mid-run is the payoff.
        activityStore.removeTransitions(
            fromBundleId: RoutinesDemoScript.linearBundleId,
            toBundleId: RoutinesDemoScript.xcodeBundleId
        )
        refreshCompanionManagerAfterStoreMutation()

        await playDemoScript(makeRoutinesDemoScript())
        guard !Task.isCancelled else { return }

        let finishedAtDescription = lastRunTimeFormatter.string(from: Date())
        routinesDemoRunState = .finished(atTimeDescription: finishedAtDescription)
        lastRunStatusDescription = "Routines demo · \(finishedAtDescription)"
    }

    /// The Routines demo as a conversation script. Side effects (activity
    /// writes, detector runs, proof updates) execute inside the beat
    /// producers, so each real operation fires exactly when its beat lands
    /// in its column.
    private func makeRoutinesDemoScript() -> [DemoScriptStep] {
        // Shared mutable state between steps. A reference type so closures
        // created upfront all see values written by earlier steps (the
        // detector step writes this; the final bubble reads it for its
        // badge and the recap reads it for its metric).
        final class RoutinesDemoRunContext {
            var detectedRoutineChip: RoutineSuggestion?
        }
        let runContext = RoutinesDemoRunContext()

        return [
            // Earlier this week: Clicky quietly watches the user repeat the
            // same app switch. Each day pill performs real backdated writes.
            DemoScriptStep(lane: .firstSession) { [self] in
                recordDemoAppTransitions(
                    fromBundleId: RoutinesDemoScript.linearBundleId,
                    toBundleId: RoutinesDemoScript.xcodeBundleId,
                    transitionCount: RoutinesDemoScript.transitionsSeededPerDay,
                    daysAgoFromToday: 3
                )
                routinesDemoEdgesSeededProof = RoutinesDemoScript.edgesSeededProofDescription(afterSeededDayCount: 1)

                return .systemEvent(
                    iconSystemName: "arrow.triangle.2.circlepath",
                    label: RoutinesDemoScript.daySeedPillLabel(dayDescription: "3 days ago"),
                    detail: "Real transitions recorded in the activity store"
                )
            },
            DemoScriptStep(lane: .firstSession) { [self] in
                // Real detector over the live store: proves one day of
                // recurrence is below the chip's bar (minimum 2 distinct
                // days), so Clicky stays quiet instead of guessing.
                let chipAfterOneDay = detectLinearToXcodeRoutineChip()
                return .systemEvent(
                    iconSystemName: "magnifyingglass",
                    label: chipAfterOneDay == nil
                        ? "No routine chip yet — only 1 distinct day"
                        : "Unexpected: a routine chip already qualified",
                    detail: "RoutineDetector ran over the real activity store"
                )
            },
            DemoScriptStep(lane: .firstSession) {
                .userSays(text: RoutinesDemoScript.askTranscript)
            },
            DemoScriptStep(lane: .firstSession) {
                .clickyResponds(text: RoutinesDemoScript.genericAnswerResponse, matchedSkillBadge: nil)
            },
            DemoScriptStep(lane: .firstSession) { [self] in
                recordDemoAppTransitions(
                    fromBundleId: RoutinesDemoScript.linearBundleId,
                    toBundleId: RoutinesDemoScript.xcodeBundleId,
                    transitionCount: RoutinesDemoScript.transitionsSeededPerDay,
                    daysAgoFromToday: 2
                )
                routinesDemoEdgesSeededProof = RoutinesDemoScript.edgesSeededProofDescription(afterSeededDayCount: 2)

                return .systemEvent(
                    iconSystemName: "arrow.triangle.2.circlepath",
                    label: RoutinesDemoScript.daySeedPillLabel(dayDescription: "2 days ago"),
                    detail: nil
                )
            },
            DemoScriptStep(lane: .firstSession) { [self] in
                recordDemoAppTransitions(
                    fromBundleId: RoutinesDemoScript.linearBundleId,
                    toBundleId: RoutinesDemoScript.xcodeBundleId,
                    transitionCount: RoutinesDemoScript.transitionsSeededPerDay,
                    daysAgoFromToday: 1
                )
                routinesDemoEdgesSeededProof = RoutinesDemoScript.edgesSeededProofDescription(
                    afterSeededDayCount: RoutinesDemoScript.seededDistinctDayCount
                )
                lastMemoryWrittenDescription = "Activity edges · Linear → Xcode ×\(RoutinesDemoScript.transitionsSeededPerDay * RoutinesDemoScript.seededDistinctDayCount) over \(RoutinesDemoScript.seededDistinctDayCount) days · \(lastRunTimeFormatter.string(from: Date()))"

                return .systemEvent(
                    iconSystemName: "arrow.triangle.2.circlepath",
                    label: RoutinesDemoScript.daySeedPillLabel(dayDescription: "Yesterday"),
                    detail: nil
                )
            },

            // Today: one more real switch tips the pattern over the
            // recurrence bar. The lane switch wakes up the right column.
            DemoScriptStep(lane: .secondSession) { [self] in
                // The live trigger: the simulated user opens Xcode after
                // Linear right now — one real transition recorded at "now".
                activityStore.recordTransition(
                    from: RoutinesDemoScript.linearBundleId,
                    to: RoutinesDemoScript.xcodeBundleId
                )
                simulatedAppContextDisplayName = RoutinesDemoScript.xcodeDisplayName

                return .systemEvent(
                    iconSystemName: "macwindow",
                    label: "Today · user opens Xcode after Linear",
                    detail: "One more real transition, recorded just now"
                )
            },
            DemoScriptStep(lane: .secondSession) { [self] in
                // Real detector + real panel refresh: proves the recurrence
                // rules now produce the chip, and pushes it into the actual
                // companion panel UI.
                runContext.detectedRoutineChip = detectLinearToXcodeRoutineChip()
                refreshCompanionManagerAfterStoreMutation()

                let routineChipWasDetected = runContext.detectedRoutineChip != nil
                routinesDemoChipShownProof = routineChipWasDetected ? "Yes" : "No (unexpected)"
                routinesDemoChipLabelProof = runContext.detectedRoutineChip?.label

                lastMatchedMemoryDescription = runContext.detectedRoutineChip.map { detectedRoutineChip in
                    "Routine chip · \(detectedRoutineChip.label)"
                } ?? "No match"

                return .systemEvent(
                    iconSystemName: "checkmark.seal",
                    label: runContext.detectedRoutineChip.map { detectedRoutineChip in
                        "Routine chip shown · \u{201C}\(detectedRoutineChip.label)\u{201D}"
                    } ?? "Unexpected: no routine chip detected",
                    detail: "RoutineDetector ran for real — the chip is live in the companion panel"
                )
            },
            DemoScriptStep(lane: .secondSession) {
                .userSays(text: RoutinesDemoScript.askTranscript)
            },
            DemoScriptStep(lane: .secondSession) {
                .clickyResponds(
                    text: RoutinesDemoScript.routineAwareAnswerResponse,
                    // Badge reflects the real detector result from the
                    // previous step, not a hardcoded claim.
                    matchedSkillBadge: runContext.detectedRoutineChip != nil
                        ? "Routine: Linear → Xcode"
                        : nil
                )
            },
            DemoScriptStep(lane: .secondSession) { [self] in
                // The chip count metric is real (the detector either produced
                // the chip or it didn't); the answer-style contrast is
                // scripted conversation copy, so it stays labeled simulated.
                let routineChipWasDetected = runContext.detectedRoutineChip != nil
                routinesDemoAnswerStyleProof = "generic → routine-aware (simulated)"
                beforeAfterMetricDescription = routineChipWasDetected
                    ? "Routine chips: 0 → 1 (real recurrence rules)"
                    : "Routine chips: 0 → 0 (unexpected)"
                // Side-effect-only step: publishes the recap strip spanning
                // both columns instead of appending a conversation row.
                comparisonRecapText = routineChipWasDetected
                    ? "Same question: generic → routine-aware · chip from real recurrence rules"
                    : "Same question, but no routine chip qualified (unexpected)"
                return nil
            },
        ]
    }

    /// Runs the REAL RoutineDetector over the live activity store and returns
    /// the Linear → Xcode chip if it qualified. Other detected chips (e.g.
    /// from another loaded profile's edges) are ignored so the demo's proof
    /// fields always describe this demo's pattern.
    private func detectLinearToXcodeRoutineChip() -> RoutineSuggestion? {
        let detectedSuggestions = RoutineDetector.suggestions(
            from: activityStore.allEdges(),
            suppressedEdgeIds: activityStore.suppressedEdgeIdentifiers()
        )
        return detectedSuggestions.first { detectedSuggestion in
            detectedSuggestion.fromBundleId == RoutinesDemoScript.linearBundleId
                && detectedSuggestion.toBundleId == RoutinesDemoScript.xcodeBundleId
        }
    }

    // MARK: - Niche Suggestions Demo Run

    /// Plays the "Developer + Xcode" niche-suggestions arc as a before/after
    /// conversation in the comparison window:
    ///
    /// 1. Left column ("No niche picked") — the niche override is REALLY
    ///    cleared, and a fresh user in Xcode asks what Clicky can even help
    ///    with. Without a niche, Clicky can only answer generically.
    /// 2. Right column ("Developer + Xcode") — the Developer niche is REALLY
    ///    saved (the real companion panel picker updates live), the frontmost
    ///    app is simulated as Xcode, and the REAL
    ///    `NicheDiscoveryManager.suggestionSnapshot` returns the app-aware
    ///    suggestions from the real bundled mapping. Clicky's bubble is built
    ///    from that snapshot, the user asks the first real suggestion, and
    ///    gets an informed answer.
    /// 3. A recap strip contrasts the two columns.
    ///
    /// Only the conversation text is scripted (the demo must not depend on
    /// speech or network); the niche override writes and the suggestion
    /// snapshot are the production code paths. The snapshot is deterministic
    /// here: with an explicit override and Xcode frontmost it reads only the
    /// static bundle-niche map and app suggestion mapping — never the
    /// presenter's real app usage. The override is cleared by the opening
    /// beat so every run replays the identical arc, even right after loading
    /// the Developer profile (which sets that same override).
    /// Calling this again (the window's Replay chip) restarts the run.
    func runNicheSuggestionsDemo() {
        // Re-pressing Run mid-run is ignored; starting a DIFFERENT demo is
        // allowed — the clear below cancels the other demo's task first.
        guard !nicheSuggestionsDemoRunState.isRunning else { return }

        clearFeatureDemoRunPresentations()
        nicheSuggestionsDemoRunState = .running

        featureDemoRunTask = Task { [weak self] in
            await self?.performNicheSuggestionsDemoRun()
        }
    }

    private func performNicheSuggestionsDemoRun() async {
        activeFeatureDemoKind = .nicheSuggestions
        stageDemoTitle = "Niche Suggestions · Developer + Xcode"

        await playDemoScript(makeNicheSuggestionsDemoScript())
        guard !Task.isCancelled else { return }

        let finishedAtDescription = lastRunTimeFormatter.string(from: Date())
        nicheSuggestionsDemoRunState = .finished(atTimeDescription: finishedAtDescription)
        lastRunStatusDescription = "Niche suggestions demo · \(finishedAtDescription)"
    }

    /// The Niche Suggestions demo as a conversation script. Side effects
    /// (the real niche override writes, the real suggestion snapshot, proof
    /// updates) execute inside the beat producers, so each real operation
    /// fires exactly when its beat lands in its column.
    private func makeNicheSuggestionsDemoScript() -> [DemoScriptStep] {
        // Shared mutable state between steps. A reference type so closures
        // created upfront all see values written by earlier steps (the
        // snapshot step writes this; the suggestions bubble, the user's
        // pick, and the recap all read it).
        final class NicheSuggestionsDemoRunContext {
            var appAwareSnapshot: NicheSuggestionSnapshot?
        }
        let runContext = NicheSuggestionsDemoRunContext()

        return [
            // No niche picked: the override is really cleared, so Clicky
            // starts cold — even right after loading the Developer profile
            // (which sets that same override).
            DemoScriptStep(lane: .firstSession) { [self] in
                companionManager?.clearUserNicheOverride()
                nicheSuggestionsDemoNichePickedProof = "None yet"

                return .systemEvent(
                    iconSystemName: "person.crop.circle.badge.questionmark",
                    label: "Fresh user · no niche picked",
                    detail: "Real niche override cleared — the companion panel picker updates live"
                )
            },
            DemoScriptStep(lane: .firstSession) {
                .userSays(text: NicheSuggestionsDemoScript.coldOpenAskTranscript)
            },
            DemoScriptStep(lane: .firstSession) {
                .clickyResponds(
                    text: NicheSuggestionsDemoScript.genericCapabilitiesResponse,
                    matchedSkillBadge: nil
                )
            },

            // Developer + Xcode: the niche override is really saved, the
            // frontmost app is simulated as Xcode, and the real suggestion
            // snapshot produces the app-aware asks. The lane switch wakes
            // up the right column.
            DemoScriptStep(lane: .secondSession) { [self] in
                companionManager?.setUserNiche(.developer)
                nicheSuggestionsDemoNichePickedProof = "Developer"

                return .systemEvent(
                    iconSystemName: "person.crop.circle.badge.checkmark",
                    label: "Niche picked · Developer",
                    detail: "Real niche override saved — the companion panel picker updates live"
                )
            },
            DemoScriptStep(lane: .secondSession) { [self] in
                simulatedAppContextDisplayName = NicheSuggestionsDemoScript.xcodeDisplayName
                nicheSuggestionsDemoSimulatedFrontmostAppProof = NicheSuggestionsDemoScript.xcodeDisplayName

                return .systemEvent(
                    iconSystemName: "macwindow",
                    label: "User is in Xcode",
                    detail: "Simulated frontmost app fed to the suggestion engine"
                )
            },
            DemoScriptStep(lane: .secondSession) { [self] in
                // Real suggestion engine over the simulated app context:
                // with an explicit Developer override and Xcode frontmost
                // this reads only static bundled data, so the result is
                // identical on every machine.
                let appAwareSnapshot = companionManager?.nicheSuggestionSnapshot(
                    forSimulatedFrontmostBundleId: NicheSuggestionsDemoScript.xcodeBundleId
                )
                runContext.appAwareSnapshot = appAwareSnapshot

                let shownSuggestionCount = appAwareSnapshot?.suggestions.count ?? 0
                let snapshotIsAppAware = shownSuggestionCount > 0

                nicheSuggestionsDemoSuggestionModeProof = appAwareSnapshot.map { snapshot in
                    NicheSuggestionsDemoScript.suggestionModeProofDescription(for: snapshot.mode)
                }
                nicheSuggestionsDemoSuggestionsShownProof = snapshotIsAppAware
                    ? "\(shownSuggestionCount) (real mapping)"
                    : "0 (unexpected)"

                lastMatchedMemoryDescription = snapshotIsAppAware
                    ? "Niche mapping · Xcode · \(shownSuggestionCount) app-aware suggestions"
                    : "No match"

                return .systemEvent(
                    iconSystemName: "lightbulb",
                    label: snapshotIsAppAware
                        ? "\(shownSuggestionCount) app-aware suggestions found for Xcode"
                        : "Unexpected: no app-aware suggestions found",
                    detail: "NicheDiscoveryManager.suggestionSnapshot ran for real"
                )
            },
            DemoScriptStep(lane: .secondSession) {
                // The bubble is built from the real snapshot, so the prompts
                // shown can never drift from what the suggestion engine
                // actually returned. Badge reflects the real snapshot result
                // from the previous step, not a hardcoded claim.
                .clickyResponds(
                    text: NicheSuggestionsDemoScript.suggestionsBubbleText(
                        from: runContext.appAwareSnapshot
                    ),
                    matchedSkillBadge: runContext.appAwareSnapshot?.suggestions.isEmpty == false
                        ? "App-aware: Xcode"
                        : nil
                )
            },
            DemoScriptStep(lane: .secondSession) {
                // The user picks the first suggestion — the ask text is the
                // prompt the real snapshot actually returned.
                .userSays(
                    text: runContext.appAwareSnapshot?.suggestions.first?.prompt
                        ?? NicheSuggestionsDemoScript.fallbackPickedSuggestionPrompt
                )
            },
            DemoScriptStep(lane: .secondSession) {
                .clickyResponds(
                    text: NicheSuggestionsDemoScript.pickedSuggestionAnswerResponse,
                    matchedSkillBadge: nil
                )
            },
            DemoScriptStep(lane: .secondSession) { [self] in
                let shownSuggestionCount = runContext.appAwareSnapshot?.suggestions.count ?? 0
                let snapshotIsAppAware = shownSuggestionCount > 0

                beforeAfterMetricDescription = snapshotIsAppAware
                    ? "Suggested asks: 0 → \(shownSuggestionCount) (real app-aware mapping)"
                    : "Suggested asks: 0 → 0 (unexpected)"
                // Side-effect-only step: publishes the recap strip spanning
                // both columns instead of appending a conversation row.
                comparisonRecapText = snapshotIsAppAware
                    ? "Blank page → \(shownSuggestionCount) app-aware asks · suggestions from the real niche mapping"
                    : "No app-aware suggestions qualified (unexpected)"
                return nil
            },
        ]
    }

    // MARK: - Ask Clicky Quick Action Runs

    /// Answers one Ask Clicky quick ask from the current demo state, then
    /// has the real Clicky overlay speak it aloud via ElevenLabs TTS. The
    /// memory reads / matchers are real and read-only; only the spoken copy
    /// is scripted. Unlike the feature demos, asks never write to the
    /// stores and never open the comparison window.
    func runAskClickyQuickAction(_ quickAction: AskClickyQuickAction) {
        // Re-pressing the SAME ask mid-run is ignored; starting a different
        // ask (or a feature demo) is allowed — the clear below cancels the
        // in-flight run's task first.
        let thisQuickActionIsAlreadyRunning = askClickyRunState.isRunning
            && activeAskClickyQuickAction == quickAction
        guard !thisQuickActionIsAlreadyRunning else { return }

        clearFeatureDemoRunPresentations()
        askClickyRunState = .running
        activeAskClickyQuickAction = quickAction

        featureDemoRunTask = Task { [weak self] in
            await self?.performAskClickyQuickActionRun(quickAction)
        }
    }

    private func performAskClickyQuickActionRun(_ quickAction: AskClickyQuickAction) async {
        let computedAskResult = computeAskClickyResult(for: quickAction)

        lastMatchedMemoryDescription = computedAskResult.lastMatchedMemoryDescription
        promptSectionsIncludedDescription = computedAskResult.promptSectionsIncludedDescription
        beforeAfterMetricDescription = computedAskResult.beforeAfterMetricDescription

        await companionManager?.speakSimulationDemoAskResponse(
            spokenText: computedAskResult.spokenText,
            matchedSkillNames: computedAskResult.matchedSkillNames
        )
        guard !Task.isCancelled else { return }

        let finishedAtDescription = lastRunTimeFormatter.string(from: Date())
        askClickyRunState = .finished(atTimeDescription: finishedAtDescription)
        lastRunStatusDescription = "Ask Clicky · \(finishedAtDescription)"
        activeAskClickyQuickAction = nil
    }

    /// Read-only answer assembly for one Ask Clicky quick ask. Each branch
    /// runs the same production matchers the voice pipeline uses, then
    /// builds speakable copy from the real results.
    private func computeAskClickyResult(for quickAction: AskClickyQuickAction) -> AskClickyComputedResult {
        switch quickAction {
        case .whatDidYouLearnAboutMe:
            return computeWhatDidYouLearnAskResult()
        case .helpMeCommitInXcodeAgain:
            return computeHelpMeCommitInXcodeAgainAskResult()
        case .whatShouldIDoNextInThisApp:
            return computeWhatShouldIDoNextInThisAppAskResult()
        }
    }

    private func computeWhatDidYouLearnAskResult() -> AskClickyComputedResult {
        let recalledActiveSkills = teachingSkillStore.skills
            .filter { skill in skill.status == .active }
        let recalledActivePreferences = auxiliaryMemoryStore
            .memories(for: .preference)
            .filter { preferenceMemory in preferenceMemory.status == .active }
        let recalledActiveRoutines = auxiliaryMemoryStore
            .memories(for: .routine)
            .filter { routineMemory in routineMemory.status == .active }

        let recalledMemoryTotal = recalledActiveSkills.count
            + recalledActivePreferences.count
            + recalledActiveRoutines.count

        let spokenText = AskClickyScript.whatDidYouLearnSpokenText(
            recalledActiveSkills: recalledActiveSkills,
            recalledActivePreferences: recalledActivePreferences,
            recalledActiveRoutines: recalledActiveRoutines
        )

        return AskClickyComputedResult(
            spokenText: spokenText,
            matchedSkillNames: [],
            lastMatchedMemoryDescription: recalledMemoryTotal > 0
                ? "Recall · \(recalledActiveSkills.count) skills + \(recalledActivePreferences.count) preferences + \(recalledActiveRoutines.count) routines"
                : "Recall · nothing learned yet",
            promptSectionsIncludedDescription: "—",
            beforeAfterMetricDescription: recalledMemoryTotal > 0
                ? "Recalled \(recalledMemoryTotal) real memories (read-only)"
                : "Recalled 0 memories (baseline)"
        )
    }

    private func computeHelpMeCommitInXcodeAgainAskResult() -> AskClickyComputedResult {
        let matchesForAsk = SkillMatcher.matchSkills(
            from: teachingSkillStore.skills,
            bundleId: AskClickyScript.xcodeBundleId,
            transcript: AskClickyQuickAction.helpMeCommitInXcodeAgain.promptText
        )
        let topMatchedSkill = matchesForAsk.first?.skill

        let voicePromptForAsk = TeachingPromptBuilder.buildVoiceResponsePrompt(
            basePrompt: AskClickyScript.demoBasePrompt,
            matchedSkills: matchesForAsk.map(\.skill)
        )
        let promptIncludedTeachingSkillsSection =
            voicePromptForAsk.contains("teaching skills:")

        let spokenText = AskClickyScript.commitAnswerText(topMatchedSkill: topMatchedSkill)

        return AskClickyComputedResult(
            spokenText: spokenText,
            matchedSkillNames: topMatchedSkill.map { [$0.name] } ?? [],
            lastMatchedMemoryDescription: topMatchedSkill.map { topMatchedSkill in
                "Skill · \(topMatchedSkill.name) (top match)"
            } ?? "No match",
            promptSectionsIncludedDescription: promptIncludedTeachingSkillsSection
                ? "base + teaching skills"
                : "base only",
            beforeAfterMetricDescription: topMatchedSkill != nil
                ? "Answered from matched skill (read-only)"
                : "No commit skill saved yet"
        )
    }

    private func computeWhatShouldIDoNextInThisAppAskResult() -> AskClickyComputedResult {
        let simulatedAppContext = loadedDemoProfile?.simulatedAppContext
        let contextBundleId = simulatedAppContext?.bundleId

        let topMatchedRoutineMemory = AuxiliaryMemoryMatcher.matchRoutines(
            from: auxiliaryMemoryStore.memories,
            bundleId: contextBundleId,
            transcript: AskClickyQuickAction.whatShouldIDoNextInThisApp.promptText,
            limit: 2
        ).first

        let detectedRoutineChipForContextApp = RoutineDetector.suggestions(
            from: activityStore.allEdges(),
            suppressedEdgeIds: activityStore.suppressedEdgeIdentifiers()
        ).first { detectedSuggestion in
            detectedSuggestion.toBundleId == contextBundleId
        }

        let voicePromptForAsk = TeachingPromptBuilder.buildVoiceResponsePrompt(
            basePrompt: AskClickyScript.demoBasePrompt,
            matchedSkills: [],
            matchedRoutines: [topMatchedRoutineMemory].compactMap { $0 }
        )
        let promptIncludedRoutinesSection =
            voicePromptForAsk.contains("recurring routines:")

        let spokenText = AskClickyScript.whatNextAnswerText(
            simulatedAppContext: simulatedAppContext,
            topMatchedRoutineMemory: topMatchedRoutineMemory,
            detectedRoutineChipForContextApp: detectedRoutineChipForContextApp
        )

        let lastMatchedMemoryDescription: String
        if let topMatchedRoutineMemory {
            lastMatchedMemoryDescription = "Routine · \(topMatchedRoutineMemory.title) (matched)"
        } else if let detectedRoutineChipForContextApp {
            lastMatchedMemoryDescription = "Routine chip · \(detectedRoutineChipForContextApp.label)"
        } else {
            lastMatchedMemoryDescription = "No match"
        }

        let beforeAfterMetricDescription: String
        if topMatchedRoutineMemory != nil {
            beforeAfterMetricDescription = "Answer from routine memory (read-only)"
        } else if detectedRoutineChipForContextApp != nil {
            beforeAfterMetricDescription = "Answer from routine chip (read-only)"
        } else if let simulatedAppContext {
            beforeAfterMetricDescription = "No routine signal for \(simulatedAppContext.displayName)"
        } else {
            beforeAfterMetricDescription = "No app context loaded"
        }

        return AskClickyComputedResult(
            spokenText: spokenText,
            matchedSkillNames: [],
            lastMatchedMemoryDescription: lastMatchedMemoryDescription,
            promptSectionsIncludedDescription: promptIncludedRoutinesSection
                ? "base + recurring routines"
                : "base only",
            beforeAfterMetricDescription: beforeAfterMetricDescription
        )
    }

    // MARK: - Demo Script Player

    /// Plays a demo script beat by beat: runs the step's real side effects,
    /// shows the typing indicator (in the step's lane) before Clicky bubbles,
    /// appends the beat to that lane's column, and pauses so the presenter
    /// can narrate. Cancellation (reset / profile load / re-run) stops
    /// playback between beats.
    private func playDemoScript(_ demoScriptSteps: [DemoScriptStep]) async {
        for demoScriptStep in demoScriptSteps {
            guard !Task.isCancelled else { return }

            guard let beat = demoScriptStep.performSideEffectsAndProduceBeat() else {
                // Side-effect-only step (e.g. the recap): nothing to render,
                // no pacing pause needed.
                continue
            }

            if beat.showsTypingIndicatorFirst {
                clickyTypingLane = demoScriptStep.lane
                await pause(nanoseconds: DemoScriptPacing.typingIndicatorNanoseconds)
                clickyTypingLane = nil
                guard !Task.isCancelled else { return }
            }

            appendBeat(beat, to: demoScriptStep.lane)

            await pause(nanoseconds: DemoScriptPacing.pacingAfterBeatNanoseconds)
        }
    }

    private func appendBeat(_ beat: DemoConversationBeat, to comparisonLane: DemoComparisonLane) {
        // IDs continue across both lanes so every beat in the run keeps a
        // unique, stable identity for SwiftUI.
        let nextBeatId = firstSessionLaneBeats.count + secondSessionLaneBeats.count
        let stageBeat = DemoStageBeat(id: nextBeatId, beat: beat)

        switch comparisonLane {
        case .firstSession:
            firstSessionLaneBeats.append(stageBeat)
        case .secondSession:
            secondSessionLaneBeats.append(stageBeat)
        }
    }

    private func pause(nanoseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    /// Cancels any in-flight run and clears both cards' run state/proofs
    /// plus the shared comparison playback. Cleared together because the
    /// demos share one window: starting demo B while demo A plays cancels A.
    private func clearFeatureDemoRunPresentations() {
        featureDemoRunTask?.cancel()
        featureDemoRunTask = nil

        skillsDemoRunState = .notRun
        skillsDemoSavedSkillNameProof = nil
        skillsDemoSkillMatchedProof = nil
        skillsDemoPromptIncludedProof = nil
        skillsDemoTurnsToSuccessProof = nil

        preferencesDemoRunState = .notRun
        preferencesDemoSignalDetectedProof = nil
        preferencesDemoSavedPreferenceTitleProof = nil
        preferencesDemoPromptIncludedProof = nil
        preferencesDemoAnswerLengthProof = nil

        routinesDemoRunState = .notRun
        routinesDemoEdgesSeededProof = nil
        routinesDemoChipShownProof = nil
        routinesDemoChipLabelProof = nil
        routinesDemoAnswerStyleProof = nil

        nicheSuggestionsDemoRunState = .notRun
        nicheSuggestionsDemoNichePickedProof = nil
        nicheSuggestionsDemoSimulatedFrontmostAppProof = nil
        nicheSuggestionsDemoSuggestionModeProof = nil
        nicheSuggestionsDemoSuggestionsShownProof = nil

        askClickyRunState = .notRun
        activeAskClickyQuickAction = nil

        activeFeatureDemoKind = nil
        firstSessionLaneBeats = []
        secondSessionLaneBeats = []
        clickyTypingLane = nil
        comparisonRecapText = nil
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

    /// Records `transitionCount` real transitions for one app pair on the
    /// calendar day `daysAgoFromToday` days before today. Timestamps are
    /// anchored at noon (the same anchoring `seedAppTransitions` uses) so
    /// they always fall inside ActivityStore's 30-day rolling window and
    /// never straddle a midnight boundary.
    private func recordDemoAppTransitions(
        fromBundleId: String,
        toBundleId: String,
        transitionCount: Int,
        daysAgoFromToday: Int
    ) {
        let calendar = Calendar.current
        let todayAtNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        guard let transitionDay = calendar.date(
            byAdding: .day,
            value: -daysAgoFromToday,
            to: todayAtNoon
        ) else { return }

        for _ in 0..<transitionCount {
            activityStore.recordTransition(
                from: fromBundleId,
                to: toBundleId,
                at: transitionDay
            )
        }
    }

    /// Pushes the mutated store contents into CompanionManager's published
    /// state: teaching skills, the unified memories list, and routine chips.
    private func refreshCompanionManagerAfterStoreMutation() {
        companionManager?.refreshTeachingSkills()
        companionManager?.refreshRoutineSuggestions()
    }
}

/// Shared playback pacing for every demo script, tuned so a presenter can
/// narrate between beats.
private enum DemoScriptPacing {
    /// How long Clicky's typing indicator shows before each of its bubbles.
    static let typingIndicatorNanoseconds: UInt64 = 900_000_000
    /// Pause after each beat lands, so the presenter can narrate.
    static let pacingAfterBeatNanoseconds: UInt64 = 1_100_000_000
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

/// The deterministic script behind the Preferences demo run. The stated
/// preference deliberately contains two detector phrases ("from now on",
/// "keep answers short") so the REAL PreferenceSignalDetector fires on it;
/// the rest of the conversation text is fixed so the demo never depends on
/// speech recognition or network.
private enum PreferencesDemoScript {
    static let shortAnswersPreferenceId = "demo-preference-short-shortcuts"
    static let shortAnswersPreferenceTitle = "Short answers, shortcuts first"
    static let xcodeBundleId = "com.apple.dt.Xcode"

    /// The same question is asked in both columns — only the saved
    /// preference differs between them.
    static let screenHelpQuestionTranscript = "How do I add a new file to my Xcode project?"

    // Before: no style preference exists, so the answer is long and
    // menu-path-first.
    static let verboseAnswerResponse = "There are a couple of ways to do this. In the menu bar, go to File, then New, then choose File from Template. A sheet appears where you pick a template, for example Swift File, then click Next, choose where to save it in the project navigator, make sure the right target is checked under Targets, and finally click Create."

    static let statedPreferenceTranscript = "From now on, keep answers short and lead with the keyboard shortcut."
    static let preferenceAcknowledgement = "Got it — short answers, shortcuts first. Saved."

    // After: the same question through the saved preference.
    static let shortAnswerResponse = "⌘N, pick your template, hit ⏎. Done."

    /// Short stand-in for the production voice system prompt. The proof is
    /// about whether TeachingPromptBuilder appends the user-preferences
    /// section, which works identically regardless of the base prompt text.
    static let demoBasePrompt = "you are clicky, a voice screen tutor."

    /// Recap word counts are computed from the script constants at run time
    /// so they can never drift from the copy actually shown in the bubbles.
    static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    static func makeShortAnswersPreferenceMemory() -> Memory {
        Memory(
            id: shortAnswersPreferenceId,
            category: .preference,
            title: shortAnswersPreferenceTitle,
            summary: "Keep responses brief and lead with the keyboard shortcut",
            body: """
            Answer in one or two short sentences. When a task has a keyboard
            shortcut, give the shortcut first; mention the menu path only if
            the user asks for it.
            """,
            usageCount: 1,
            lastUsed: Date()
        )
    }
}

/// The deterministic script behind the Routines demo run. The seeded counts
/// are chosen to clear RoutineDetector's bars (minimum 2 distinct days,
/// strength >= 0.4) by the time the right column's live switch lands; the
/// conversation text is fixed so the demo never depends on speech
/// recognition or network.
private enum RoutinesDemoScript {
    static let linearBundleId = "com.linear"
    static let xcodeBundleId = "com.apple.dt.Xcode"
    static let linearDisplayName = "Linear"
    static let xcodeDisplayName = "Xcode"

    /// 3 transitions × 3 backdated days seeded in the left column, plus the
    /// right column's live switch "today" = 10 transitions over 4 distinct
    /// days, comfortably past the detector's recurrence bars.
    static let transitionsSeededPerDay = 3
    static let seededDistinctDayCount = 3

    /// The same question is asked in both columns — only the detected
    /// routine differs between them.
    static let askTranscript = "What should I do next in this app?"

    // Before: no routine has qualified, so Clicky has to ask for context.
    static let genericAnswerResponse = "That depends on what you're working on — tell me the task and I can point you to the right place in Xcode."

    // After: the detected Linear → Xcode routine informs the answer.
    static let routineAwareAnswerResponse = "You usually land in Xcode right after picking a Linear ticket. Pull up that ticket's branch and start there — want me to walk you through your usual first steps?"

    static func daySeedPillLabel(dayDescription: String) -> String {
        "\(dayDescription) · \(linearDisplayName) → \(xcodeDisplayName) ×\(transitionsSeededPerDay)"
    }

    /// Cumulative "Activity edges seeded" proof text, computed from the
    /// script constants so it can never drift from the writes actually
    /// performed by the day beats.
    static func edgesSeededProofDescription(afterSeededDayCount seededDayCount: Int) -> String {
        let transitionTotal = transitionsSeededPerDay * seededDayCount
        let dayWord = seededDayCount == 1 ? "day" : "days"
        return "\(transitionTotal) over \(seededDayCount) \(dayWord)"
    }
}

/// The deterministic script behind the Niche Suggestions demo run. With an
/// explicit Developer override and Xcode as the simulated frontmost app, the
/// real suggestion snapshot reads only static bundled data
/// (bundle-niche-map.json + NicheAppSuggestionMapping), so the suggestions
/// shown are identical on every machine; the conversation text is fixed so
/// the demo never depends on speech recognition or network.
private enum NicheSuggestionsDemoScript {
    static let xcodeBundleId = "com.apple.dt.Xcode"
    static let xcodeDisplayName = "Xcode"

    // Before: no niche picked, so the user doesn't know what to ask and
    // Clicky can only answer generically.
    static let coldOpenAskTranscript = "I just opened Xcode. What can you even help me with here?"
    static let genericCapabilitiesResponse = "I can see your screen and explain anything on it — tell me what you're trying to do and I'll walk you through it."

    // After: the user taps the first app-aware suggestion and gets an
    // informed, pointing-ready answer.
    static let pickedSuggestionAnswerResponse = "⌘2 opens the Source Control navigator — that's where commits live. I'd fly over and point at it on your screen right now."

    /// Shown only if the real snapshot unexpectedly returns no suggestions,
    /// so the conversation arc can still complete.
    static let fallbackPickedSuggestionPrompt = "How do I commit from Xcode? Point at the Source Control menu."

    /// Builds Clicky's suggestions bubble from the REAL snapshot: the real
    /// context label followed by the real prompts, so the bubble can never
    /// drift from what the suggestion engine returned.
    static func suggestionsBubbleText(from appAwareSnapshot: NicheSuggestionSnapshot?) -> String {
        guard let appAwareSnapshot, !appAwareSnapshot.suggestions.isEmpty else {
            return "I don't have app-aware suggestions for this screen yet — tell me what you're working on and I'll help from there."
        }

        let suggestionLines = appAwareSnapshot.suggestions
            .map { suggestion in "• \(suggestion.prompt)" }
            .joined(separator: "\n")
        return "\(appAwareSnapshot.contextLabel)\n\(suggestionLines)"
    }

    /// Human-readable proof text for the snapshot mode. With an explicit
    /// niche override the app-aware branch reports `.userOverride`, which
    /// the proof field spells out as a user-picked niche.
    static func suggestionModeProofDescription(for suggestionMode: NicheSuggestionSnapshot.Mode) -> String {
        switch suggestionMode {
        case .userOverride: return "app-aware (user-picked niche)"
        case .appAware: return "app-aware (inferred niche)"
        case .usageBased: return "usage-based"
        case .profileBiased: return "profile-biased"
        case .generalFallback: return "general fallback (unexpected)"
        }
    }
}

/// Read-only answer assembly for one Ask Clicky quick ask, passed to the
/// real Clicky overlay for TTS playback.
private struct AskClickyComputedResult {
    let spokenText: String
    /// Skill names that informed the answer — drives the overlay's
    /// "using what you learned" chip while TTS plays.
    let matchedSkillNames: [String]
    let lastMatchedMemoryDescription: String
    let promptSectionsIncludedDescription: String
    let beforeAfterMetricDescription: String
}

/// The deterministic copy behind the Ask Clicky quick asks. Unlike the
/// feature demo scripts, the spoken answers are largely ASSEMBLED from
/// real store contents at run time (skill names, memory titles, matcher
/// results), so the spoken claims can never drift from what is actually on
/// disk — only the connective phrasing is fixed.
private enum AskClickyScript {
    static let xcodeBundleId = "com.apple.dt.Xcode"

    /// Short stand-in for the production voice system prompt. The proofs
    /// are about whether TeachingPromptBuilder appends its sections, which
    /// works identically regardless of the base prompt text.
    static let demoBasePrompt = "you are clicky, a voice screen tutor. answer briefly."

    /// TTS-friendly version of the recall answer — bullets flattened into
    /// flowing speech.
    static func whatDidYouLearnSpokenText(
        recalledActiveSkills: [TeachingSkill],
        recalledActivePreferences: [Memory],
        recalledActiveRoutines: [Memory]
    ) -> String {
        whatDidYouLearnAnswerText(
            recalledActiveSkills: recalledActiveSkills,
            recalledActivePreferences: recalledActivePreferences,
            recalledActiveRoutines: recalledActiveRoutines
        )
        .replacingOccurrences(of: "\n• ", with: ". ")
        .replacingOccurrences(of: "\n", with: " ")
    }

    /// Builds the "what did you learn about me?" answer from the REAL
    /// recalled store contents, with an honest empty-state line when
    /// nothing has been learned yet.
    static func whatDidYouLearnAnswerText(
        recalledActiveSkills: [TeachingSkill],
        recalledActivePreferences: [Memory],
        recalledActiveRoutines: [Memory]
    ) -> String {
        let recalledMemoryTotal = recalledActiveSkills.count
            + recalledActivePreferences.count
            + recalledActiveRoutines.count
        guard recalledMemoryTotal > 0 else {
            return "Nothing yet — I learn from our sessions. Teach me a workflow once, or load a demo profile, and ask me again."
        }

        var answerLines = ["Here's what I've learned about you so far:"]
        if !recalledActiveSkills.isEmpty {
            let skillNames = recalledActiveSkills.map(\.name).joined(separator: ", ")
            answerLines.append("• Workflows I can repeat: \(skillNames)")
        }
        if !recalledActivePreferences.isEmpty {
            let preferenceTitles = recalledActivePreferences.map(\.title).joined(separator: ", ")
            answerLines.append("• How you like to be taught: \(preferenceTitles)")
        }
        if !recalledActiveRoutines.isEmpty {
            let routineTitles = recalledActiveRoutines.map(\.title).joined(separator: ", ")
            answerLines.append("• Routines I've noticed: \(routineTitles)")
        }
        return answerLines.joined(separator: "\n")
    }

    /// Commit answer copy. The step-by-step phrasing is only used when the
    /// top match really is the demo commit skill (the one both the Skills
    /// demo and the Developer profile write); any other matched skill gets
    /// a name-accurate generic line, and no match gets the honest
    /// not-learned-yet line.
    static func commitAnswerText(topMatchedSkill: TeachingSkill?) -> String {
        guard let topMatchedSkill else {
            return "I haven't learned your commit flow yet — walk through it with me once (or run the Skills demo) and I'll remember it."
        }
        guard topMatchedSkill.id == SkillsDemoScript.commitSkillId else {
            return "I have your saved \u{201C}\(topMatchedSkill.name)\u{201D} flow — want me to walk you through it?"
        }
        return "Same as last time: ⌘2 for Source Control, check your files, write the message, hit ⌘⏎. You've got this."
    }

    /// "What should I do next?" answer copy, grounded in whichever real
    /// signal was found: a matched routine memory first, then a detected
    /// routine chip, then honest no-signal fallbacks.
    static func whatNextAnswerText(
        simulatedAppContext: SimulationDemoAppContext?,
        topMatchedRoutineMemory: Memory?,
        detectedRoutineChipForContextApp: RoutineSuggestion?
    ) -> String {
        guard let simulatedAppContext else {
            return "I'm not sure which app you're in — load a demo profile to simulate one, or just tell me what you're working on."
        }
        if let topMatchedRoutineMemory {
            return "This is usually where your \u{201C}\(topMatchedRoutineMemory.title)\u{201D} routine kicks in — \(topMatchedRoutineMemory.summary). Want me to walk you through the steps?"
        }
        if let detectedRoutineChipForContextApp {
            return "\(detectedRoutineChipForContextApp.label) — looks like that's your pattern right now. Want to pick up from there?"
        }
        return "I haven't noticed a routine for \(simulatedAppContext.displayName) yet — tell me what you're working on and I'll help from there."
    }

    /// Badge under the "what should I do next?" answer bubble, reflecting
    /// the strongest real signal found (routine memory over chip), or nil
    /// when nothing matched.
    static func whatNextAnswerBadge(
        topMatchedRoutineMemory: Memory?,
        detectedRoutineChipForContextApp: RoutineSuggestion?
    ) -> String? {
        if let topMatchedRoutineMemory {
            return "Routine: \(topMatchedRoutineMemory.title)"
        }
        if let detectedRoutineChipForContextApp {
            return "Routine chip: \(detectedRoutineChipForContextApp.label)"
        }
        return nil
    }
}
