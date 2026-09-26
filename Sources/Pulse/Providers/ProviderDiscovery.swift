import Foundation

extension Provider {
    /// A hint for the chooser, never permission to read. The injected existence
    /// check lets tests exercise discovery without opening anyone's files.
    static func installedOnThisMac(
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Set<Provider> {
        Set(allCases.filter { $0.discoveryPaths(home: home).contains(where: exists) })
    }

    private func discoveryPaths(home: URL) -> [String] {
        func local(_ path: String) -> String { home.appending(path: path).path }
        func app(_ name: String) -> [String] {
            ["/Applications/\(name).app", local("Applications/\(name).app")]
        }

        guard let written = handWritten else {
            return (profile?.discoveryPaths ?? []).map { $0.hasPrefix("/") ? $0 : local($0) }
        }
        switch written {
        case .claudeCode:
            return [local(".claude"), local("Library/Application Support/Claude")] + app("Claude")
        case .codex: return [local(".codex")]
        case .kiro:
            return [local(".kiro"), local("Library/Application Support/kiro-cli")] + app("Kiro") + app("Kiro CLI")
        case .grok: return [local(".grok")]
        case .grokBot: return app("Grok Bot")
        case .antigravity: return app("Antigravity")
        case .cursor:
            return [local("Library/Application Support/Cursor/User/globalStorage/state.vscdb")]
        case .openCodeGo: return [local(".local/share/opencode/auth.json")]
        case .glmCoding:
            return [".coding-relay/glm-api-key", ".config/bigmodel/api_key", ".config/zhipu/api_key"].map(local)
        case .commandCode: return [local(".commandcode/auth.json")]
        case .devin:
            return ["Devin", "Windsurf"].map {
                local("Library/Application Support/\($0)/User/globalStorage/state.vscdb")
            }
        // The editor, either edition. A hint only: what is read is the
        // browser's session for the account page, not anything the app keeps.
        case .qoder:
            return ["Qoder", "QoderCN"].map { local("Library/Application Support/\($0)") } + app("Qoder")
        // StepFun's own coding CLI, Step Code. A hint only: what is read is the
        // console's browser session, not the CLI's saved credential.
        case .stepFun:
            return [local(".stepcode")]
        // sub2api is somebody's own deployment and V2EX is a website; there
        // is nothing on this Mac that says either is in use.
        case .kimiCode, .ollamaCloud, .zai, .minimax, .minimaxCN, .copilot,
             .volcengine, .deepSeek, .xiaomiMiMo, .sub2api, .newAPI, .v2ex:
            return []
        // Found by its manifest in the extensions folder, not by anything
        // installed. See `ExtensionCatalog`.
        case .pulseExtension:
            return []
        }
    }
}
