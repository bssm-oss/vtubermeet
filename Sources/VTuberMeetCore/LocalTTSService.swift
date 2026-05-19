import CryptoKit
import Foundation

public struct LocalTTSConfiguration: Sendable {
    public enum AudioFormat: String, Sendable {
        case wav
        case mp3

        public var contentType: String {
            switch self {
            case .wav: "audio/wav"
            case .mp3: "audio/mpeg"
            }
        }
    }

    public static let defaultAPIURL = URL(string: "http://127.0.0.1:9888/")!

    public let apiURL: URL
    public let generatedAudioDirectory: URL
    public let audioFormat: AudioFormat
    public let maxTextLength: Int
    public let cacheLimit: Int
    public let maxCacheMissesPerMinute: Int
    public let requestTimeout: TimeInterval

    public init(
        apiURL: URL,
        generatedAudioDirectory: URL = Self.defaultGeneratedAudioDirectory(),
        audioFormat: AudioFormat = .wav,
        maxTextLength: Int = 300,
        cacheLimit: Int = 64,
        maxCacheMissesPerMinute: Int = 20,
        requestTimeout: TimeInterval = 60
    ) {
        self.apiURL = apiURL
        self.generatedAudioDirectory = generatedAudioDirectory
        self.audioFormat = audioFormat
        self.maxTextLength = maxTextLength
        self.cacheLimit = cacheLimit
        self.maxCacheMissesPerMinute = maxCacheMissesPerMinute
        self.requestTimeout = requestTimeout
    }

    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LocalTTSConfiguration {
        let rawURL = environment["LOCAL_TTS_API_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiURL: URL
        if let rawURL, !rawURL.isEmpty {
            guard let parsedURL = URL(string: rawURL) else {
                throw LocalTTSError.invalidAPIURL(rawURL)
            }
            apiURL = parsedURL
        } else {
            apiURL = defaultAPIURL
        }

        try validateLocalURL(apiURL)

        let generatedAudioDirectory = environment["LOCAL_TTS_OUTPUT_DIR"]
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            ?? defaultGeneratedAudioDirectory()

        let audioFormat = try loadAudioFormat(environment: environment)

        return LocalTTSConfiguration(
            apiURL: apiURL,
            generatedAudioDirectory: generatedAudioDirectory,
            audioFormat: audioFormat
        )
    }

    public static func defaultGeneratedAudioDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport
            .appendingPathComponent("local.vtubermeet.app", isDirectory: true)
            .appendingPathComponent("outputs", isDirectory: true)
            .appendingPathComponent("tts_generated", isDirectory: true)
    }

    private static func loadAudioFormat(environment: [String: String]) throws -> AudioFormat {
        let rawFormat = environment["LOCAL_TTS_AUDIO_FORMAT"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let rawFormat, !rawFormat.isEmpty else { return .wav }
        guard let format = AudioFormat(rawValue: rawFormat) else {
            throw LocalTTSError.unsupportedAudioFormat(rawFormat)
        }
        return format
    }

    private static func validateLocalURL(_ url: URL) throws {
        guard url.scheme == "http" else {
            throw LocalTTSError.invalidAPIURL(url.absoluteString)
        }

        let allowedHosts = ["127.0.0.1", "localhost", "::1"]
        guard let host = url.host, allowedHosts.contains(host) else {
            throw LocalTTSError.nonLocalAPIURL(url.absoluteString)
        }
    }
}

public enum LocalTTSError: Error, Equatable, LocalizedError, Sendable {
    case emptyText
    case textTooLong(maximum: Int)
    case invalidAPIURL(String)
    case nonLocalAPIURL(String)
    case rateLimited(retryAfterSeconds: Int)
    case upstreamUnavailable(URL)
    case upstreamHTTPStatus(Int)
    case invalidResponse
    case emptyAudio
    case cacheUnavailable(String)
    case unsupportedAudioFormat(String)

