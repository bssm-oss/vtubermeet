import Foundation

public struct AvatarExpressionProfile: Equatable, Sendable {
    public let presetID: String
    public let supportsNamedExpressions: Bool
    public let namedExpressions: [CompanionExpression: String]
    public let lipSyncParameters: [String]

    public init(
        presetID: String,
        supportsNamedExpressions: Bool,
        namedExpressions: [CompanionExpression: String],
        lipSyncParameters: [String]
    ) {
        self.presetID = presetID
        self.supportsNamedExpressions = supportsNamedExpressions
        self.namedExpressions = namedExpressions
        self.lipSyncParameters = lipSyncParameters
    }
}

public enum AvatarExpressionProfiles {
    public static let all: [AvatarExpressionProfile] = [
        AvatarExpressionProfile(
            presetID: "hiyori-momose",
            supportsNamedExpressions: false,
            namedExpressions: [:],
            lipSyncParameters: ["ParamMouthOpenY"]
        ),
        AvatarExpressionProfile(
            presetID: "haru-live2d",
            supportsNamedExpressions: true,
            namedExpressions: [
                .neutral: "F01",
                .smile: "F02",
                .curious: "F04",
                .angry: "F03",
                .sad: "F05",
                .surprised: "F06",
                .blush: "F07",
                .pout: "F03"
            ],
            lipSyncParameters: ["ParamMouthOpenY"]
        ),
        AvatarExpressionProfile(
            presetID: "mao-niziiro",
            supportsNamedExpressions: true,
            namedExpressions: [
                .neutral: "exp_01",
                .smile: "exp_02",
                .curious: "exp_04",
                .angry: "exp_03",
                .sad: "exp_05",
                .surprised: "exp_06",
                .blush: "exp_07",
                .pout: "exp_03"
            ],
            lipSyncParameters: ["ParamA"]
        ),
        AvatarExpressionProfile(
            presetID: "rice-glassfield",
            supportsNamedExpressions: false,
            namedExpressions: [:],
            lipSyncParameters: ["ParamMouthOpenY", "ParamA"]
        ),
        AvatarExpressionProfile(
            presetID: "natori-sample",
            supportsNamedExpressions: true,
            namedExpressions: [
                .neutral: "Normal",
                .smile: "Smile",
                .curious: "Surprised",
                .angry: "Angry",
                .sad: "Sad",
                .surprised: "Surprised",
                .blush: "Blushing",
                .pout: "Angry"
            ],
            lipSyncParameters: ["ParamMouthOpenY"]
        ),
        AvatarExpressionProfile(
            presetID: "ren-sample",
            supportsNamedExpressions: true,
            namedExpressions: [
                .neutral: "exp_01",
                .smile: "exp_02",
                .curious: "exp_04",
                .angry: "exp_03",
                .sad: "exp_05",
                .surprised: "exp_04",
                .blush: "exp_02",
                .pout: "exp_03"
            ],
            lipSyncParameters: ["ParamMouthOpenY"]
        )
    ]

    public static func profile(for presetID: String) -> AvatarExpressionProfile? {
        all.first { $0.presetID == presetID }
    }

    public static func fallback(for presetID: String) -> AvatarExpressionProfile {
        AvatarExpressionProfile(
            presetID: presetID,
            supportsNamedExpressions: false,
            namedExpressions: [:],
            lipSyncParameters: ["ParamMouthOpenY", "ParamA"]
        )
    }
}
