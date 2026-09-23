import Foundation

/// Project identity survives reading and caching; its short name is only a label.
struct UsageProject: Hashable, Codable, Sendable {
    enum Identity: Hashable, Codable, Sendable {
        case directory(String)
        case label(String)
        /// A store's project folder when the working directory is not known.
        case source(String)
    }

    let identity: Identity
    let name: String

    init?(_ value: String?) {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if value.hasPrefix("/") {
            // Normalize separators only. Resolving symlinks or `..` would make
            // historical attribution depend on the current filesystem.
            let parts = value.split(separator: "/")
            let path = "/" + parts.joined(separator: "/")
            identity = .directory(path)
            name = parts.last.map(String.init) ?? "/"
        } else {
            identity = .label(value)
            name = value
        }
    }

    init(source: String, name: String) {
        identity = .source(source)
        self.name = name
    }

    var path: String? {
        if case .directory(let path) = identity { return path }
        return nil
    }

    /// Extend only ambiguous directory names, using the shortest distinct suffix.
    static func displayName(for project: UsageProject, among projects: Set<UsageProject>) -> String {
        let peers = projects.filter { $0 != project && $0.name == project.name }
        guard !peers.isEmpty else { return project.name }
        guard let path = project.path else {
            if case .source(let source) = project.identity {
                return source
            }
            return project.name
        }
        let parts = path.split(separator: "/")
        for count in 2...max(2, parts.count) {
            let suffix = parts.suffix(count).joined(separator: "/")
            if peers.allSatisfy({ peer in
                guard let other = peer.path else { return suffix != peer.name }
                return other.split(separator: "/").suffix(count).joined(separator: "/") != suffix
            }) { return suffix }
        }
        return path
    }
}
