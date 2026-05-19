import Foundation

@MainActor
final class LocalTTSUpstreamLauncher {
    private var process: Process?
    private var logHandle: FileHandle?
    private(set) var logURL: URL?

    deinit {
        if let process, process.isRunning {
            process.terminate()
        }
        try? logHandle?.close()
    }

    func startIfNeeded(apiURL: URL, scriptURL: URL) async -> LocalTTSUpstreamLaunchStatus {
        if await isReachable(apiURL) {
            return .running
        }

        if let process, process.isRunning {
            if await waitUntilReachable(apiURL, timeoutSeconds: 20) {
                return .running
            }
            return .starting(logURL: logURL)
        }

        do {
            try startProcess(apiURL: apiURL, scriptURL: scriptURL)
        } catch {
            return .failed(message: error.localizedDescription, logURL: logURL)
        }

        if await waitUntilReachable(apiURL, timeoutSeconds: 75) {
            return .started(logURL: logURL)
        }

        guard process?.isRunning == true else {
            return .failed(message: "Local TTS process exited before it became ready.", logURL: logURL)
        }

        return .starting(logURL: logURL)
    }

    func isReachable(_ apiURL: URL) async -> Bool {
        var request = URLRequest(url: readinessURL(for: apiURL))
        request.httpMethod = "GET"
        request.timeoutInterval = 2

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private func readinessURL(for apiURL: URL) -> URL {
        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
        components?.path = "/docs"
        components?.query = nil
        return components?.url ?? apiURL
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        try? logHandle?.close()
        logHandle = nil
    }

    private func startProcess(apiURL: URL, scriptURL: URL) throws {
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let logURL = try Self.makeLogURL()
        try? logHandle?.close()
        logHandle = nil
        try Data().write(to: logURL)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", scriptURL.path]
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        process.environment = makeEnvironment(apiURL: apiURL)
        process.standardOutput = handle
        process.standardError = handle

        try process.run()
        self.process = process
        self.logHandle = handle
        self.logURL = logURL
    }

    private func makeEnvironment(apiURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HOST"] = apiURL.host ?? "127.0.0.1"
        environment["PORT"] = String(apiURL.port ?? 9888)
        environment["DEVICE"] = environment["DEVICE"] ?? "cpu"
        environment["MEDIA_TYPE"] = environment["MEDIA_TYPE"] ?? environment["LOCAL_TTS_AUDIO_FORMAT"] ?? "wav"
        environment["PATH"] = Self.launchPath(existingPath: environment["PATH"])
        return environment
    }

    private func waitUntilReachable(_ apiURL: URL, timeoutSeconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await isReachable(apiURL) {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    private static func makeLogURL() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = appSupport
            .appendingPathComponent("local.vtubermeet.app", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("local-tts.log")
    }

    private static func launchPath(existingPath: String?) -> String {
        let candidates = [
            existingPath,
            "/opt/homebrew/Caskroom/miniconda/base/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            NSHomeDirectory() + "/miniconda3/bin",
            NSHomeDirectory() + "/anaconda3/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        return candidates.compactMap { $0 }.joined(separator: ":")
    }
}

enum LocalTTSUpstreamLaunchStatus: Equatable {
    case running
    case started(logURL: URL?)
    case starting(logURL: URL?)
    case failed(message: String, logURL: URL?)

    var userMessage: String {
        switch self {
        case .running:
            return "로컬 TTS 연결됨"
        case .started:
            return "로컬 TTS를 자동으로 시작했습니다"
        case .starting:
            return "로컬 TTS 시작 중입니다. 첫 실행은 시간이 걸릴 수 있어요"
        case let .failed(message, logURL):
            if let logURL {
                return "로컬 TTS 시작 실패: \(message) · 로그: \(logURL.path)"
            }
            return "로컬 TTS 시작 실패: \(message)"
        }
    }

    var isUsable: Bool {
        switch self {
        case .running, .started:
            return true
        case .starting, .failed:
            return false
        }
    }
}
