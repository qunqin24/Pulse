import Foundation

/// Public announcements, never evidence that this particular account was reset.
struct CodexResetFeed: Decodable, Sendable {
    struct Event: Decodable, Sendable {
        struct Schedule: Decodable, Sendable {
            let label: String
            let from: Date
            let through: Date
        }

        let title: String
        let schedule: Schedule?
    }

    let events: [Event]

    func nextEvent(now: Date = Date()) -> Event? {
        events.filter { ($0.schedule?.through ?? .distantPast) > now }
            .min { ($0.schedule?.from ?? .distantFuture) < ($1.schedule?.from ?? .distantFuture) }
    }

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                       debugDescription: "Invalid reset timestamp"))
            }
            return date
        }
        return try decoder.decode(Self.self, from: data)
    }

    static func fetch() async -> Self? {
        var request = URLRequest(url: URL(string: "https://aihot.news/api/v1/codex-resets")!)
        request.timeoutInterval = 20
        do {
            let (data, response) = try await NetworkSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try decode(data)
        } catch { return nil }
    }
}
