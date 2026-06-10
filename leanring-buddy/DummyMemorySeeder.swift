//
//  DummyMemorySeeder.swift
//  leanring-buddy
//
//  Seeds sample memories for local UI testing.
//  DEBUG builds only — adds any dummy entries not already on disk.
//

import Foundation

enum DummyMemorySeeder {
    static func seedMissingDummyMemories(
        skillStore: TeachingSkillStore,
        auxiliaryStore: AuxiliaryMemoryStore
    ) {
        #if DEBUG
        // Skip seeding under E2E so dummy skills never pollute the store the
        // automated harness asserts against.
        guard !ClickyE2EConfiguration.isEnabled else { return }

        var seededCount = 0

        for dummySkill in makeDummySkills() where skillStore.skill(withID: dummySkill.id) == nil {
            try? skillStore.saveSkill(dummySkill)
            seededCount += 1
        }

        for dummyMemory in makeDummyAuxiliaryMemories() where auxiliaryStore.memory(withID: dummyMemory.id) == nil {
            try? auxiliaryStore.save(dummyMemory)
            seededCount += 1
        }

        guard seededCount > 0 else { return }
        print("🧪 Seeded \(seededCount) dummy memories for UI testing")
        #endif
    }

    #if DEBUG
    private static func makeDummySkills() -> [TeachingSkill] {
        [
            TeachingSkill(
                id: "teach-textedit-save",
                name: "Save a document in TextEdit",
                description: "Walk through saving the current document to disk",
                bundleIds: ["com.apple.TextEdit"],
                status: .active,
                lastUsed: Date().addingTimeInterval(-86400),
                usageCount: 5,
                isPinned: false,
                taskSlug: "save",
                receipts: [
                    MemoryReceipt(
                        savedAt: Date().addingTimeInterval(-86400),
                        sessionId: UUID(),
                        gateReasons: [.userConfirmed, .screenTeaching],
                        appBundleId: "com.apple.TextEdit",
                        userAsk: "how do I save this document?",
                        triggerPhrase: "perfect, that worked",
                        assistantAnswerSummary: "press command s, pick a folder and filename, then click save.",
                        userConfirmedItWorked: true,
                        updatedExistingMemory: false
                    )
                ],
                body: """
                1. Click **File** in the menu bar.
                2. Choose **Save** (or press ⌘S).
                3. Pick a folder and filename, then click **Save**.
                """
            ),
            TeachingSkill(
                id: "teach-xcode-commit",
                name: "Commit changes in Xcode",
                description: "Stage and commit your current changes via Source Control",
                bundleIds: ["com.apple.dt.Xcode"],
                status: .active,
                lastUsed: Date().addingTimeInterval(-172800),
                usageCount: 3,
                isPinned: false,
                taskSlug: "commit",
                receipts: [
                    MemoryReceipt(
                        savedAt: Date().addingTimeInterval(-172800),
                        sessionId: UUID(),
                        gateReasons: [.repeatedTopic, .screenTeaching],
                        appBundleId: "com.apple.dt.Xcode",
                        userAsk: "how do I commit my changes again?",
                        triggerPhrase: nil,
                        assistantAnswerSummary: "open source control, check your files, enter a message, and hit commit.",
                        userConfirmedItWorked: false,
                        updatedExistingMemory: false
                    )
                ],
                body: """
                1. Open the **Source Control** navigator (⌘2).
                2. Review changed files and check the ones to include.
                3. Enter a commit message and click **Commit**.
                """
            ),
            TeachingSkill(
                id: "teach-xcode-breakpoint",
                name: "Set a breakpoint in Xcode",
                description: "Pause execution on a line while debugging",
                bundleIds: ["com.apple.dt.Xcode"],
                status: .active,
                lastUsed: Date().addingTimeInterval(-43200),
                usageCount: 2,
                isPinned: false,
                taskSlug: "breakpoint",
                receipts: [
                    MemoryReceipt(
                        savedAt: Date().addingTimeInterval(-43200),
                        sessionId: UUID(),
                        gateReasons: [.multiStepPointing, .screenTeaching],
                        appBundleId: "com.apple.dt.Xcode",
                        userAsk: "how do I pause on this line while debugging?",
                        triggerPhrase: nil,
                        assistantAnswerSummary: "click the gutter next to the line number to set a breakpoint, then run with the debugger.",
                        userConfirmedItWorked: false,
                        updatedExistingMemory: false
                    )
                ],
                body: """
                1. Click the gutter to the left of the line number.
                2. Run with the debugger (⌘R).
                3. Execution pauses when that line is hit.
                """
            ),
            TeachingSkill(
                id: "teach-safari-inspector",
                name: "Open Web Inspector in Safari",
                description: "Inspect page elements with Safari's developer tools",
                bundleIds: ["com.apple.Safari"],
                status: .active,
                lastUsed: Date().addingTimeInterval(-129600),
                usageCount: 1,
                isPinned: false,
                taskSlug: "inspector",
                receipts: [
                    MemoryReceipt(
                        savedAt: Date().addingTimeInterval(-129600),
                        sessionId: UUID(),
                        gateReasons: [.userConfirmed, .repeatedTopic, .screenTeaching],
                        appBundleId: "com.apple.Safari",
                        userAsk: "where is the web inspector in Safari?",
                        triggerPhrase: "got it, that helps",
                        assistantAnswerSummary: "enable the develop menu in settings, then choose develop → show web inspector.",
                        userConfirmedItWorked: true,
                        updatedExistingMemory: false
                    )
                ],
                body: """
                1. Enable **Develop** menu in Safari Settings → Advanced.
                2. Choose **Develop → Show Web Inspector**.
                3. Pick the page tab to inspect.
                """
            ),
            TeachingSkill(
                id: "teach-finder-new-folder",
                name: "Create a new folder in Finder",
                description: "Make a new folder in the current Finder window",
                bundleIds: ["com.apple.finder"],
                status: .stale,
                lastUsed: Date().addingTimeInterval(-604800),
                usageCount: 1,
                isPinned: false,
                taskSlug: "new-folder",
                body: """
                1. In Finder, go to the location where you want the folder.
                2. Choose **File → New Folder** (⇧⌘N).
                3. Type the folder name and press Return.
                """
            ),
            TeachingSkill(
                id: "teach-safari-bookmark",
                name: "Bookmark a page in Safari",
                description: "Save the current tab as a bookmark for later",
                bundleIds: ["com.apple.Safari"],
                status: .archived,
                lastUsed: Date().addingTimeInterval(-1209600),
                usageCount: 2,
                isPinned: false,
                taskSlug: "bookmark",
                body: """
                1. With the page open, click the **Share** button in the toolbar.
                2. Choose **Add Bookmark**.
                3. Name it and pick a folder, then click **Add**.
                """
            )
        ]
    }

