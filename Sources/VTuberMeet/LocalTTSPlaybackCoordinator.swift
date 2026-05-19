import AVFoundation
import Foundation
import VTuberMeetCore

@MainActor
final class LocalTTSPlaybackCoordinator {
    private var audioPlayer: AVAudioPlayer?
    private var mouthTimer: Timer?
    private lazy var delegateProxy = LocalTTSAudioDelegateProxy(owner: self)
    private var onMouthOpen: ((Double) -> Void)?
    private var onSpeaking: ((Bool) -> Void)?

    func speak(
        text: String,
        endpointURL: URL,
        onMouthOpen: @escaping (Double) -> Void,
        onSpeaking: @escaping (Bool) -> Void
    ) async throws {
        stop()

        let audio = try await requestAudio(text: text, endpointURL: endpointURL)
        try Task.checkCancellation()

        let player = try AVAudioPlayer(data: audio)
        audioPlayer = player
        self.onMouthOpen = onMouthOpen
        self.onSpeaking = onSpeaking
        player.delegate = delegateProxy
        player.prepareToPlay()

        onSpeaking(true)
        startMouthTimer()

        if !player.play() {
            stop()
            throw LocalTTSPlaybackError.playbackFailed
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        mouthTimer?.invalidate()
        mouthTimer = nil
        onMouthOpen?(0)
        onSpeaking?(false)
        onMouthOpen = nil
        onSpeaking = nil
    }

    fileprivate func finishPlayback() {
        stop()
    }

    private func requestAudio(text: String, endpointURL: URL) async throws -> Data {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 70
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/*", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(TTSRequest(text: text))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalTTSPlaybackError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = decodeErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw LocalTTSPlaybackError.service(message)
        }
        guard !data.isEmpty else {
            throw LocalTTSPlaybackError.emptyAudio
        }

        return data
    }

    private func startMouthTimer() {
        mouthTimer?.invalidate()
        mouthTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let elapsed = self.audioPlayer?.currentTime ?? 0
                self.onMouthOpen?(LipSync.mouthOpen(elapsedSeconds: elapsed, speaking: self.audioPlayer?.isPlaying == true))
            }
        }
    }

    private func decodeErrorMessage(from data: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data) else {
            return String(data: data, encoding: .utf8)
        }
        return payload.error
    }

    private struct TTSRequest: Encodable {
        let text: String
    }

    private struct ErrorPayload: Decodable {
        let error: String
    }
}

enum LocalTTSPlaybackError: Error, LocalizedError {
    case invalidResponse
    case emptyAudio
    case playbackFailed
    case service(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "로컬 TTS 응답이 올바르지 않습니다."
        case .emptyAudio:
            "로컬 TTS가 빈 오디오를 반환했습니다."
        case .playbackFailed:
            "로컬 TTS 오디오를 재생하지 못했습니다."
        case let .service(message):
            message
        }
    }
}

private final class LocalTTSAudioDelegateProxy: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    weak var owner: LocalTTSPlaybackCoordinator?

    init(owner: LocalTTSPlaybackCoordinator) {
        self.owner = owner
        super.init()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak owner] in
            owner?.finishPlayback()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak owner] in
            owner?.finishPlayback()
        }
    }
}
