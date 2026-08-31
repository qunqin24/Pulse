import Foundation

/// Compiles the production client directly; no credentials, network, or app launch.
@main
struct OllamaCloudTests {
    static func check(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }

    static func fails(_ expected: OllamaCloudError, _ action: () throws -> Void) {
        do { try action(); preconditionFailure("Expected \(expected)") }
        catch { check(error as? OllamaCloudError == expected, "Unexpected error: \(error)") }
    }

    static func page(session: String = "17.5% used", weekly: String = "62% used",
                     sessionTime: String = "2026-09-01T10:00:00.123Z",
                     weeklyTime: String = "2026-09-07T10:00:00Z") -> Data {
        Data("""
        <!doctype html><html><body>
        <h2><span>Cloud Usage</span><span>Pro</span></h2>
        <div data-usage-meter>
          <div><span>Session usage</span><span>\(session)</span></div>
          <div data-usage-track aria-label="Session usage">
            <button data-usage-segment style="width: 3%">A model</button>
          </div>
          <div class="local-time" data-time="\(sessionTime)">Resets later</div>
        </div>
        <div data-usage-meter>
          <div><span>Weekly usage</span><span>\(weekly)</span></div>
          <div data-usage-track><button data-usage-segment style="width: 22%">Another model</button></div>
          <div class="local-time" data-time="\(weeklyTime)">Resets later</div>
        </div>
        <script>const example = '90% used';</script>
        </body></html>
        """.utf8)
    }

    static func main() throws {
        let normal = try OllamaCloudPage.parse(page())
        check(normal.session.usedFraction == 0.175, "Session total, not CSS segment")
        check(normal.weekly.usedFraction == 0.62, "Weekly total")
        check(normal.session.resetsAt != nil && normal.weekly.resetsAt != nil, "Reset outside label row")
        check(normal.session.resetsAt! < normal.weekly.resetsAt!, "Reset association")
        let limits = try OllamaCloudPage.parse(page(session: "0% used", weekly: "100% USED"))
        check(limits.session.usedFraction == 0 && limits.weekly.usedFraction == 1, "Zero and exhausted")
        fails(.invalidPage) { _ = try OllamaCloudPage.parse(page(session: "101% used")) }
        fails(.invalidPage) { _ = try OllamaCloudPage.parse(page(session: "-1% used")) }
        fails(.invalidPage) { _ = try OllamaCloudPage.parse(page(session: "NaN% used")) }
        fails(.invalidPage) { _ = try OllamaCloudPage.parse(page(session: "not reported")) }
        fails(.invalidPage) { _ = try OllamaCloudPage.parse(page(weekly: "not reported")) }
        fails(.invalidPage) { _ = try OllamaCloudPage.parse(page(sessionTime: "tomorrow")) }
        fails(.invalidPage) { _ = try OllamaCloudPage.parse(Data("<html>No usage</html>".utf8)) }
        fails(.invalidPage) { _ = try OllamaCloudPage.parse(Data(repeating: 32, count: OllamaCloudPage.maximumBytes + 1)) }
        fails(.invalidPage) { _ = try OllamaCloudPage.parse(Data("<!DOCTYPE html [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><html>&secret;</html>".utf8)) }
        fails(.signedOut) { _ = try OllamaCloudPage.parse(Data("<html><form action='/auth/signin'><input type='email'></form></html>".utf8)) }
        let noResetHTML = String(decoding: page(), as: UTF8.self)
            .replacingOccurrences(of: #" data-time="2026-09-01T10:00:00.123Z""#, with: "")
        let noReset = try OllamaCloudPage.parse(Data(noResetHTML.utf8))
        check(noReset.session.resetsAt == nil && noReset.weekly.resetsAt != nil, "Do not borrow another window's reset")
        let duplicate = String(decoding: page(), as: UTF8.self).replacingOccurrences(of: "17.5% used", with: "17.5% used</span><span>12% used")
        fails(.invalidPage) { _ = try OllamaCloudPage.parse(Data(duplicate.utf8)) }
        let scriptOnly = "<html><script>\(String(decoding: page(), as: UTF8.self))</script></html>"
        fails(.invalidPage) { _ = try OllamaCloudPage.parse(Data(scriptOnly.utf8)) }

        check(try OllamaSessionCookie.normalize("Cookie: analytics=ignored; wos-session=fake-value") == "wos-session=fake-value", "Strip unrelated cookies")
        check(try OllamaSessionCookie.normalize("__Secure-session=abc==") == "__Secure-session=abc==", "Preserve equals")
        check(try OllamaSessionCookie.normalize("wos-session.0=one; wos-session.1=two") == "wos-session.0=one; wos-session.1=two", "Chunked auth cookie")
        fails(.invalidCookie) { _ = try OllamaSessionCookie.normalize("wos-session=abc\r\nX-Injected: true") }
        fails(.invalidCookie) { _ = try OllamaSessionCookie.normalize("sk-api-key") }
        fails(.invalidCookie) { _ = try OllamaSessionCookie.normalize("analytics=abc") }
        fails(.invalidCookie) { _ = try OllamaSessionCookie.normalize("wos-session=") }
        fails(.invalidCookie) { _ = try OllamaSessionCookie.normalize("wos-session=a; wos-session=b") }
        fails(.missingCookie) { _ = try OllamaSessionCookie.normalize("") }
        let request = try OllamaCloudClient.request(cookie: "__Secure-session=synthetic")
        check(request.url == URL(string: "https://ollama.com/settings"), "Fixed destination")
        check(request.httpMethod == "GET", "Read only")
        check(request.value(forHTTPHeaderField: "Authorization") == nil, "Not an API key")
        for status in [301, 302, 307, 308, 401, 403] {
            let response = HTTPURLResponse(url: OllamaCloudClient.settingsURL, statusCode: status, httpVersion: nil, headerFields: nil)!
            fails(.signedOut) { try OllamaCloudClient.validate(response) }
        }
        for (status, error) in [(429, OllamaCloudError.rateLimited), (500, .serverError)] {
            let response = HTTPURLResponse(url: OllamaCloudClient.settingsURL, statusCode: status, httpVersion: nil, headerFields: nil)!
            fails(error) { try OllamaCloudClient.validate(response) }
        }
        let wrongHost = HTTPURLResponse(url: URL(string: "https://example.com/settings")!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
        fails(.invalidPage) { try OllamaCloudClient.validate(wrongHost) }
        let json = HTTPURLResponse(url: OllamaCloudClient.settingsURL, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        fails(.invalidPage) { try OllamaCloudClient.validate(json) }
        let html = HTTPURLResponse(url: OllamaCloudClient.settingsURL, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html; charset=utf-8"])!
        try OllamaCloudClient.validate(html)
        print("Ollama Cloud: parsing, cookie boundaries, request and response checks passed.")
    }
}
