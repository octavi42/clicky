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

@MainActor
final class SimulationDemoEngine: ObservableObject {
    @Published private(set) var loadedDemoProfile: SimulationDemoProfile?
    @Published private(set) var demoSkillCount: Int = 0
    @Published private(set) var demoPreferenceCount: Int = 0
    @Published private(set) var demoRoutineMemoryCount: Int = 0
    @Published private(set) var simulatedAppContextDisplayName: String?
    @Published private(set) var lastRunStatusDescription: String = "Not run yet"

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
