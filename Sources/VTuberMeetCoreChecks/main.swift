import Foundation
import VTuberMeetCore

@discardableResult
func check(_ condition: @autoclosure () -> Bool, _ message: String) -> Bool {
    if condition() {
        return true
    }

    FileHandle.standardError.write(Data("Check failed: \(message)\n".utf8))
    Foundation.exit(1)
}

let service = ChatService()

do {
    _ = try service.respondLocallyForChecks(to: "   ")
    check(false, "empty message should throw")
} catch {
    check(error as? ChatError == .emptyMessage, "empty message should throw ChatError.emptyMessage")
}

let response = try service.respondLocallyForChecks(to: "오늘 뭐 할까?")
check(response.mood == .curious, "question should infer curious mood")
check(response.motion == .tilt, "curious mood should map to tilt motion")
check(response.affect.expression == .curious, "curious mood should map to curious expression")
check(response.text.contains("오늘 뭐 할까?"), "response should include user text")

let angryResponse = try service.respondLocallyForChecks(to: "나 지금 너무 화나")
check(angryResponse.mood == .angry, "angry message should infer angry mood")
check(angryResponse.motion == .shake, "angry mood should map to shake motion")
check(angryResponse.affect.expression == .angry, "angry mood should map to angry expression")

let embarrassedResponse = try service.respondLocallyForChecks(to: "에치치 부끄럽잖아")
check(embarrassedResponse.mood == .embarrassed, "embarrassed message should infer embarrassed mood")
check(embarrassedResponse.affect.expression == .blush, "embarrassed mood should map to blush expression")

let sadResponse = try service.respondLocallyForChecks(to: "오늘 너무 속상하고 힘들어")
check(sadResponse.mood == .sad, "sad message should infer sad mood")
check(sadResponse.motion == .nod, "sad mood should map to nod motion")

let surprisedResponse = try service.respondLocallyForChecks(to: "헉 진짜? 대박")
check(surprisedResponse.mood == .surprised, "surprised message should infer surprised mood")
check(surprisedResponse.motion == .recoil, "surprised mood should map to recoil motion")

let closed = LipSync.mouthOpen(elapsedSeconds: 1.0, speaking: false)
let open = LipSync.mouthOpen(elapsedSeconds: 1.4, speaking: true)
check(closed == 0, "mouth should close when not speaking")
check(open > 0.07, "mouth should open while speaking")
check(open <= 0.98, "mouth should stay clamped")

let ttsConfiguration = try LocalTTSConfiguration.load(environment: [:])
check(ttsConfiguration.apiURL.absoluteString == "http://127.0.0.1:9888/", "Local TTS default URL should be local")
check(ttsConfiguration.audioFormat == .wav, "Local TTS should default to WAV")
check(ttsConfiguration.generatedAudioDirectory.path.hasSuffix("outputs/tts_generated"), "Local TTS should default to generated audio cache")
let customTTSConfiguration = try LocalTTSConfiguration.load(environment: [
    "LOCAL_TTS_API_URL": "http://localhost:9888/",
    "LOCAL_TTS_AUDIO_FORMAT": "mp3",
    "LOCAL_TTS_OUTPUT_DIR": "/tmp/local-tts-generated"
])
check(customTTSConfiguration.apiURL.absoluteString == "http://localhost:9888/", "Local TTS URL should be configurable")
check(customTTSConfiguration.audioFormat == .mp3, "Local TTS format should be configurable")
check(customTTSConfiguration.generatedAudioDirectory.path == "/tmp/local-tts-generated", "Local TTS output directory should be configurable")
let normalizedTTS = try LocalTTSService.normalizedText("  안녕, 오늘 좋아  ", maximumLength: 20)
check(normalizedTTS == "안녕, 오늘 좋아", "Local TTS text should be trimmed")
do {
    _ = try LocalTTSService.normalizedText("   ", maximumLength: 20)
    check(false, "empty TTS text should throw")
} catch {
    check(error as? LocalTTSError == .emptyText, "empty TTS text should throw LocalTTSError.emptyText")
}
do {
    _ = try LocalTTSService.normalizedText("123456", maximumLength: 5)
    check(false, "long TTS text should throw")
} catch {
    check(error as? LocalTTSError == .textTooLong(maximum: 5), "long TTS text should throw LocalTTSError.textTooLong")
}

