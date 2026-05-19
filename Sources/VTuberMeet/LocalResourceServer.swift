import Darwin
import Foundation

final class LocalResourceServer {
    private let rootURL: URL
    private let queue = DispatchQueue(label: "app.vtubermeet.local-resource-server")
    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    private(set) var port: UInt16 = 0

    init(rootURL: URL) {
        self.rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
    }

    deinit {
        stop()
    }

    func start() throws {
        guard serverSocket == -1 else { return }

        let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        let flags = fcntl(socketFD, F_GETFL, 0)
        _ = fcntl(socketFD, F_SETFL, flags | O_NONBLOCK)

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(0).bigEndian
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

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.getsockname(socketFD, sockaddrPointer, &boundLength)
            }
        }

        guard nameResult == 0 else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            Darwin.close(socketFD)
            throw error
        }

        serverSocket = socketFD
        port = UInt16(bigEndian: boundAddress.sin_port)

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
        defer { Darwin.close(clientSocket) }

        let flags = fcntl(clientSocket, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(clientSocket, F_SETFL, flags & ~O_NONBLOCK)
        }

        var noSignal: Int32 = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(clientSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        guard let request = readRequest(from: clientSocket) else {
            sendResponse(status: "400 Bad Request", contentType: "text/plain; charset=utf-8", body: Data("Bad Request".utf8), to: clientSocket)
            return
        }

        guard request.method == "GET" || request.method == "HEAD" else {
            sendResponse(status: "405 Method Not Allowed", contentType: "text/plain; charset=utf-8", body: Data("Method Not Allowed".utf8), to: clientSocket, includeBody: request.method != "HEAD")
            return
        }

        guard let fileURL = fileURL(for: request.path) else {
            sendResponse(status: "403 Forbidden", contentType: "text/plain; charset=utf-8", body: Data("Forbidden".utf8), to: clientSocket, includeBody: request.method != "HEAD")
            return
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            sendResponse(status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: Data("Not Found".utf8), to: clientSocket, includeBody: request.method != "HEAD")
            return
        }

        sendResponse(status: "200 OK", contentType: contentType(for: fileURL), body: data, to: clientSocket, includeBody: request.method != "HEAD")
    }

    private func readRequest(from socket: Int32) -> HTTPRequest? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bufferCapacity = buffer.count

        while data.count < 16_384 {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.recv(socket, rawBuffer.baseAddress, bufferCapacity, 0)
            }

            guard count > 0 else { break }
            data.append(buffer, count: count)

            if data.range(of: Data("\r\n\r\n".utf8)) != nil { break }
        }

        guard let text = String(data: data, encoding: .utf8),
              let firstLine = text.components(separatedBy: "\r\n").first else {
            return nil
        }

        let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        return HTTPRequest(method: parts[0], path: parts[1])
    }

    private func fileURL(for rawPath: String) -> URL? {
        let pathWithoutQuery = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        guard let decoded = pathWithoutQuery.removingPercentEncoding else { return nil }

        var relativePath = decoded
        if relativePath == "/" { relativePath = "/Live2DViewer/index.html" }
        if relativePath.hasPrefix("/") { relativePath.removeFirst() }
        guard !relativePath.isEmpty, !relativePath.split(separator: "/").contains("..") else { return nil }

        let fileURL = rootURL.appendingPathComponent(relativePath).resolvingSymlinksInPath().standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : "\(rootURL.path)/"
        guard fileURL.path.hasPrefix(rootPath), !hasDirectoryPath(fileURL) else { return nil }
        return fileURL
    }

    private func hasDirectoryPath(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func sendResponse(status: String, contentType: String, body: Data, to socket: Int32, includeBody: Bool = true) {
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"

        var response = Data(headers.utf8)
        if includeBody { response.append(body) }
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

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "js": "application/javascript; charset=utf-8"
        case "json", "model3", "physics3", "pose3", "cdi3", "exp3", "motion3": "application/json; charset=utf-8"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "moc3": "application/octet-stream"
        default: "application/octet-stream"
        }
    }

    private struct HTTPRequest {
        let method: String
        let path: String
    }
}
