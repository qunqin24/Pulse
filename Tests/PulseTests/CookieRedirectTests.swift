import Foundation
import Testing
@testable import Pulse

/// Every request seen, and a 302 to another host for the provider's own.
private final class RedirectingStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var seen: [(host: String, cookie: String?)] = []
    private static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.lock.withLock { Self.seen.append((host, request.value(forHTTPHeaderField: "Cookie"))) }
        if host == "elsewhere.example" {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let target = URL(string: "https://elsewhere.example/collect")!
        let redirect = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil,
                                       headerFields: ["Location": target.absoluteString])!
        client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: redirect)
        client?.urlProtocol(self, didReceive: redirect, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// A session cookie set by hand on a request must never reach another host
/// through a redirect: URLSession forwards hand-set headers when it follows
/// one, so these clients do not follow them.
@Suite("Session cookies and redirects", .serialized)
struct CookieRedirectTests {
    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectingStub.self]
        return URLSession(configuration: configuration)
    }

    private static func leaked() -> Bool {
        RedirectingStub.seen.contains { $0.host == "elsewhere.example" }
    }

    @Test("Qoder's session stays on Qoder's host")
    func qoder() async {
        RedirectingStub.seen = []
        var client = QoderClient()
        client.session = Self.session()
        await #expect(throws: QoderError.sessionExpired) {
            try await client.fetch(cookie: "login_token=secret", site: .international)
        }
        #expect(!Self.leaked())
    }

    @Test("Xiaomi's session stays on Xiaomi's host")
    func xiaomi() async {
        RedirectingStub.seen = []
        var client = XiaomiMiMoClient()
        client.session = Self.session()
        _ = try? await client.fetch(cookie: "api-platform_serviceToken=secret; userId=1")
        #expect(!RedirectingStub.seen.isEmpty)
        #expect(!Self.leaked())
    }
}
