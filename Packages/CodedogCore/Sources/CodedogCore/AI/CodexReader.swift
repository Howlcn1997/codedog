import Foundation

/// 读取 Codex 会话日志：`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`（压缩归档跳过）。
enum CodexReader {
    static var root: String {
        (ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory() + "/.codex") + "/sessions"
    }

    static func sessionFiles() -> [String] {
        guard let e = FileManager.default.enumerator(atPath: root) else { return [] }
        var out: [String] = []
        while let rel = e.nextObject() as? String {
            if rel.hasSuffix(".jsonl") { out.append(root + "/" + rel) }
        }
        return out
    }

    static func summarize(file: String) -> SessionSummary {
        var s = SessionSummary(tool: .codex, id: (file as NSString).lastPathComponent, file: file)
        var model = "codex"
        var lastTotal = TokenUsage()        // token_count 是累计值，取最后一次
        var tokensByModel: [String: TokenUsage] = [:]
        var lastEvent: (date: Date, complete: Bool)?

        JSONLScanner.forEachLine(path: file, matchingAny: [#""session_meta""#, #""turn_context""#, #""thread_settings_applied""#, #""token_count""#, #""task_complete""#, #""task_started""#, #""user_message""#, #""UserMessage""#, #""agent_message""#]) { obj in
            let type = obj["type"] as? String
            let payload = obj["payload"] as? [String: Any] ?? [:]
            let ts = (obj["timestamp"] as? String).flatMap(DayKey.parseISO)
            switch type {
            case "session_meta":
                if let id = payload["id"] as? String { s.id = id }
                if let cwd = payload["cwd"] as? String { s.cwd = cwd }
            case "turn_context":
                if s.cwd == nil, let cwd = payload["cwd"] as? String { s.cwd = cwd }
                if let m = payload["model"] as? String { model = m }
            case "event_msg":
                let kind = payload["type"] as? String
                if kind == "thread_settings_applied", let settings = payload["thread_settings"] as? [String: Any], let m = settings["model"] as? String {
                    model = m
                }
                if kind == "token_count", let info = payload["info"] as? [String: Any], let total = info["total_token_usage"] as? [String: Any] {
                    let now = codexUsage(total)
                    // 增量记到当前模型名下
                    let delta = TokenUsage(input: max(0, now.input - lastTotal.input), output: max(0, now.output - lastTotal.output),
                                           cacheRead: max(0, now.cacheRead - lastTotal.cacheRead), cacheWrite5m: max(0, now.cacheWrite5m - lastTotal.cacheWrite5m))
                    tokensByModel[model, default: TokenUsage()] += delta
                    lastTotal = now
                }
                guard let ts else { return }
                switch kind {
                case "task_complete": lastEvent = (ts, true)
                case "task_started", "user_message": lastEvent = (ts, false)
                case "agent_message": s.days[DayKey.string(ts), default: 0] += 1
                default: break
                }
                if kind == "task_complete" || kind == "agent_message" || kind == "user_message" || kind == "task_started" {
                    s.startedAt = min(s.startedAt ?? ts, ts)
                    s.lastAt = max(s.lastAt ?? ts, ts)
                }
                if kind == "task_complete" {
                    s.days[DayKey.string(ts), default: 0] += 1
                    if let msg = payload["last_agent_message"] as? String, s.title == nil { s.title = String(msg.prefix(60)) }
                }
            default: break
            }
        }
        s.tokens = tokensByModel.filter { $0.value.total > 0 }
        s.waiting = lastEvent?.complete ?? false
        return s
    }

    static func codexUsage(_ u: [String: Any]) -> TokenUsage {
        func int(_ k: String) -> Int { (u[k] as? NSNumber)?.intValue ?? 0 }
        let cached = int("cached_input_tokens")
        return TokenUsage(input: max(0, int("input_tokens") - cached), output: int("output_tokens"), cacheRead: cached, cacheWrite5m: int("cache_write_input_tokens"))
    }
}

/// VS Code 系编辑器的工作区记录：`~/Library/Application Support/<App>/User/workspaceStorage/*/workspace.json`。
enum EditorUsageReader {
    static let apps: [(tool: AITool, folder: String)] = [
        (.vscode, "Code"), (.cursor, "Cursor"), (.windsurf, "Windsurf"), (.trae, "Trae"),
    ]

    /// 返回 (工具, 文件夹路径, 首次, 最近)。
    static func usages() -> [(tool: AITool, path: String, first: Date?, last: Date?)] {
        let fm = FileManager.default
        var out: [(AITool, String, Date?, Date?)] = []
        for app in apps {
            let storage = NSHomeDirectory() + "/Library/Application Support/\(app.folder)/User/workspaceStorage"
            for dir in (try? fm.contentsOfDirectory(atPath: storage)) ?? [] {
                let base = storage + "/" + dir
                guard let data = fm.contents(atPath: base + "/workspace.json"),
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let folder = json["folder"] as? String, let url = URL(string: folder), url.isFileURL else { continue }
                let first = (try? fm.attributesOfItem(atPath: base + "/workspace.json"))?[.creationDate] as? Date
                let last = ((try? fm.attributesOfItem(atPath: base + "/state.vscdb"))?[.modificationDate] as? Date)
                    ?? ((try? fm.attributesOfItem(atPath: base))?[.modificationDate] as? Date)
                out.append((app.tool, FolderScanner.normalize(url.path(percentEncoded: false)), first, last))
            }
        }
        return out
    }
}