    public var errorDescription: String? {
        switch self {
        case .emptyText:
            "TTS text must not be empty."
        case let .textTooLong(maximum):
            "TTS text must be \(maximum) characters or fewer."
        case let .invalidAPIURL(rawURL):
            "LOCAL_TTS_API_URL is invalid: \(rawURL)"
        case let .nonLocalAPIURL(rawURL):
            "LOCAL_TTS_API_URL must point to localhost only, not \(rawURL)."
        case let .rateLimited(retryAfterSeconds):
            "Too many uncached TTS requests. Try again in \(retryAfterSeconds) seconds."
        case let .upstreamUnavailable(url):
            "Local TTS server is not reachable at \(url.absoluteString). Start the bundled start_local_tts_api.sh helper with a private local TTS config."
        case let .upstreamHTTPStatus(statusCode):
            "Local TTS server returned HTTP \(statusCode)."
        case .invalidResponse:
            "Local TTS server returned an invalid response."
        case .emptyAudio:
            "Local TTS server returned empty audio."
        case let .cacheUnavailable(reason):
            "Local TTS cache is unavailable: \(reason)"
        case let .unsupportedAudioFormat(format):
            "Unsupported Local TTS audio format: \(format). Use wav or mp3."
        }
    }
}

public struct LocalTTSAudio: Sendable {
    public let data: Data
    public let contentType: String
    public let fileURL: URL
    public let cacheHit: Bool
}

public actor LocalTTSService {
    private let configuration: LocalTTSConfiguration
    private var cache: [String: LocalTTSAudio] = [:]
    private var cacheOrder: [String] = []
    private var cacheMissTimestamps: [Date] = []

    public init(configuration: LocalTTSConfiguration) {
        self.configuration = configuration
    }

    public func synthesize(text rawText: String) async throws -> LocalTTSAudio {
        let text = try Self.normalizedText(rawText, maximumLength: configuration.maxTextLength)

        if let cachedAudio = cache[text] {
            return cachedAudio
        }

        if let diskCachedAudio = try loadFromDiskCache(for: text) {
            storeInMemory(diskCachedAudio, for: text)
            return diskCachedAudio
        }

        try enforceRateLimit(now: Date())
        let audioData = try await requestAudio(for: text)
        let audio = try storeOnDisk(audioData, for: text, cacheHit: false)
        storeInMemory(audio, for: text)
        return audio
    }

    public static func normalizedText(_ rawText: String, maximumLength: Int) throws -> String {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw LocalTTSError.emptyText
        }
        guard text.count <= maximumLength else {
            throw LocalTTSError.textTooLong(maximum: maximumLength)
        }
        return text
    }

    private func enforceRateLimit(now: Date) throws {
        let windowStart = now.addingTimeInterval(-60)
        cacheMissTimestamps.removeAll { $0 < windowStart }

        guard cacheMissTimestamps.count < configuration.maxCacheMissesPerMinute else {
            let oldest = cacheMissTimestamps.first ?? now
            let retryAfter = max(1, Int(ceil(60 - now.timeIntervalSince(oldest))))
            throw LocalTTSError.rateLimited(retryAfterSeconds: retryAfter)
        }

        cacheMissTimestamps.append(now)
    }

    private func requestAudio(for text: String) async throws -> Data {
        var request = URLRequest(url: configuration.apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.audioFormat.contentType, forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(LocalTTSUpstreamRequest(text: text))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LocalTTSError.upstreamUnavailable(configuration.apiURL)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalTTSError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LocalTTSError.upstreamHTTPStatus(httpResponse.statusCode)
        }
        guard !data.isEmpty else {
            throw LocalTTSError.emptyAudio
        }

        return data
    }

    private func loadFromDiskCache(for text: String) throws -> LocalTTSAudio? {
        let fileURL = cacheFileURL(for: text)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            return LocalTTSAudio(
                data: try Data(contentsOf: fileURL),
                contentType: configuration.audioFormat.contentType,
                fileURL: fileURL,
                cacheHit: true
            )
        } catch {
            throw LocalTTSError.cacheUnavailable(error.localizedDescription)
        }
    }

    private func storeOnDisk(_ audio: Data, for text: String, cacheHit: Bool) throws -> LocalTTSAudio {
        let fileURL = cacheFileURL(for: text)
        do {
            try FileManager.default.createDirectory(
                at: configuration.generatedAudioDirectory,
                withIntermediateDirectories: true
            )
            try audio.write(to: fileURL, options: .atomic)
        } catch {
            throw LocalTTSError.cacheUnavailable(error.localizedDescription)
        }

        return LocalTTSAudio(
            data: audio,
            contentType: configuration.audioFormat.contentType,
            fileURL: fileURL,
            cacheHit: cacheHit
        )
    }

    private func cacheFileURL(for text: String) -> URL {
        let key = [
            "local-tts-v1",
            configuration.apiURL.absoluteString,
            configuration.audioFormat.rawValue,
            text
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return configuration.generatedAudioDirectory.appendingPathComponent("\(digest).\(configuration.audioFormat.rawValue)")
    }

    private func storeInMemory(_ audio: LocalTTSAudio, for text: String) {
        if cache[text] == nil {
            cacheOrder.append(text)
        }
        cache[text] = audio

        while cacheOrder.count > configuration.cacheLimit {
            let evictedKey = cacheOrder.removeFirst()
            cache.removeValue(forKey: evictedKey)
        }
    }
}

private struct LocalTTSUpstreamRequest: Encodable {
    let text: String
    let text_language = "ko"
    let cut_punc = ".?!。？！"
    let top_k = 15
    let top_p = 1.0
    let temperature = 1.0
    let speed = 1.0
    let sample_steps = 32
    let if_sr = false
}
