//
//  MemorySimilarityScorer.swift
//  leanring-buddy
//
//  Pluggable similarity scorers for preference/routine dedup decisions.
//

import Foundation
import NaturalLanguage

enum MemorySimilarityScorerKind: String, CaseIterable {
    case lexicalDice
    case appleEmbedding
    case hybrid
}

protocol MemorySimilarityScorer {
    func similarity(between textA: String, and textB: String) -> Double
}

/// Normalized token overlap using the Dice coefficient (0...1).
struct LexicalDiceSimilarityScorer: MemorySimilarityScorer {
    func similarity(between textA: String, and textB: String) -> Double {
        let tokensA = Set(SkillMatcher.meaningfulTokens(textA))
        let tokensB = Set(SkillMatcher.meaningfulTokens(textB))
        guard !tokensA.isEmpty, !tokensB.isEmpty else { return 0 }

        let sharedTokenCount = tokensA.intersection(tokensB).count
        return (2.0 * Double(sharedTokenCount)) / Double(tokensA.count + tokensB.count)
    }
}

/// On-device sentence embeddings via Apple's NaturalLanguage framework.
/// NLEmbedding is not thread-safe, so this scorer is main-actor isolated.
@MainActor
struct AppleEmbeddingSimilarityScorer: MemorySimilarityScorer {
    private let sentenceEmbedding: NLEmbedding?

    init() {
        sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
    }

    func similarity(between textA: String, and textB: String) -> Double {
        guard let sentenceEmbedding,
              let vectorA = sentenceEmbedding.vector(for: textA),
              let vectorB = sentenceEmbedding.vector(for: textB) else {
            return 0
        }

        return Self.cosineSimilarity(vectorA, vectorB)
    }

    private static func cosineSimilarity(_ vectorA: [Double], _ vectorB: [Double]) -> Double {
        guard vectorA.count == vectorB.count, !vectorA.isEmpty else { return 0 }

        var dotProduct = 0.0
        var normA = 0.0
        var normB = 0.0

        for index in 0..<vectorA.count {
            dotProduct += vectorA[index] * vectorB[index]
            normA += vectorA[index] * vectorA[index]
            normB += vectorB[index] * vectorB[index]
        }

        guard normA > 0, normB > 0 else { return 0 }
        let cosine = dotProduct / (normA.squareRoot() * normB.squareRoot())
        return max(0, min(1, cosine))
    }
}

enum MemorySimilarityScorerFactory {
    @MainActor
    static func makeScorer(for kind: MemorySimilarityScorerKind) -> any MemorySimilarityScorer {
        switch kind {
        case .lexicalDice:
            return LexicalDiceSimilarityScorer()
        case .appleEmbedding:
            return AppleEmbeddingSimilarityScorer()
        case .hybrid:
            return HybridMemorySimilarityScorer()
        }
    }
}

/// Combines lexical and Apple embedding signals. Lexical drives ranking; merge thresholds
/// are applied separately in AuxiliaryMemoryMatcher using both scores.
@MainActor
struct HybridMemorySimilarityScorer: MemorySimilarityScorer {
    private let lexicalScorer = LexicalDiceSimilarityScorer()
    private let appleScorer = AppleEmbeddingSimilarityScorer()

    func similarity(between textA: String, and textB: String) -> Double {
        max(
            lexicalScorer.similarity(between: textA, and: textB),
            appleScorer.similarity(between: textA, and: textB)
        )
    }

    func lexicalSimilarity(between textA: String, and textB: String) -> Double {
        lexicalScorer.similarity(between: textA, and: textB)
    }

    func appleSimilarity(between textA: String, and textB: String) -> Double {
        appleScorer.similarity(between: textA, and: textB)
    }
}
