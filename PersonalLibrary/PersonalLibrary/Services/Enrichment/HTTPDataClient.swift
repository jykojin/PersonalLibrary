import Foundation
import Network
import Security

protocol HTTPDataClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

enum HTTPDataClientError: Error, Equatable {
    case responseTooLarge
}

struct BoundedHTTPResponseBuffer {
    private(set) var data = Data()
    let maximumResponseBytes: Int

    init(maximumResponseBytes: Int) {
        self.maximumResponseBytes = max(0, maximumResponseBytes)
    }

    mutating func append(_ chunk: Data) throws {
        guard chunk.count <= maximumResponseBytes - data.count else {
            throw HTTPDataClientError.responseTooLarge
        }
        data.append(chunk)
    }
}

final class URLSessionHTTPDataClient: HTTPDataClient, @unchecked Sendable {
    private let session: URLSession
    private let sessionDelegate: BoundedHTTPSessionDelegate

    init(
        configuration: URLSessionConfiguration = .default,
        maximumResponseBytes: Int = 5_000_000
    ) {
        let sessionDelegate = BoundedHTTPSessionDelegate(
            maximumResponseBytes: max(0, maximumResponseBytes),
            allowsRedirect: { original, redirected in
                Self.allowsMetadataRedirect(from: original, to: redirected)
            }
        )
        self.sessionDelegate = sessionDelegate
        session = URLSession(
            configuration: configuration,
            delegate: sessionDelegate,
            delegateQueue: nil
        )
    }

    deinit {
        session.invalidateAndCancel()
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await sessionDelegate.data(for: request, using: session)
    }

    private static func allowsMetadataRedirect(from original: URL, to redirected: URL) -> Bool {
        let originalPort = original.port ?? 443
        let redirectedPort = redirected.port ?? 443
        return original.scheme?.lowercased() == "https"
            && redirected.scheme?.lowercased() == "https"
            && original.host?.lowercased() == redirected.host?.lowercased()
            && originalPort == redirectedPort
            && redirected.user == nil
            && redirected.password == nil
    }
}

