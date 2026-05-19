import Foundation

public struct AvatarPreset: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let style: AvatarStyle
    public let license: String
    public let source: String
    public let attribution: String
    public let redistribution: Redistribution
    public let modelDirectory: String
    public let modelFile: String
    public let licenseFile: String

    public init(
        id: String,
        name: String,
        description: String,
        style: AvatarStyle,
        license: String,
        source: String,
        attribution: String,
        redistribution: Redistribution,
        modelDirectory: String,
        modelFile: String,
        licenseFile: String
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.style = style
        self.license = license
        self.source = source
        self.attribution = attribution
        self.redistribution = redistribution
        self.modelDirectory = modelDirectory
        self.modelFile = modelFile
        self.licenseFile = licenseFile
    }
}

public enum AvatarStyle: String, Codable, Sendable {
    case appKitLive2DStyleRig = "appkit-live2d-style-rig"
    case live2DModel = "live2d-model"
}

public enum Redistribution: String, Codable, Sendable {
    case allowed
    case restricted
}

public enum AvatarManifestError: Error, Equatable, LocalizedError {
    case emptyManifest
    case invalidPreset(index: Int, reason: String)

    public var errorDescription: String? {
        switch self {
        case .emptyManifest:
            "Avatar manifest must include at least one preset."
        case let .invalidPreset(index, reason):
            "Avatar preset \(index) is invalid: \(reason)."
        }
    }
}

public enum AvatarManifest {
    public static func decode(_ data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> [AvatarPreset] {
        let presets = try decoder.decode([AvatarPreset].self, from: data)
        try validate(presets)
        return presets
    }

    public static func validate(_ presets: [AvatarPreset]) throws {
        guard !presets.isEmpty else {
            throw AvatarManifestError.emptyManifest
        }

        for (index, preset) in presets.enumerated() {
            try validateNonEmpty(preset.id, field: "id", index: index)
            try validateNonEmpty(preset.name, field: "name", index: index)
            try validateNonEmpty(preset.description, field: "description", index: index)
            try validateNonEmpty(preset.license, field: "license", index: index)
            try validateNonEmpty(preset.source, field: "source", index: index)
            try validateNonEmpty(preset.attribution, field: "attribution", index: index)
            try validateNonEmpty(preset.modelDirectory, field: "modelDirectory", index: index)
            try validateNonEmpty(preset.modelFile, field: "modelFile", index: index)
            try validateNonEmpty(preset.licenseFile, field: "licenseFile", index: index)

            if preset.style == .live2DModel && !preset.modelFile.hasSuffix(".model3.json") {
                throw AvatarManifestError.invalidPreset(index: index, reason: "Live2D modelFile must point to a .model3.json file")
            }
        }
    }

    private static func validateNonEmpty(_ value: String, field: String, index: Int) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AvatarManifestError.invalidPreset(index: index, reason: "\(field) cannot be empty")
        }
    }
}
