//
//  TeachingPromptBuilder.swift
//  leanring-buddy
//
//  Composes the voice response system prompt with matched teaching skills,
//  active preferences, and matched routines.
//

import Foundation

enum TeachingPromptBuilder {
    static func buildVoiceResponsePrompt(
        basePrompt: String,
        matchedSkills: [TeachingSkill],
        activePreferences: [Memory] = [],
        matchedRoutines: [Memory] = [],
        maxSkillCharacters: Int = 3500,
        maxPreferenceCharacters: Int = 800,
        maxRoutineCharacters: Int = 1200
    ) -> String {
        var promptSections: [String] = [basePrompt]

        if !matchedSkills.isEmpty {
            var usedCharacters = 0
            var renderedSkills: [String] = []

            for skill in matchedSkills {
                let rendered = skill.renderedMarkdown()
                if usedCharacters + rendered.count > maxSkillCharacters, !renderedSkills.isEmpty {
                    break
                }
                renderedSkills.append(rendered)
                usedCharacters += rendered.count
            }

            if !renderedSkills.isEmpty {
                promptSections.append("""
                teaching skills:
                the following local teaching notes were learned from earlier successful tutoring sessions on this mac. reuse them when they clearly apply. prefer the saved ui labels, menu paths, shortcuts, and pointing order over guessing.

                \(renderedSkills.joined(separator: "\n\n"))
                """)
            }
        }

        if !activePreferences.isEmpty {
            var usedCharacters = 0
            var renderedPreferences: [String] = []

            for preference in activePreferences {
                let rendered = renderMemory(preference)
                if usedCharacters + rendered.count > maxPreferenceCharacters, !renderedPreferences.isEmpty {
                    break
                }
                renderedPreferences.append(rendered)
                usedCharacters += rendered.count
            }

            if !renderedPreferences.isEmpty {
                promptSections.append("""
                user preferences:
                standing instructions about how this user wants help. honor these in every response.

                \(renderedPreferences.joined(separator: "\n\n"))
                """)
            }
        }

        if !matchedRoutines.isEmpty {
            var usedCharacters = 0
            var renderedRoutines: [String] = []

            for routine in matchedRoutines {
                let rendered = renderMemory(routine)
                if usedCharacters + rendered.count > maxRoutineCharacters, !renderedRoutines.isEmpty {
                    break
                }
                renderedRoutines.append(rendered)
                usedCharacters += rendered.count
            }

            if !renderedRoutines.isEmpty {
                promptSections.append("""
                recurring routines:
                workflows this user runs on a cadence. suggest or follow these steps when the current task matches.

                \(renderedRoutines.joined(separator: "\n\n"))
                """)
            }
        }

        guard promptSections.count > 1 else { return basePrompt }
        return promptSections.joined(separator: "\n\n")
    }

    /// Returns only the memory-injection suffix appended after `basePrompt`.
    /// Used by the presenter demo's X-Ray Prompt Peek to show the exact text
    /// Claude receives beyond the generic companion instructions.
    static func memoryInjectionExcerpt(basePrompt: String, builtPrompt: String) -> String? {
        let trimmedBasePrompt = basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBuiltPrompt = builtPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedBuiltPrompt.count > trimmedBasePrompt.count else { return nil }

        if trimmedBuiltPrompt.hasPrefix(trimmedBasePrompt) {
            let injectionExcerpt = trimmedBuiltPrompt
                .dropFirst(trimmedBasePrompt.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return injectionExcerpt.isEmpty ? nil : injectionExcerpt
        }

        // Defensive fallback when the base prompt was normalized differently
        // between build and peek (should not happen in the demo scripts).
        for sectionHeader in ["teaching skills:", "user preferences:", "recurring routines:"] {
            if let sectionRange = trimmedBuiltPrompt.range(of: sectionHeader) {
                return String(trimmedBuiltPrompt[sectionRange.lowerBound...])
            }
        }

        return nil
    }

    private static func renderMemory(_ memory: Memory) -> String {
        """
        - \(memory.title): \(memory.summary)
        \(memory.body)
        """
    }
}