private final class BoundedHTTPSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct TransferState {
        var buffer: BoundedHTTPResponseBuffer
        var response: URLResponse?
        let continuation: CheckedContinuation<(Data, URLResponse), Error>
    }

    private let maximumResponseBytes: Int
    private let allowsRedirect: @Sendable (URL, URL) -> Bool
    private let lock = NSLock()
    private var transfers: [Int: TransferState] = [:]

    init(
        maximumResponseBytes: Int,
        allowsRedirect: @escaping @Sendable (URL, URL) -> Bool
    ) {
        self.maximumResponseBytes = maximumResponseBytes
        self.allowsRedirect = allowsRedirect
    }

    func data(for request: URLRequest, using session: URLSession) async throws -> (Data, URLResponse) {
        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let shouldCancel = lock.withLock {
                    guard !Task.isCancelled else { return true }
                    transfers[task.taskIdentifier] = TransferState(
                        buffer: BoundedHTTPResponseBuffer(
                            maximumResponseBytes: maximumResponseBytes
                        ),
                        continuation: continuation
                    )
                    return false
                }
                if shouldCancel {
                    continuation.resume(throwing: CancellationError())
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            self.finish(taskIdentifier: task.taskIdentifier, throwing: CancellationError())
            task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let original = task.originalRequest?.url,
              let redirected = request.url,
              allowsRedirect(original, redirected) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard response.expectedContentLength <= Int64(maximumResponseBytes) else {
            finish(taskIdentifier: dataTask.taskIdentifier, throwing: HTTPDataClientError.responseTooLarge)
            completionHandler(.cancel)
            dataTask.cancel()
            return
        }

        let isActive = lock.withLock {
            guard var transfer = transfers[dataTask.taskIdentifier] else { return false }
            transfer.response = response
            transfers[dataTask.taskIdentifier] = transfer
            return true
        }
        completionHandler(isActive ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let continuation: CheckedContinuation<(Data, URLResponse), Error>? = lock.withLock {
            guard var transfer = transfers[dataTask.taskIdentifier] else { return nil }
            do {
                try transfer.buffer.append(data)
            } catch {
                return transfers.removeValue(forKey: dataTask.taskIdentifier)?.continuation
            }
            transfers[dataTask.taskIdentifier] = transfer
            return nil
        }

        if let continuation {
            dataTask.cancel()
            continuation.resume(throwing: HTTPDataClientError.responseTooLarge)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let transfer = lock.withLock {
            transfers.removeValue(forKey: task.taskIdentifier)
        }
        guard let transfer else { return }

        if let error {
            transfer.continuation.resume(throwing: error)
        } else if let response = transfer.response {
            transfer.continuation.resume(returning: (transfer.buffer.data, response))
        } else {
            transfer.continuation.resume(throwing: URLError(.badServerResponse))
        }
    }

    private func finish(taskIdentifier: Int, throwing error: Error) {
        let continuation = lock.withLock {
            transfers.removeValue(forKey: taskIdentifier)?.continuation
        }
        continuation?.resume(throwing: error)
    }
}

protocol AIPinnedHTTPTransport: Sendable {
    func data(
        for request: URLRequest,
        connectingTo address: String,
        serverName: String,
        port: UInt16,
        maximumResponseBytes: Int
    ) async throws -> (Data, HTTPURLResponse)
}

protocol AIPinnedConnectionFactory: Sendable {
    func exchange(
        requestData: Data,
        connectingTo address: String,
        serverName: String,
        port: UInt16,
        timeout: TimeInterval,
        maximumWireBytes: Int
    ) async throws -> Data
}

struct NetworkPinnedHTTPTransport: AIPinnedHTTPTransport {
    private static let maximumHeaderBytes = 65_536
    private let connectionFactory: any AIPinnedConnectionFactory

    init(connectionFactory: any AIPinnedConnectionFactory = NetworkAIPinnedConnectionFactory()) {
        self.connectionFactory = connectionFactory
    }

    func data(
        for request: URLRequest,
        connectingTo address: String,
        serverName: String,
        port: UInt16,
        maximumResponseBytes: Int
    ) async throws -> (Data, HTTPURLResponse) {
        let requestData = try Self.encode(request, serverName: serverName, port: port)
        let maximumWireBytes = maximumResponseBytes.addingReportingOverflow(
            Self.maximumHeaderBytes
        )
        let rawResponse = try await connectionFactory.exchange(
            requestData: requestData,
            connectingTo: address,
            serverName: serverName,
            port: port,
            timeout: request.timeoutInterval,
            maximumWireBytes: maximumWireBytes.overflow ? Int.max : maximumWireBytes.partialValue
        )
        return try Self.decode(
            rawResponse,
            requestURL: request.url,
            requestMethod: request.httpMethod,
            maximumResponseBytes: maximumResponseBytes
        )
    }

    private static func encode(
        _ request: URLRequest,
        serverName: String,
        port: UInt16
    ) throws -> Data {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              request.httpBodyStream == nil else {
            throw URLError(.badURL)
        }
        let method = (request.httpMethod ?? "GET").uppercased()
        guard method == "GET" || method == "POST" else {
            throw URLError(.unsupportedURL)
        }

        var target = components.percentEncodedPath
        if target.isEmpty { target = "/" }
        if let query = components.percentEncodedQuery, !query.isEmpty {
            target += "?\(query)"
        }
        guard !target.contains("\r"), !target.contains("\n") else {
            throw URLError(.badURL)
        }

        let hostForHeader = serverName.contains(":") ? "[\(serverName)]" : serverName
        let hostHeader = port == 443 ? hostForHeader : "\(hostForHeader):\(port)"
        var headers = request.allHTTPHeaderFields ?? [:]
        for name in headers.keys where [
            "host", "content-length", "connection", "accept-encoding"
        ].contains(name.lowercased()) {
            headers.removeValue(forKey: name)
        }
        headers["Host"] = hostHeader
        headers["Connection"] = "close"
        headers["Accept-Encoding"] = "identity"
        let body = request.httpBody ?? Data()
        if !body.isEmpty || method == "POST" {
            headers["Content-Length"] = String(body.count)
        }

        var wire = "\(method) \(target) HTTP/1.1\r\n"
        for (name, value) in headers.sorted(by: {
            $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }) {
            guard !name.contains("\r"), !name.contains("\n"),
                  !value.contains("\r"), !value.contains("\n") else {
                throw URLError(.badURL)
            }
            wire += "\(name): \(value)\r\n"
        }
        wire += "\r\n"
        var data = Data(wire.utf8)
        data.append(body)
        return data
    }

    private static func decode(
        _ rawResponse: Data,
        requestURL: URL?,
        requestMethod: String?,
        maximumResponseBytes: Int
    ) throws -> (Data, HTTPURLResponse) {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = rawResponse.range(of: separator),
              headerRange.lowerBound <= maximumHeaderBytes,
              let headerText = String(
                data: rawResponse[..<headerRange.lowerBound],
                encoding: .isoLatin1
              ) else {
            throw URLError(.badServerResponse)
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { throw URLError(.badServerResponse) }
        let statusParts = statusLine.split(separator: " ", maxSplits: 2)
        guard statusParts.count >= 2,
              statusParts[0].hasPrefix("HTTP/1."),
              let statusCode = Int(statusParts[1]),
              let requestURL else {
            throw URLError(.badServerResponse)
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else {
                throw URLError(.badServerResponse)
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw URLError(.badServerResponse) }
            if let existingKey = headers.keys.first(where: {
                $0.caseInsensitiveCompare(name) == .orderedSame
            }) {
                headers[existingKey] = "\(headers[existingKey]!), \(value)"
            } else {
                headers[name] = value
            }
        }

        let bodyStart = headerRange.upperBound
        let encodedBody = Data(rawResponse[bodyStart...])
        let headerValue: (String) -> String? = { requestedName in
            headers.first(where: {
                $0.key.caseInsensitiveCompare(requestedName) == .orderedSame
            })?.value
        }
        let hasNoBody = requestMethod?.uppercased() == "HEAD"
            || statusCode == 204
            || statusCode == 304
            || (100..<200).contains(statusCode)
        let body: Data
        if hasNoBody {
            body = Data()
        } else if let transferEncoding = headerValue("Transfer-Encoding") {
            guard transferEncoding
                .split(separator: ",")
                .contains(where: { $0.trimmingCharacters(in: .whitespaces)
                    .caseInsensitiveCompare("chunked") == .orderedSame }) else {
                throw URLError(.badServerResponse)
            }
            body = try decodeChunked(encodedBody, maximumResponseBytes: maximumResponseBytes)
        } else if let contentLengthValue = headerValue("Content-Length") {
            guard let contentLength = Int(contentLengthValue), contentLength >= 0 else {
                throw URLError(.badServerResponse)
            }
            guard contentLength <= maximumResponseBytes else {
                throw HTTPDataClientError.responseTooLarge
            }
            guard encodedBody.count >= contentLength else {
                throw URLError(.badServerResponse)
            }
            body = Data(encodedBody.prefix(contentLength))
        } else {
            guard encodedBody.count <= maximumResponseBytes else {
                throw HTTPDataClientError.responseTooLarge
            }
            body = encodedBody
        }

        guard body.count <= maximumResponseBytes else {
            throw HTTPDataClientError.responseTooLarge
        }
        guard let response = HTTPURLResponse(
            url: requestURL,
            statusCode: statusCode,
            httpVersion: String(statusParts[0]),
            headerFields: headers
        ) else {
            throw URLError(.badServerResponse)
        }
        return (body, response)
    }

    private static func decodeChunked(
        _ encoded: Data,
        maximumResponseBytes: Int
    ) throws -> Data {
        let delimiter = Data("\r\n".utf8)
        var cursor = encoded.startIndex
        var decoded = Data()
        while true {
            guard let lineRange = encoded.range(of: delimiter, in: cursor..<encoded.endIndex),
                  let sizeLine = String(data: encoded[cursor..<lineRange.lowerBound], encoding: .ascii),
                  let sizeText = sizeLine.split(separator: ";", maxSplits: 1).first,
                  let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16),
                  size >= 0 else {
                throw URLError(.badServerResponse)
            }
            cursor = lineRange.upperBound
            if size == 0 {
                guard encoded.distance(from: cursor, to: encoded.endIndex) >= 2 else {
                    throw URLError(.badServerResponse)
                }
                let immediateEnd = encoded.index(cursor, offsetBy: 2)
                if encoded[cursor..<immediateEnd] == delimiter {
                    return decoded
                }
                guard encoded.range(
                    of: Data("\r\n\r\n".utf8),
                    in: cursor..<encoded.endIndex
                ) != nil else {
                    throw URLError(.badServerResponse)
                }
                return decoded
            }
            guard size <= maximumResponseBytes - decoded.count,
                  encoded.distance(from: cursor, to: encoded.endIndex) >= size + 2 else {
                if size > maximumResponseBytes - decoded.count {
                    throw HTTPDataClientError.responseTooLarge
                }
                throw URLError(.badServerResponse)
            }
            let chunkEnd = encoded.index(cursor, offsetBy: size)
            decoded.append(encoded[cursor..<chunkEnd])
            let delimiterEnd = encoded.index(chunkEnd, offsetBy: 2)
            guard encoded[chunkEnd..<delimiterEnd] == delimiter else {
                throw URLError(.badServerResponse)
            }
            cursor = delimiterEnd
        }
    }
}

struct NetworkAIPinnedConnectionFactory: AIPinnedConnectionFactory {
    func exchange(
        requestData: Data,
        connectingTo address: String,
        serverName: String,
        port: UInt16,
        timeout: TimeInterval,
        maximumWireBytes: Int
    ) async throws -> Data {
        let endpointHost: NWEndpoint.Host
        if let ipv4 = IPv4Address(address) {
            endpointHost = .ipv4(ipv4)
        } else if let ipv6 = IPv6Address(address) {
            endpointHost = .ipv6(ipv6)
        } else {
            throw AIEndpointPolicyError.dnsResolutionFailed
        }

        let tls = NWProtocolTLS.Options()
        serverName.withCString {
            sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, $0)
        }
        "http/1.1".withCString {
            sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, $0)
        }
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(
            host: endpointHost,
            port: NWEndpoint.Port(rawValue: port)!,
            using: parameters
        )
        let operation = NetworkAIHTTPExchange(
            connection: connection,
            requestData: requestData,
            maximumWireBytes: maximumWireBytes
        )

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await operation.run() }
            group.addTask {
                let boundedTimeout = max(0.001, min(timeout, 3_600))
                try await Task.sleep(for: .seconds(boundedTimeout))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw URLError(.unknown)
            }
            return result
        }
    }
}

