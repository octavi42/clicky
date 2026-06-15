//
//  ProactivePreferenceTests.swift
//  leanring-buddyTests
//

import Testing
import Foundation
@testable import leanring_buddy

@MainActor
struct ProactivePreferenceTests {

    @Test func detectStatedPreferenceReturnsCorrectAxisAndPhrase() async throws {
        let transcript = "From now on, always keep your answers short"
        let result = PreferenceSignalDetector.detectStatedPreference(in: transcript)
        
        #expect(result != nil)
        #expect(result?.axis == .answerLength)
        #expect(result?.phrase == transcript)
    }

    @Test func detectStatedPreferenceIgnoresQuestions() async throws {
        let transcript = "How do I always keep my answers short?"
        let result = PreferenceSignalDetector.detectStatedPreference(in: transcript)
        
        #expect(result == nil)
    }

    @Test func detectStatedPreferenceHandlesTone() async throws {
        let transcript = "I'd prefer you be more casual"
        let result = PreferenceSignalDetector.detectStatedPreference(in: transcript)
        
        #expect(result != nil)
        #expect(result?.axis == .tone)
    }

    @Test func detectStatedPreferenceHandlesInputStyle() async throws {
        let transcript = "Use the keyboard instead of menus"
        let result = PreferenceSignalDetector.detectStatedPreference(in: transcript)
        
        #expect(result != nil)
        #expect(result?.axis == .inputModality)
    }

}
