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
