import Foundation
import Testing
@testable import Pulse

/// Answers every request with a 403 and OpenCode Go's entitlement error.
private final class ResponseLogStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 403, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"type":"error","error":{"type":"EntitlementError","message":"OpenCode Go subscription required."}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// The server replies the connection diagnostics show: recorded only during
/// a check, never a request header or a query, credentials masked in the body.
@Suite("Server replies")
struct ResponseLogTests {
    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResponseLogStub.self]
        return URLSession(configuration: configuration)
    }

    @Test("A check's requests are recorded with its reading; outside a check nothing is")
    func capturedDuringACheck() async throws {
        let session = Self.session()
        let request = {
            var request = URLRequest(url: URL(string: "https://opencode.ai/zen/go/v1/usage?key=secret-in-query")!)
            request.setValue("Bearer oc_sk_should_never_be_kept", forHTTPHeaderField: "Authorization")
            return request
        }()

        let reading = await ResponseLog.capture {
            _ = try? await session.recordedData(for: request)
            return .unavailable(.openCodeGo, reason: .noPlan)
        }
        let entry = try #require(reading.responses.first)
        #expect(reading.responses.count == 1)
        #expect(entry.status == 403)
        #expect(entry.address == "https://opencode.ai/zen/go/v1/usage")
        #expect(entry.contentType == "application/json")
        #expect(entry.body.contains("OpenCode Go subscription required."))
        #expect(!entry.body.contains("oc_sk"))
        #expect(!entry.address.contains("secret"))

        // No check running: nothing to record into, and nothing kept.
        _ = try? await session.recordedData(for: request)
        #expect(ResponseLog.collector == nil)
    }

    @Test("Values under credential names are masked; counts and plain words are not")
    func jsonRedaction() {
        let body = Data("""
        {"access_token":"abc","refresh_token":"def","session":"s","api_key":"k","input_tokens":1200,
         "model":"claude-opus-4-6-20260101","email":"me@example.com","nested":{"secret":"x","plan":"Pro"}}
        """.utf8)
        let text = ResponseLog.text(of: body, contentType: "application/json")
        #expect(!text.contains("\"abc\"") && !text.contains("\"def\"") && !text.contains("\"k\""))
        #expect(text.contains("\"access_token\" : \"\(ResponseLog.mask)\""))
        #expect(text.contains("\"input_tokens\" : 1200"))
        #expect(text.contains("claude-opus-4-6-20260101"))
        #expect(text.contains("me@example.com"))
        #expect(text.contains("\"plan\" : \"Pro\""))
    }

    @Test("Long random runs are masked in any text; model names and UUIDs survive")
    func textRedaction() {
        let key = "sk-proj-Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy4z"
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
        let text = ResponseLog.redacted("Incorrect key \(key); token \(jwt); model gpt-5.6-codex-max-2026-10-01; id 123e4567-e89b-12d3-a456-426614174000")
        #expect(!text.contains(key))
        #expect(!text.contains("eyJhbGci"))
        #expect(text.contains("gpt-5.6-codex-max-2026-10-01"))
        #expect(text.contains("123e4567-e89b-12d3-a456-426614174000"))
    }

    @Test("A failed request is recorded with no status and its error")
    func failure() {
        let request = URLRequest(url: URL(string: "https://example.com/v1/usage")!)
        let entry = ResponseLog.entry(request, response: nil, data: nil, error: URLError(.timedOut), at: Date())
        #expect(entry.status == nil)
        #expect(entry.body.contains("-1001"))
    }

    @Test("A long body is cut, and bytes that are not text say so")
    func limits() {
        let long = ResponseLog.text(of: Data(String(repeating: "a ", count: 5000).utf8), contentType: "text/plain")
        #expect(long.count <= ResponseLog.bodyLimit + 2)
        #expect(!ResponseLog.text(of: Data([0xFF, 0xFE, 0x00, 0x81]), contentType: nil).isEmpty)
    }

    @Test("A failed status page read says which request failed and how")
    func failureLine() {
        let request = URLRequest(url: URL(string: "https://status.example.com/api/status")!)
        let ok = ResponseLog.Entry(at: Date(), method: "GET", address: "a", status: 200, contentType: nil, body: "{}", byteCount: 2)
        let refused = ResponseLog.Entry(at: Date(), method: "GET", address: "b", status: 503, contentType: nil, body: "", byteCount: 0)
        let dropped = ResponseLog.entry(request, response: nil, data: nil, error: URLError(.timedOut), at: Date())
        #expect(ResponseLog.failure(of: [ok, refused]).contains("503"))
        #expect(ResponseLog.failure(of: [dropped]).contains("-1001"))
        #expect(ResponseLog.failure(of: [ok]) != ResponseLog.failure(of: []))
    }

    @Test("Keys in the shapes the review found leaking are masked")
    func reviewLeaks() {
        // `sk-` and 32 small hex digits: no capitals, under 40 characters.
        let hexKey = "sk-" + String(repeating: "a1b2c3d4", count: 4)
        #expect(!ResponseLog.redacted("Invalid key \(hexKey)").contains(hexKey))
        // Short tokens in an array under a credential name.
        let body = Data(#"{"tokens":["abc123","def456"],"session":{"id":"s-1"},"usage":{"input_tokens":12}}"#.utf8)
        let text = ResponseLog.text(of: body, contentType: "application/json")
        #expect(!text.contains("abc123") && !text.contains("def456") && !text.contains("s-1"))
        #expect(text.contains("\"input_tokens\" : 12"))
        // Known prefixes, however short the rest.
        #expect(!ResponseLog.redacted("ghp_abcdefghijklmnop").contains("ghp_"))
    }

    @Test("Whatever credential the request carried is masked wherever the reply repeats it")
    func echoedCredentials() {
        var request = URLRequest(url: URL(string: "https://example.com/v1/usage?api_key=plainwordsecret")!)
        request.setValue("Bearer shortsecretvalue", forHTTPHeaderField: "Authorization")
        request.setValue("session=cookievalue123; theme=dark", forHTTPHeaderField: "Cookie")
        let reply = Data(#"{"error":"bad token shortsecretvalue for plainwordsecret, cookie cookievalue123"}"#.utf8)
        let entry = ResponseLog.entry(request, response: nil, data: reply, error: nil, at: Date())
        #expect(!entry.body.contains("shortsecretvalue"))
        #expect(!entry.body.contains("plainwordsecret"))
        #expect(!entry.body.contains("cookievalue123"))
        #expect(entry.body.contains("bad token"))
    }

    @Test("A redirect says where it pointed, without the query")
    func redirectTarget() {
        let url = URL(string: "https://example.com/app")!
        let reply = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
                                    headerFields: ["Location": "https://accounts.example.com/signin?continue=secret"])
        let entry = ResponseLog.entry(URLRequest(url: url), response: reply, data: Data(), error: nil, at: Date())
        #expect(entry.body == "Location: https://accounts.example.com/signin")
        let relative = HTTPURLResponse(url: url, statusCode: 301, httpVersion: nil, headerFields: ["Location": "/app/"])
        #expect(ResponseLog.entry(URLRequest(url: url), response: relative, data: Data(), error: nil, at: Date()).body
            == "Location: https://example.com/app/")
    }
}