private final class NetworkAIHTTPExchange: @unchecked Sendable {
    private let connection: NWConnection
    private let requestData: Data
    private let maximumWireBytes: Int
    private let queue = DispatchQueue(label: "com.joe.PersonalLibrary.ai-pinned-http")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var responseData = Data()
    private var didSendRequest = false

    init(connection: NWConnection, requestData: Data, maximumWireBytes: Int) {
        self.connection = connection
        self.requestData = requestData
        self.maximumWireBytes = maximumWireBytes
    }

    func run() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let shouldCancel = lock.withLock {
                    guard !Task.isCancelled else { return true }
                    self.continuation = continuation
                    return false
                }
                guard !shouldCancel else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                connection.stateUpdateHandler = { [weak self] state in
                    self?.handle(state)
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            self.finish(throwing: CancellationError())
        }
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            let shouldSend = lock.withLock {
                guard !didSendRequest, continuation != nil else { return false }
                didSendRequest = true
                return true
            }
            guard shouldSend else { return }
            connection.send(
                content: requestData,
                contentContext: .defaultMessage,
                isComplete: true,
                completion: .contentProcessed {
                [weak self] error in
                if let error {
                    self?.finish(throwing: error)
                } else {
                    self?.receive()
                }
            })
        case .failed(let error):
            finish(throwing: error)
        case .cancelled:
            finish(throwing: CancellationError())
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                finish(throwing: error)
                return
            }
            if let data, !data.isEmpty {
                let didOverflow = lock.withLock {
                    guard self.continuation != nil else { return false }
                    guard self.responseData.count <= self.maximumWireBytes,
                          data.count <= self.maximumWireBytes - self.responseData.count else {
                        return true
                    }
                    self.responseData.append(data)
                    return false
                }
                if didOverflow {
                    finish(throwing: HTTPDataClientError.responseTooLarge)
                    return
                }
            }
            if isComplete {
                finish(returning: lock.withLock { self.responseData })
            } else {
                receive()
            }
        }
    }

    private func finish(returning data: Data) {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        guard let continuation else { return }
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(returning: data)
    }

    private func finish(throwing error: Error) {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        guard let continuation else { return }
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(throwing: error)
    }
}