let selectedGemma = try OllamaClient.selectPreferredModel(from: ["qwen2.5:3b", "gemma3:4b"])
check(selectedGemma == "gemma3:4b", "Gemma model selection should prefer installed Gemma")
let selectedGemma4 = try OllamaClient.selectPreferredModel(from: ["gemma3:4b", "gemma4:e4b"])
check(selectedGemma4 == "gemma4:e4b", "Gemma model selection should prefer Gemma 4 when installed")

let json = """
[
  {
    "id": "mao-niziiro",
    "name": "Mao Niziiro",
    "description": "Official Live2D model",
    "style": "live2d-model",
    "license": "Live2D Free Material License",
    "source": "https://github.com/Live2D/CubismWebSamples/tree/develop/Samples/Resources/Mao",
    "attribution": "Live2D Inc.",
    "modelDirectory": "Avatars/Mao",
    "modelFile": "Mao.model3.json",
    "licenseFile": "Avatars/Mao/license.md",
    "redistribution": "allowed"
  }
]
"""

let presets = try AvatarManifest.decode(Data(json.utf8))
check(presets.count == 1, "manifest should decode one preset")
check(presets[0].style == .live2DModel, "manifest should decode Live2D model style")
check(presets[0].redistribution == .allowed, "manifest should decode redistribution")
check(presets[0].modelFile == "Mao.model3.json", "manifest should include model file")

let repositoryManifestURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/VTuberMeet/Resources/Avatars/manifest.json")
let repositoryManifest = try AvatarManifest.decode(Data(contentsOf: repositoryManifestURL))
check(repositoryManifest.count >= 5, "bundled manifest should include several cute Live2D presets")
check(repositoryManifest[0].id == "hiyori-momose", "default bundled manifest preset should be Hiyori Momose")
check(repositoryManifest.contains { $0.id == "mao-niziiro" }, "bundled manifest should include Mao")
check(repositoryManifest.contains { $0.id == "wanko-sample" }, "bundled manifest should include Wanko")

let resourceRootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/VTuberMeet/Resources")

for preset in repositoryManifest {
    check(preset.style == .live2DModel, "bundled manifest preset should use a real Live2D model")
    guard let profile = AvatarExpressionProfiles.profile(for: preset.id) else {
        check(false, "bundled \(preset.name) should have an avatar expression profile")
        continue
    }
    check(!profile.lipSyncParameters.isEmpty, "bundled \(preset.name) profile should include lip-sync parameters")

    let modelURL = resourceRootURL
        .appendingPathComponent(preset.modelDirectory)
        .appendingPathComponent(preset.modelFile)
    let licenseURL = resourceRootURL.appendingPathComponent(preset.licenseFile)
    check(FileManager.default.fileExists(atPath: modelURL.path), "bundled \(preset.name) model3 file should exist")
    check(FileManager.default.fileExists(atPath: licenseURL.path), "bundled \(preset.name) license file should exist")

    let expressionNames = try expressionNames(in: modelURL)
    if profile.supportsNamedExpressions {
        check(!profile.namedExpressions.isEmpty, "bundled \(preset.name) profile should map named expressions")
        for expressionName in Set(profile.namedExpressions.values) {
            check(expressionNames.contains(expressionName), "bundled \(preset.name) model should include expression \(expressionName)")
        }
    } else {
        check(profile.namedExpressions.isEmpty, "bundled \(preset.name) fallback profile should not require named expressions")
    }
}

print("VTuberMeetCoreChecks passed")

private func expressionNames(in modelURL: URL) throws -> Set<String> {
    let data = try Data(contentsOf: modelURL)
    let object = try JSONSerialization.jsonObject(with: data)
    guard let root = object as? [String: Any],
          let fileReferences = root["FileReferences"] as? [String: Any],
          let expressions = fileReferences["Expressions"] as? [[String: Any]] else {
        return []
    }

    return Set(expressions.compactMap { $0["Name"] as? String })
}
