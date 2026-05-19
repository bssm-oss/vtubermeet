import Foundation

public enum CompanionMood: String, Codable, CaseIterable, Sendable {
    case calm
    case happy
    case curious
    case angry
    case sad
    case surprised
    case embarrassed
}

public enum CompanionMotion: String, Codable, Sendable {
    case idle
    case bounce
    case tilt
    case shake
    case nod
    case leanIn
    case recoil
}

public struct ChatResponse: Equatable, Sendable {
    public let id: String
    public let text: String
    public let affect: CompanionAffect
    public let modelName: String?

    public var mood: CompanionMood { affect.mood }
    public var motion: CompanionMotion { affect.motion }

    public init(id: String, text: String, mood: CompanionMood, motion: CompanionMotion, modelName: String? = nil) {
        self.init(
            id: id,
            text: text,
            affect: CompanionAffect(
                mood: mood,
                expression: AffectEngine.expression(for: mood),
                motion: motion,
                intensity: 0.6,
                duration: 2.0,
                confidence: 0.7,
                source: .fallback
            ),
            modelName: modelName
        )
    }

    public init(id: String, text: String, affect: CompanionAffect, modelName: String? = nil) {
        self.id = id
        self.text = text
        self.affect = affect
        self.modelName = modelName
    }
}

public enum ChatError: Error, Equatable, LocalizedError {
    case emptyMessage
    case messageTooLong(maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyMessage:
            "메시지를 입력해 주세요."
        case let .messageTooLong(maximum):
            "메시지는 \(maximum)자 이하로 입력해 주세요."
        }
    }
}

public struct ChatService: Sendable {
    public static let maximumMessageLength = 1_200
    private let llmClient: OllamaClient

    public init(llmClient: OllamaClient = OllamaClient()) {
        self.llmClient = llmClient
    }

    public func availableLocalModel() async throws -> String {
        try await llmClient.selectModel()
    }

    public func respond(to rawText: String, characterName: String) async throws -> ChatResponse {
        let text = try Self.validate(rawText)
        let model = try await llmClient.selectModel()
        let generatedText: String

        do {
            generatedText = try await llmClient.generate(message: text, characterName: characterName, model: model)
        } catch LocalLLMError.emptyResponse {
            let inputAffect = AffectEngine.infer(from: text, source: .fallback)
            generatedText = buildFallbackResponse(for: text, mood: inputAffect.mood)
        }

        let affect = AffectEngine.evaluate(userText: text, assistantText: generatedText)

        return ChatResponse(
            id: "assistant-\(Int(Date().timeIntervalSince1970 * 1000))",
            text: generatedText,
            affect: affect,
            modelName: model
        )
    }

    public func respondLocallyForChecks(to rawText: String) throws -> ChatResponse {
        let text = try Self.validate(rawText)
        let affect = AffectEngine.infer(from: text, source: .fallback)

        return ChatResponse(
            id: "assistant-\(Int(Date().timeIntervalSince1970 * 1000))",
            text: buildFallbackResponse(for: text, mood: affect.mood),
            affect: affect,
            modelName: nil
        )
    }

    public static func validate(_ rawText: String) throws -> String {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw ChatError.emptyMessage
        }

        guard text.count <= Self.maximumMessageLength else {
            throw ChatError.messageTooLong(maximum: Self.maximumMessageLength)
        }

        return text
    }

    private func buildFallbackResponse(for text: String, mood: CompanionMood) -> String {
        let body = switch mood {
        case .calm:
            "차분하게 듣고 있어요."
        case .happy:
            "밝은 분위기라서 저도 표정이 확 살아났어요."
        case .curious:
            "궁금한 이야기라 고개를 살짝 기울여서 생각해볼게요."
        case .angry:
            "조금 화난 분위기라 표정도 단단해졌어요. 그래도 차분히 같이 풀어볼게요."
        case .sad:
            "속상한 이야기라 천천히 고개를 끄덕이면서 들어볼게요."
        case .surprised:
            "깜짝 놀랐어요. 눈이 동그래진 채로 다시 확인해볼게요."
        case .embarrassed:
            "살짝 부끄럽지만 웃으면서 받아볼게요."
        }

        return "응, ‘\(text)’라고 했죠. \(body) 다음 말도 편하게 이어주세요."
    }
}