    private static func makeDummyAuxiliaryMemories() -> [Memory] {
        [
            Memory(
                id: "pref-concise-answers",
                category: .preference,
                title: "Prefer concise answers",
                summary: "Keep explanations short unless more detail is asked for",
                body: """
                When helping with quick tasks, favor short step lists over long explanations.
                Offer to expand only if the user asks follow-up questions.
                """,
                usageCount: 2,
                lastUsed: Date().addingTimeInterval(-259200),
                receipts: [
                    MemoryReceipt(
                        savedAt: Date().addingTimeInterval(-259200),
                        sessionId: UUID(),
                        gateReasons: [.statedPreference],
                        appBundleId: "com.apple.dt.Xcode",
                        userAsk: "can you explain what this function does?",
                        triggerPhrase: "keep answers short from now on",
                        assistantAnswerSummary: "short version: it parses the config file and falls back to defaults.",
                        userConfirmedItWorked: false,
                        updatedExistingMemory: false
                    )
                ]
            ),
            Memory(
                id: "pref-dark-apps",
                category: .preference,
                title: "Use dark mode in dev tools",
                summary: "Default to dark themes in Xcode and terminal apps",
                body: """
                When pointing at appearance settings, assume dark mode is preferred in developer tools.
                """,
                usageCount: 1,
                lastUsed: Date().addingTimeInterval(-432000),
                receipts: [
                    MemoryReceipt(
                        savedAt: Date().addingTimeInterval(-432000),
                        sessionId: UUID(),
                        gateReasons: [.statedPreference],
                        appBundleId: "com.apple.dt.Xcode",
                        userAsk: "how do I change the theme in Xcode?",
                        triggerPhrase: "I prefer dark mode in all my dev tools",
                        assistantAnswerSummary: "open settings, go to themes, and pick the dark appearance.",
                        userConfirmedItWorked: false,
                        updatedExistingMemory: false
                    )
                ]
            ),
            Memory(
                id: "pref-keyboard-only",
                category: .preference,
                title: "Keyboard shortcuts over menus",
                summary: "Prefer keyboard paths instead of menu walkthroughs",
                body: """
                When teaching UI tasks, lead with keyboard shortcuts first.
                Only mention menu paths if the user asks or a shortcut does not exist.
                """,
                bundleIds: ["com.apple.dt.Xcode"],
                usageCount: 3,
                lastUsed: Date().addingTimeInterval(-86400),
                receipts: [
                    MemoryReceipt(
                        savedAt: Date().addingTimeInterval(-86400),
                        sessionId: UUID(),
                        gateReasons: [.statedPreference],
                        appBundleId: "com.apple.dt.Xcode",
                        userAsk: "how do I refactor this method name?",
                        triggerPhrase: "always give me the keyboard shortcut, not the menu",
                        assistantAnswerSummary: "select the symbol and press control command e to rename across the project.",
                        userConfirmedItWorked: false,
                        updatedExistingMemory: false
                    )
                ]
            ),
            Memory(
                id: "pref-answer-depth",
                category: .preference,
                title: "Go deeper on code explanations",
                summary: "Give detailed explanations when discussing code",
                body: """
                When the user is asking about code, include context, tradeoffs, and edge cases.
                Do not default to one-line answers for programming questions.
                """,
                usageCount: 5,
                lastUsed: Date().addingTimeInterval(-7200),
                receipts: [
                    MemoryReceipt(
                        savedAt: Date().addingTimeInterval(-604800),
                        sessionId: UUID(),
                        gateReasons: [.statedPreference],
                        appBundleId: "com.apple.dt.Xcode",
                        userAsk: "what does this async function do?",
                        triggerPhrase: "keep answers short from now on",
                        assistantAnswerSummary: "it awaits the network call and returns the parsed json body.",
                        userConfirmedItWorked: false,
                        updatedExistingMemory: false
                    ),
                    MemoryReceipt(
                        savedAt: Date().addingTimeInterval(-7200),
                        sessionId: UUID(),
                        gateReasons: [.styleCorrection],
                        appBundleId: "com.apple.dt.Xcode",
                        userAsk: "explain this error in the console",
                        triggerPhrase: "that's too short, go deeper when explaining code",
                        assistantAnswerSummary: "the error means the task was cancelled before the await finished; check your task group lifecycle.",
                        userConfirmedItWorked: false,
                        updatedExistingMemory: true
                    )
                ]
            ),
            Memory(
                id: "routine-standup-prep",
                category: .routine,
                title: "Morning standup prep",
                summary: "Review yesterday's commits before the daily standup",
                body: """
                1. Open Xcode Source Control or git log.
                2. Scan commits from the previous workday.
                3. Note blockers to mention in standup.
                """,
                bundleIds: ["com.apple.dt.Xcode"],
                usageCount: 4,
                lastUsed: Date().addingTimeInterval(-345600),
                receipts: [
                    MemoryReceipt(
                        savedAt: Date().addingTimeInterval(-345600),
                        sessionId: UUID(),
                        gateReasons: [.recurringRoutine],
                        appBundleId: "com.apple.dt.Xcode",
                        userAsk: "walk me through my standup prep again",
                        triggerPhrase: nil,
                        assistantAnswerSummary: "open source control, skim yesterday's commits, and jot down blockers before the call.",
                        userConfirmedItWorked: false,
                        updatedExistingMemory: false
                    )
                ]
            ),
            Memory(
                id: "routine-fcp-export",
                category: .routine,
                title: "Export video from Final Cut",
                summary: "Repeated export workflow before sharing a cut",
                body: """
                1. Choose **File → Share → Master File**.
                2. Pick H.264 or ProRes depending on destination.
                3. Set the output folder and click **Save**.
                """,
                bundleIds: ["com.apple.FinalCut"],
                usageCount: 6,
                lastUsed: Date().addingTimeInterval(-172800),
                receipts: [
                    MemoryReceipt(
                        savedAt: Date().addingTimeInterval(-172800),
                        sessionId: UUID(),
                        gateReasons: [.recurringRoutine],
                        appBundleId: "com.apple.FinalCut",
                        userAsk: "I need to export this timeline again",
                        triggerPhrase: nil,
                        assistantAnswerSummary: "use file → share → master file, pick your codec, and save to the exports folder.",
                        userConfirmedItWorked: false,
                        updatedExistingMemory: false
                    )
                ]
            ),
            Memory(
                id: "routine-pr-review",
                category: .routine,
                title: "Review a pull request",
                summary: "Open GitHub, read the diff, leave comments",
                body: """
                1. Open the PR in the browser.
                2. Read the **Files changed** tab top to bottom.
                3. Leave inline comments on anything unclear.
                4. Approve or request changes.
                """,
                bundleIds: ["com.apple.Safari"],
                usageCount: 2,
                lastUsed: Date().addingTimeInterval(-518400),
                receipts: [
                    MemoryReceipt(
                        savedAt: Date().addingTimeInterval(-518400),
                        sessionId: UUID(),
                        gateReasons: [.recurringRoutine],
                        appBundleId: "com.apple.Safari",
                        userAsk: "help me review this pull request like last time",
                        triggerPhrase: nil,
                        assistantAnswerSummary: "open files changed, scan the diff, comment inline, then approve or request changes.",
                        userConfirmedItWorked: false,
                        updatedExistingMemory: true
                    )
                ]
            )
        ]
    }
    #endif
}
