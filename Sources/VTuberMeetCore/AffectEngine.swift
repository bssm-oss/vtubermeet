import Foundation

public enum CompanionExpression: String, Codable, CaseIterable, Sendable {
    case neutral
    case smile
    case curious
    case angry
    case sad
    case surprised
    case blush
    case pout
}

public enum AffectSource: String, Codable, Sendable {
    case deterministicRules
    case fallback
    case normalizedLLMSuggestion
}

public struct CompanionAffect: Codable, Equatable, Sendable {
    public let mood: CompanionMood
    public let expression: CompanionExpression
    public let motion: CompanionMotion
    public let intensity: Double
    public let duration: Double
    public let confidence: Double
    public let source: AffectSource

    public init(
        mood: CompanionMood,
        expression: CompanionExpression,
        motion: CompanionMotion,
        intensity: Double,
        duration: Double,
        confidence: Double,
        source: AffectSource
    ) {
        self.mood = mood
        self.expression = expression
        self.motion = motion
        self.intensity = Self.clamp(intensity, lower: 0, upper: 1)
        self.duration = Self.clamp(duration, lower: 0.4, upper: 8.0)
        self.confidence = Self.clamp(confidence, lower: 0, upper: 1)
        self.source = source
    }

    public static let neutral = CompanionAffect(
        mood: .calm,
        expression: .neutral,
        motion: .idle,
        intensity: 0.25,
        duration: 1.4,
        confidence: 1.0,
        source: .fallback
    )

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(upper, max(lower, value))
    }
}

public enum AffectEngine {
    public static func evaluate(userText: String, assistantText: String) -> CompanionAffect {
        infer(from: "\(userText) \(assistantText)", source: .deterministicRules)
    }

    public static func infer(from text: String, source: AffectSource = .deterministicRules) -> CompanionAffect {
        let normalized = text.lowercased()

        if containsAny(normalized, ["화", "짜증", "싫", "나빠", "미워", "분노", "삐졌", "열받"]) {
            return make(mood: .angry, source: source, confidence: 0.9)
        }

        if containsAny(normalized, ["부끄", "에치치", "쑥스", "민망", "창피"]) {
            return make(mood: .embarrassed, source: source, confidence: 0.84)
        }

        if containsAny(normalized, ["슬퍼", "우울", "속상", "눈물", "힘들", "아파", "못했", "실패"]) {
            return make(mood: .sad, source: source, confidence: 0.82)
        }

        if containsAny(normalized, ["깜짝", "헉", "대박", "놀랐", "뭐라고", "진짜?"]) {
            return make(mood: .surprised, source: source, confidence: 0.8)
        }

        if containsAny(normalized, ["?", "？", "뭐", "왜", "어떻게", "궁금", "모르", "헷갈"]) {
            return make(mood: .curious, source: source, confidence: 0.86)
        }

        if containsAny(normalized, ["!", "！", "좋", "귀엽", "ㅋㅋ", "ㅎㅎ", "신나", "잘했", "최고", "반가"]) {
            return make(mood: .happy, source: source, confidence: 0.84)
        }

        return make(mood: .calm, source: source, confidence: 0.72)
    }

    public static func make(mood: CompanionMood, source: AffectSource = .deterministicRules, confidence: Double = 0.8) -> CompanionAffect {
        CompanionAffect(
            mood: mood,
            expression: expression(for: mood),
            motion: motion(for: mood),
            intensity: intensity(for: mood),
            duration: duration(for: mood),
            confidence: confidence,
            source: source
        )
    }

    public static func expression(for mood: CompanionMood) -> CompanionExpression {
        switch mood {
        case .calm: .neutral
        case .happy: .smile
        case .curious: .curious
        case .angry: .angry
        case .sad: .sad
        case .surprised: .surprised
        case .embarrassed: .blush
        }
    }

    public static func motion(for mood: CompanionMood) -> CompanionMotion {
        switch mood {
        case .calm: .idle
        case .happy: .bounce
        case .curious: .tilt
        case .angry: .shake
        case .sad: .nod
        case .surprised: .recoil
        case .embarrassed: .leanIn
        }
    }

    private static func intensity(for mood: CompanionMood) -> Double {
        switch mood {
        case .calm: 0.25
        case .happy: 0.72
        case .curious: 0.58
        case .angry: 0.82
        case .sad: 0.48
        case .surprised: 0.76
        case .embarrassed: 0.62
        }
    }

    private static func duration(for mood: CompanionMood) -> Double {
        switch mood {
        case .calm: 1.4
        case .happy: 3.0
        case .curious: 3.2
        case .angry: 2.4
        case .sad: 3.6
        case .surprised: 1.8
        case .embarrassed: 3.0
        }
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