final class SecureAIHTTPDataClient: HTTPDataClient, @unchecked Sendable {
    private let hostResolver: any AIHostAddressResolving
    private let pinnedTransport: any AIPinnedHTTPTransport
    private let maximumResponseBytes: Int

    init(
        maximumResponseBytes: Int = 2_000_000,
        hostResolver: any AIHostAddressResolving = SystemAIHostResolver(),
        transport: any AIPinnedHTTPTransport = NetworkPinnedHTTPTransport()
    ) {
        let maximumResponseBytes = max(0, maximumResponseBytes)
        self.hostResolver = hostResolver
        self.pinnedTransport = transport
        self.maximumResponseBytes = maximumResponseBytes
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var currentRequest = request
        for redirectCount in 0...5 {
            guard let url = currentRequest.url, let host = url.host else {
                throw AIEndpointPolicyError.missingHost
            }
            try AIEndpointPolicy.validate(url)
            let addresses = try await hostResolver.resolve(host)
            try AIEndpointPolicy.validateResolvedAddresses(addresses, for: host)

            guard !addresses.isEmpty,
                  let port = UInt16(exactly: url.port ?? 443) else {
                throw AIEndpointPolicyError.dnsResolutionFailed
            }
            var result: (Data, HTTPURLResponse)?
            for (index, address) in addresses.enumerated() {
                do {
                    result = try await pinnedTransport.data(
                        for: currentRequest,
                        connectingTo: address,
                        serverName: host,
                        port: port,
                        maximumResponseBytes: maximumResponseBytes
                    )
                    break
                } catch {
                    guard index + 1 < addresses.count,
                          Self.isConnectionFailure(error) else {
                        throw error
                    }
                }
            }
            guard let (data, response) = result else {
                throw URLError(.cannotConnectToHost)
            }
            guard data.count <= maximumResponseBytes else {
                throw HTTPDataClientError.responseTooLarge
            }
            guard [301, 302, 303, 307, 308].contains(response.statusCode),
                  let location = response.value(forHTTPHeaderField: "Location") else {
                return (data, response)
            }
            guard redirectCount < 5 else {
                throw URLError(.httpTooManyRedirects)
            }
            guard let redirectedURL = URL(string: location, relativeTo: url)?.absoluteURL,
                  AIEndpointPolicy.allowsRedirect(from: url, to: redirectedURL) else {
                throw AIEndpointPolicyError.privateOrReservedHost
            }
            currentRequest = Self.redirectedRequest(
                from: currentRequest,
                to: redirectedURL,
                statusCode: response.statusCode
            )
        }
        throw URLError(.httpTooManyRedirects)
    }

    private static func redirectedRequest(
        from request: URLRequest,
        to url: URL,
        statusCode: Int
    ) -> URLRequest {
        var redirected = request
        redirected.url = url
        let method = (request.httpMethod ?? "GET").uppercased()
        if statusCode == 303 || ((statusCode == 301 || statusCode == 302) && method == "POST") {
            redirected.httpMethod = "GET"
            redirected.httpBody = nil
            redirected.setValue(nil, forHTTPHeaderField: "Content-Length")
            redirected.setValue(nil, forHTTPHeaderField: "Content-Type")
        }
        return redirected
    }

    private static func isConnectionFailure(_ error: Error) -> Bool {
        if error is NWError {
            return true
        }
        guard let urlError = error as? URLError else { return false }
        return [
            .cannotConnectToHost,
            .networkConnectionLost,
            .notConnectedToInternet,
            .timedOut
        ].contains(urlError.code)
    }
}
