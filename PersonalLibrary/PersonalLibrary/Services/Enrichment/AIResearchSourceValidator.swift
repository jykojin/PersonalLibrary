import Foundation
import Darwin

enum AIResearchSourceValidator {
    static let verificationDisclaimer = "来源 URL 仅作核验线索，App 未独立读取并逐字验证网页正文。"

    static func validate(_ values: [String], endpoint: URL) -> [URL]? {
        guard !values.isEmpty else { return nil }
        let urls = values.compactMap(URL.init(string:))
        guard urls.count == values.count,
              urls.allSatisfy({ isAllowed($0, endpoint: endpoint) }) else {
            return nil
        }
        return urls
    }

    private static func isAllowed(_ url: URL, endpoint: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = canonicalHost(url),
              let endpointHost = canonicalHost(endpoint) else {
            return false
        }
        return host != endpointHost
    }

    private static func canonicalHost(_ url: URL) -> String? {
        guard var host = url.host?.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty else {
            return nil
        }
        if host.hasPrefix("["), host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }

        var ipv4 = in_addr()
        // inet_aton intentionally accepts the legacy IPv4 spellings that URL loading
        // still resolves (single-number, hexadecimal, and shortened dotted forms).
        if inet_aton(host, &ipv4) == 1 {
            return withUnsafeBytes(of: &ipv4) { "ipv4:" + Data($0).base64EncodedString() }
        }
        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, host, &ipv6) == 1 {
            let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
            if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
                return "ipv4:" + Data(bytes[12..<16]).base64EncodedString()
            }
            return "ipv6:" + Data(bytes).base64EncodedString()
        }
        return "dns:\(host)"
    }
}
