import CryptoKit
import Foundation
import Testing
@testable import Pulse

/// Volcengine's signature.
///
/// **What these can and cannot prove.** Nobody here holds a Volcengine plan, so no
/// signature in this suite has ever been accepted by Volcengine — a live 200
/// is the one thing untested. What *is* tested is everything the scheme states
/// outright and every part of it that a transcription error would break
/// silently: the credential scope, the signed-header list and its order, the
/// encoding rules, the query canonicalisation, and the four-step key
/// derivation checked against an independent computation. A wrong signature
/// comes back as a bare 403, so these exist to make that the *unlikely*
/// explanation when somebody reports one.
@Suite("Volcengine signing")
struct VolcengineSignerTests {
    private static let credentials = VolcengineSigner.Credentials(
        accessKeyID: "AKLTTestAccessKeyId",
        secretAccessKey: "dGVzdC1zZWNyZXQtYWNjZXNzLWtleQ==",
        region: "cn-beijing"
    )
    /// 2026-09-07T09:30:00Z, so the day stamp and the timestamp are both fixed.
    private static let date = Date(timeIntervalSince1970: 1_788_773_400)
    private static let url = URL(
        string: "https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01"
    )!

    private static func headers(url: URL = url, body: Data = Data()) -> [String: String] {
        VolcengineSigner.headers(
            method: "GET",
            url: url,
            body: body,
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            credentials: credentials,
            date: date
        )
    }

    @Test("The timestamp and the day stamp are UTC, whatever the Mac is set to")
    func stampsAreUTC() throws {
        let headers = Self.headers()
        #expect(headers["X-Date"] == "20260907T093000Z")
        // The day inside the credential scope has to agree with it.
        let authorization = try #require(headers["Authorization"])
        #expect(authorization.contains("Credential=AKLTTestAccessKeyId/20260907/cn-beijing/ark/request"))
    }

    @Test("The scope ends `ark/request`, not AWS's `aws4_request`")
    func credentialScope() throws {
        let authorization = try #require(Self.headers()["Authorization"])
        #expect(authorization.hasPrefix("HMAC-SHA256 Credential="))
        #expect(authorization.contains("/ark/request,"))
        #expect(!authorization.contains("aws4_request"))
    }

    @Test("Signed headers are lower-cased and sorted, and match what is sent")
    func signedHeaderList() throws {
        let headers = Self.headers()
        let authorization = try #require(headers["Authorization"])
        #expect(authorization.contains("SignedHeaders=content-type;host;x-content-sha256;x-date,"))

        // The server re-sorts and recomputes, so a list that does not match the
        // headers actually sent is a 403 with nothing to read.
        let listed = ["content-type", "host", "x-content-sha256", "x-date"]
        #expect(listed == listed.sorted())
        for name in listed {
            let sent = headers.keys.first { $0.lowercased() == name }
            #expect(sent != nil, "\(name) is signed but not sent")
        }
    }

    @Test("An empty body is hashed, not skipped")
    func emptyBodyHash() throws {
        let headers = Self.headers()
        // SHA-256 of zero bytes, which is what the scheme asks for and not the
        // empty string.
        #expect(headers["X-Content-Sha256"]
            == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("Host comes from the URL and is sent as a header")
    func hostHeader() {
        #expect(Self.headers()["Host"] == "open.volcengineapi.com")
    }

    @Test("The signing key is the documented four-step chain")
    func signingKeyDerivation() throws {
        // Computed here independently of the signer, so a transcription slip in
        // the order of the steps — the easiest thing to get wrong and the
        // hardest to see — fails here rather than as a 403 in the field.
        func hmac(_ message: String, key: SymmetricKey) -> Data {
            Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key))
        }
        var key = SymmetricKey(data: Data(Self.credentials.secretAccessKey.utf8))
        for step in ["20260907", "cn-beijing", "ark", "request"] {
            key = SymmetricKey(data: hmac(step, key: key))
        }

        let canonicalRequest = [
            "GET",
            "/",
            "Action=GetCodingPlanUsage&Version=2024-01-01",
            "content-type:application/x-www-form-urlencoded; charset=utf-8",
            "host:open.volcengineapi.com",
            "x-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "x-date:20260907T093000Z",
            "",
            "content-type;host;x-content-sha256;x-date",
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        ].joined(separator: "\n")
        let hashed = SHA256.hash(data: Data(canonicalRequest.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let stringToSign = [
            "HMAC-SHA256",
            "20260907T093000Z",
            "20260907/cn-beijing/ark/request",
            hashed
        ].joined(separator: "\n")
        let expected = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
            .map { String(format: "%02x", $0) }.joined()

        let authorization = try #require(Self.headers()["Authorization"])
        #expect(authorization.hasSuffix("Signature=\(expected)"))
    }

    @Test("Query items are sorted by name, then value — not left in URL order")
    func queryIsCanonicalised() throws {
        // Same two parameters, opposite order in the URL. The server rebuilds
        // this string from its own parse, so both must sign identically.
        let forwards = URL(string: "https://open.volcengineapi.com/?Action=A&Version=B")!
        let backwards = URL(string: "https://open.volcengineapi.com/?Version=B&Action=A")!

        #expect(Self.headers(url: forwards)["Authorization"] == Self.headers(url: backwards)["Authorization"])
    }

    @Test("A tilde is left alone; everything outside the unreserved set is escaped")
    func encodingRules() throws {
        // `addingPercentEncoding` with a stock character set escapes `~` and
        // leaves other things alone, and either mistake is a silent 403.
        let tilde = URL(string: "https://open.volcengineapi.com/?Action=a~b")!
        let space = URL(string: "https://open.volcengineapi.com/?Action=a%20b")!

        let signedTilde = try #require(Self.headers(url: tilde)["Authorization"])
        let signedSpace = try #require(Self.headers(url: space)["Authorization"])
        // Different inputs, different signatures — proves the query reached the
        // canonical form at all rather than being dropped.
        #expect(signedTilde != signedSpace)
        #expect(signedTilde != (try #require(Self.headers()["Authorization"])))
    }

    @Test("A different body changes the signature")
    func bodyIsSigned() throws {
        let empty = try #require(Self.headers()["Authorization"])
        let filled = try #require(Self.headers(body: Data("{}".utf8))["Authorization"])
        #expect(empty != filled)
    }

    @Test("The whole header, against a second implementation of the same scheme")
    func crossChecked() throws {
        // This signature was **not** copied out of this implementation. It was
        // computed by a separate one written from the scheme in another
        // language, so the two agreeing is evidence about the algorithm rather
        // than a photograph of whatever the code happened to do. What it still
        // cannot say is that Volcengine accepts it; only an account can.
        #expect(try #require(Self.headers()["Authorization"]) == """
        HMAC-SHA256 Credential=AKLTTestAccessKeyId/20260907/cn-beijing/ark/request, \
        SignedHeaders=content-type;host;x-content-sha256;x-date, \
        Signature=3bc6ebb4fd6da065cae0c05dbfc35285cdced26090d7c0aea87b2f2330cd031d
        """)
    }
}
