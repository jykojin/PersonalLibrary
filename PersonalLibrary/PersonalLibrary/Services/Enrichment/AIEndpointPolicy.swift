import Foundation
import Darwin

enum AIEndpointPolicyError: Error, Equatable, LocalizedError {
    case httpsRequired
    case credentialsNotAllowed
    case fragmentNotAllowed
    case missingHost
    case privateOrReservedHost
    case dnsResolutionFailed

    var errorDescription: String? {
        switch self {
        case .httpsRequired: return "接口地址必须使用 HTTPS"
        case .credentialsNotAllowed: return "接口地址不能包含用户名、密码或除 api-version 外的查询参数"
        case .fragmentNotAllowed: return "接口地址不能包含片段标识"
        case .missingHost: return "接口地址缺少主机名"
        case .privateOrReservedHost: return "接口地址不能指向本机、私网或保留地址"
        case .dnsResolutionFailed: return "无法解析接口地址的主机名"
        }
    }
}

enum AIEndpointPolicy {
    private static let trustedVPNFakeIPHosts = Set(
        AIPlatformPreset.allCases
            .filter { $0 != .custom }
            .compactMap { $0.defaultEndpoint.host?.lowercased() }
    ).union(["api.drand.sh"])

    static func validate(_ endpoint: URL) throws {
        guard endpoint.scheme?.lowercased() == "https" else {
            throw AIEndpointPolicyError.httpsRequired
        }
        guard endpoint.user == nil, endpoint.password == nil else {
            throw AIEndpointPolicyError.credentialsNotAllowed
        }
        guard !containsUnsupportedQueryItem(endpoint) else {
            throw AIEndpointPolicyError.credentialsNotAllowed
        }
        guard endpoint.fragment == nil else {
            throw AIEndpointPolicyError.fragmentNotAllowed
        }
        guard let host = endpoint.host?.lowercased(), !host.isEmpty else {
            throw AIEndpointPolicyError.missingHost
        }
        guard !isPrivateOrReserved(host) else {
            throw AIEndpointPolicyError.privateOrReservedHost
        }
    }

    static func appending(_ path: String, to endpoint: URL) throws -> URL {
        try validate(endpoint)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw AIEndpointPolicyError.missingHost
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, suffix].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components.url else { throw AIEndpointPolicyError.missingHost }
        try validate(url)
        return url
    }

    static func allowsRedirect(from original: URL, to redirected: URL) -> Bool {
        guard (try? validate(redirected)) != nil else { return false }
        return original.host?.lowercased() == redirected.host?.lowercased()
            && effectivePort(original) == effectivePort(redirected)
    }

    static func validateResolvedAddresses(_ addresses: [String], for host: String) throws {
        guard !addresses.isEmpty else { throw AIEndpointPolicyError.dnsResolutionFailed }
        let allowsVPNFakeIP = trustedVPNFakeIPHosts.contains(host.lowercased())
        guard addresses.allSatisfy({ address in
            !isPrivateOrReserved(address.lowercased())
                || (allowsVPNFakeIP && isVPNFakeIPv4(address))
        }) else {
            throw AIEndpointPolicyError.privateOrReservedHost
        }
    }

    private static func effectivePort(_ url: URL) -> Int {
        url.port ?? 443
    }

    private static func containsUnsupportedQueryItem(_ url: URL) -> Bool {
        guard let queryItems = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems else {
            return false
        }
        return queryItems.contains { item in
            item.name.caseInsensitiveCompare("api-version") != .orderedSame
        }
    }

    private static func isPrivateOrReserved(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        if host.allSatisfy(\.isNumber) || host.hasPrefix("0x") { return true }

        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, host, &ipv6) == 1 {
            let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
            if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
                return isPrivateIPv4(Array(bytes[12..<16]))
            }
            let isUnspecified = bytes.allSatisfy { $0 == 0 }
            let isLoopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
            let isUniqueLocal = bytes[0] & 0xfe == 0xfc
            let isLinkLocal = bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80
            let isMulticast = bytes[0] == 0xff
            let isDocumentation = bytes[0...3].elementsEqual([0x20, 0x01, 0x0d, 0xb8])
            return isUnspecified || isLoopback || isUniqueLocal || isLinkLocal
                || isMulticast || isDocumentation
        }

        guard let octets = ipv4Octets(host) else {
            return false
        }
        return isPrivateIPv4(octets)
    }

    private static func isPrivateIPv4(_ octets: [UInt8]) -> Bool {
        guard octets.count == 4 else { return true }
        switch (Int(octets[0]), Int(octets[1]), Int(octets[2])) {
        case (0, _, _), (10, _, _), (127, _, _), (169, 254, _), (192, 168, _),
             (192, 0, 0), (192, 0, 2), (198, 18...19, _), (198, 51, 100),
             (203, 0, 113), (224...255, _, _):
            return true
        case (100, 64...127, _), (172, 16...31, _):
            return true
        default:
            return false
        }
    }

    private static func isVPNFakeIPv4(_ host: String) -> Bool {
        guard let octets = ipv4Octets(host) else { return false }
        return octets[0] == 198
            && (18...19).contains(octets[1])
    }

    private static func ipv4Octets(_ host: String) -> [UInt8]? {
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        return octets.count == 4 ? octets : nil
    }
}

protocol AIHostAddressResolving: Sendable {
    func resolve(_ host: String) async throws -> [String]
}

struct SystemAIHostResolver: AIHostAddressResolving {
    func resolve(_ host: String) async throws -> [String] {
        try await Task.detached(priority: .utility) {
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM

            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
                throw AIEndpointPolicyError.dnsResolutionFailed
            }
            defer { freeaddrinfo(first) }

            var addresses: Set<String> = []
            var current: UnsafeMutablePointer<addrinfo>? = first
            while let entry = current {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    entry.pointee.ai_addr,
                    entry.pointee.ai_addrlen,
                    &buffer,
                    socklen_t(buffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    addresses.insert(String(cString: buffer))
                }
                current = entry.pointee.ai_next
            }
            guard !addresses.isEmpty else { throw AIEndpointPolicyError.dnsResolutionFailed }
            return addresses.sorted()
        }.value
    }
}