public struct OllamaClient: Sendable {
    public static let defaultBaseURL = URL(string: "http://127.0.0.1:11434")!
    public static let preferredGemmaModels = [
        "gemma4:e4b",
        "gemma4:latest",
        "gemma4:e2b",
        "gemma4",
        "gemma3:4b",
        "gemma3:latest",
        "gemma3",
        "gemma3n:latest",
        "gemma3n",
        "gemma2:latest",
        "gemma2",
        "gemma:latest",
        "gemma"
    ]

    private let baseURL: URL

    public init(baseURL: URL = Self.defaultBaseURL) {
        self.baseURL = baseURL
    }

    public func availableModels() async throws -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, response) = try await URLSession.shared.data(from: url)
        try Self.validateHTTPResponse(response)

        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.models.map(\.name)
    }

    public func selectModel() async throws -> String {
        try await Self.selectPreferredModel(from: availableModels())
    }

    public static func selectPreferredModel(from models: [String], preferred: [String] = preferredGemmaModels) throws -> String {
        guard !models.isEmpty else { throw LocalLLMError.noModels }

        for candidate in preferred {
            if models.contains(candidate) { return candidate }
            if !candidate.contains(":"), let tagged = models.first(where: { $0.hasPrefix("\(candidate):") }) {
                return tagged
            }
        }

        if let gemma = models.first(where: { $0.localizedCaseInsensitiveContains("gemma") }) {
            return gemma
        }

        throw LocalLLMError.noGemmaModel(available: models)
    }

    public func generate(message: String, characterName: String, model: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: Self.systemPrompt(characterName: characterName)),
                ChatMessage(role: "user", content: message)
            ],
            stream: false,
            options: ChatOptions(temperature: 0.82, numPredict: 512)
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response)
        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)

        if let error = decoded.error, !error.isEmpty {
            throw LocalLLMError.runtimeError(error)
        }

        let text = decoded.message.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !text.isEmpty else { throw LocalLLMError.emptyResponse(model: model) }
        return text
    }

    private static func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LocalLLMError.httpStatus(httpResponse.statusCode)
        }
    }

    private static func systemPrompt(characterName: String) -> String {
        if let privatePrompt = privateSystemPrompt() {
            return privatePrompt.replacingOccurrences(of: "{characterName}", with: characterName)
        }

        return "넌 \(characterName)야. 반말로, 1~2문장만, 감정에 맞춰 자연스럽게 대화해. AI나 프롬프트 언급 금지."
    }

    private static func privateSystemPrompt() -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let inlinePrompt = environment["LOCAL_COMPANION_SYSTEM_PROMPT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !inlinePrompt.isEmpty {
            return inlinePrompt
        }

        let fileCandidates = [
            environment["LOCAL_COMPANION_SYSTEM_PROMPT_FILE"],
            defaultPrivatePromptFile()?.path
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

        for path in fileCandidates where !path.isEmpty {
            let expandedPath = (path as NSString).expandingTildeInPath
            if let prompt = try? String(contentsOfFile: expandedPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !prompt.isEmpty {
                return prompt
            }
        }

        return nil
    }

    private static func defaultPrivatePromptFile() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("local.vtubermeet.app", isDirectory: true)
            .appendingPathComponent("private_system_prompt.txt", isDirectory: false)
    }
}

public enum LocalLLMError: Error, LocalizedError, Sendable {
    case noModels
    case noGemmaModel(available: [String])
    case httpStatus(Int)
    case runtimeError(String)
    case emptyResponse(model: String)

    public var errorDescription: String? {
        switch self {
        case .noModels:
            "로컬 Ollama에 설치된 모델이 없습니다. 터미널에서 `ollama pull gemma4:e4b` 후 다시 시도해 주세요."
        case let .noGemmaModel(available):
            "Gemma 계열 로컬 모델을 찾지 못했습니다. 현재 모델: \(available.joined(separator: ", ")). `ollama pull gemma4:e4b`를 실행해 주세요."
        case let .httpStatus(status):
            "로컬 Ollama가 HTTP \(status)를 반환했습니다. Ollama 상태를 확인해 주세요."
        case let .runtimeError(message):
            "로컬 LLM 오류: \(message)"
        case let .emptyResponse(model):
            "\(model)이 빈 답변을 반환했습니다. 다시 시도해 주세요."
        }
    }
}

private struct TagsResponse: Decodable {
    let models: [Model]

    struct Model: Decodable {
        let name: String
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let options: ChatOptions
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatOptions: Encodable {
    let temperature: Double
    let numPredict: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case numPredict = "num_predict"
    }
}

private struct OllamaChatResponse: Decodable {
    let message: OllamaChatMessage
    let error: String?
}

private struct OllamaChatMessage: Decodable {
    let role: String
    let content: String
}
