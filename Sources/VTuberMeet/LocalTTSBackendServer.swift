import Darwin
import Foundation
import VTuberMeetCore

final class LocalTTSBackendServer: @unchecked Sendable {
    private static let maximumRequestBytes = 16_384

    private let service: LocalTTSService
    private let requestedPort: UInt16
    private let queue = DispatchQueue(label: "app.vtubermeet.local-tts-backend")
    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    private(set) var port: UInt16 = 0

    init(service: LocalTTSService, port: UInt16? = nil) {
        self.service = service
        self.requestedPort = port ?? LocalTTSBackendServer.configuredPort()
    }

    deinit {
        stop()
    }

    static func configuredPort(environment: [String: String] = ProcessInfo.processInfo.environment) -> UInt16 {
        guard let rawPort = environment["LOCAL_TTS_BACKEND_PORT"],
              let parsedPort = UInt16(rawPort),
              parsedPort > 0 else {
            return 9890
        }
        return parsedPort
    }

    func start() throws {
        guard serverSocket == -1 else { return }

        let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var noSignal: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

        let flags = fcntl(socketFD, F_GETFL, 0)
        _ = fcntl(socketFD, F_SETFL, flags | O_NONBLOCK)

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = requestedPort.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            Darwin.close(socketFD)
            throw error
        }

        guard Darwin.listen(socketFD, SOMAXCONN) == 0 else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            Darwin.close(socketFD)
            throw error
        }

        serverSocket = socketFD
        port = requestedPort

        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptAvailableConnections()
        }
        source.setCancelHandler {
            Darwin.close(socketFD)
        }
        acceptSource = source
        source.resume()
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        serverSocket = -1
        port = 0
    }

    func url(path: String) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        return components.url!
    }

    private func acceptAvailableConnections() {
        while true {
            let clientSocket = Darwin.accept(serverSocket, nil, nil)
            if clientSocket < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN { return }
                return
            }

            handleConnection(clientSocket)
        }
    }

    private func handleConnection(_ clientSocket: Int32) {
        let flags = fcntl(clientSocket, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(clientSocket, F_SETFL, flags & ~O_NONBLOCK)
        }

        var noSignal: Int32 = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(clientSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        guard let request = readRequest(from: clientSocket) else {
            sendJSONError(status: "400 Bad Request", message: "Malformed HTTP request.", to: clientSocket)
            Darwin.close(clientSocket)
            return
        }

        let path = normalizedPath(request.path)
        if request.method == "GET", path == "/health" {
            sendResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: Data(#"{"ok":true}"#.utf8), to: clientSocket)
            Darwin.close(clientSocket)
            return
        }

        guard request.method == "POST", path == "/api/tts" else {
            sendJSONError(status: "404 Not Found", message: "Use POST /api/tts.", to: clientSocket)
            Darwin.close(clientSocket)
            return
        }

        let payload: TTSRequestPayload
        do {
            payload = try JSONDecoder().decode(TTSRequestPayload.self, from: request.body)
        } catch {
            sendJSONError(status: "400 Bad Request", message: "Request body must be JSON with a text field.", to: clientSocket)
            Darwin.close(clientSocket)
            return
        }

        Task { [service] in
            do {
                let audio = try await service.synthesize(text: payload.text)
                sendResponse(status: "200 OK", contentType: audio.contentType, body: audio.data, to: clientSocket)
            } catch {
                sendError(error, to: clientSocket)
            }
            Darwin.close(clientSocket)
        }
    }

    private func readRequest(from socket: Int32) -> HTTPRequest? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bufferCapacity = buffer.count

        while data.count < Self.maximumRequestBytes {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.recv(socket, rawBuffer.baseAddress, bufferCapacity, 0)
            }

            guard count > 0 else { break }
            data.append(buffer, count: count)

            guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
                continue
            }

            let headerData = data[..<headerRange.lowerBound]
            guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
            let lines = headerText.components(separatedBy: "\r\n")
            guard let firstLine = lines.first else { return nil }
            let firstLineParts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
            guard firstLineParts.count >= 2 else { return nil }

            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
            }

            let bodyStart = headerRange.upperBound
            let contentLength = Int(headers["content-length"] ?? "0") ?? 0
            guard contentLength <= Self.maximumRequestBytes else { return nil }

            while data.count - bodyStart < contentLength, data.count < Self.maximumRequestBytes {
                let nextCount = buffer.withUnsafeMutableBytes { rawBuffer in
                    Darwin.recv(socket, rawBuffer.baseAddress, bufferCapacity, 0)
                }
                guard nextCount > 0 else { break }
                data.append(buffer, count: nextCount)
            }

            guard data.count - bodyStart >= contentLength else { return nil }
            let body = Data(data[bodyStart..<(bodyStart + contentLength)])
            return HTTPRequest(method: firstLineParts[0], path: firstLineParts[1], headers: headers, body: body)
        }

        return nil
    }

    private func normalizedPath(_ rawPath: String) -> String {
        rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
    }

    private func sendError(_ error: Error, to socket: Int32) {
        if let ttsError = error as? LocalTTSError {
            switch ttsError {
            case .emptyText, .textTooLong, .invalidAPIURL, .nonLocalAPIURL, .unsupportedAudioFormat:
                sendJSONError(status: "400 Bad Request", message: ttsError.localizedDescription, to: socket)
            case .rateLimited:
                sendJSONError(status: "429 Too Many Requests", message: ttsError.localizedDescription, to: socket)
            case .upstreamUnavailable:
                sendJSONError(status: "503 Service Unavailable", message: ttsError.localizedDescription, to: socket)
            case .upstreamHTTPStatus, .invalidResponse, .emptyAudio, .cacheUnavailable:
                sendJSONError(status: "502 Bad Gateway", message: ttsError.localizedDescription, to: socket)
            }
            return
        }

        sendJSONError(status: "500 Internal Server Error", message: error.localizedDescription, to: socket)
    }

    private func sendJSONError(status: String, message: String, to socket: Int32) {
        let payload = ErrorPayload(error: message)
        let body = (try? JSONEncoder().encode(payload)) ?? Data(#"{"error":"unknown"}"#.utf8)
        sendResponse(status: status, contentType: "application/json; charset=utf-8", body: body, to: socket)
    }

    private func sendResponse(status: String, contentType: String, body: Data, to socket: Int32) {
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"

        var response = Data(headers.utf8)
        response.append(body)
        sendAll(response, to: socket)
    }

    private func sendAll(_ data: Data, to socket: Int32) {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let result = Darwin.send(socket, baseAddress.advanced(by: sent), data.count - sent, 0)
                guard result > 0 else { return }
                sent += result
            }
        }
    }

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private struct TTSRequestPayload: Decodable {
        let text: String
    }

    private struct ErrorPayload: Encodable {
        let error: String
    }
}
