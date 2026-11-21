import Foundation

/// 读取 Claude Code 会话日志：`<config>/projects/<key>/<sessionId>.jsonl`。
/// 只读，从不修改日志。
enum ClaudeCodeReader {
    static func configDirectories() -> [String] {
        var dirs = [NSHomeDirectory() + "/.claude"]
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty { dirs.insert(custom, at: 0) }
        return dirs.filter { FileManager.default.fileExists(atPath: $0 + "/projects") }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    static func sessionFiles() -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        for dir in configDirectories() {
            let projects = dir + "/projects"
            for key in (try? fm.contentsOfDirectory(atPath: projects)) ?? [] {
                let folder = projects + "/" + key
                for f in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] where f.hasSuffix(".jsonl") {
                    out.append(folder + "/" + f)
                }
            }
        }
        return out
    }

    static func summarize(file: String) -> SessionSummary {
        var s = SessionSummary(tool: .claudeCode, id: ((file as NSString).lastPathComponent as NSString).deletingPathExtension, file: file)
        var seen = Set<String>()       // 流式回复会把同一条消息拆成多行，按 message.id 去重
        var lastHuman: Date?
        var lastAssistant: (date: Date, stop: String?)?

        JSONLScanner.forEachLine(path: file, matchingAny: [#""type":"assistant""#, #""type":"user""#, #""type":"ai-title""#, #""type":"last-prompt""#]) { obj in
            let type = obj["type"] as? String
            switch type {
            case "ai-title":
                if let t = obj["aiTitle"] as? String, !t.isEmpty { s.title = t }
            case "last-prompt":
                if let t = obj["lastPrompt"] as? String, !t.isEmpty { s.lastPrompt = t }
            case "user", "assistant":
                if s.cwd == nil, let cwd = obj["cwd"] as? String { s.cwd = cwd }
                if let sid = obj["sessionId"] as? String { s.id = sid }
                guard let ts = (obj["timestamp"] as? String).flatMap(DayKey.parseISO) else { return }
                let message = obj["message"] as? [String: Any]
                if type == "user" {
                    guard isHumanPrompt(obj, message: message) else { return }
                    lastHuman = max(lastHuman ?? ts, ts)
                    note(&s, ts)
                    return
                }
                guard let message else { return }
                let key = (message["id"] as? String) ?? (obj["uuid"] as? String) ?? UUID().uuidString
                let stop = message["stop_reason"] as? String
                if lastAssistant == nil || ts >= lastAssistant!.date { lastAssistant = (ts, stop ?? lastAssistant?.stop) }
                guard seen.insert(key).inserted else {
                    // 同一消息的后续分片可能带上最终 stop_reason / usage，这里只更新结束原因
                    return
                }
                note(&s, ts)
                s.days[DayKey.string(ts), default: 0] += 1
                if let model = message["model"] as? String, model != "<synthetic>", let usage = message["usage"] as? [String: Any] {
                    s.tokens[model, default: TokenUsage()] += tokenUsage(usage)
                }
            default: break
            }
        }
        if let a = lastAssistant {
            s.waiting = a.stop == "end_turn" && a.date >= (lastHuman ?? .distantPast)
        }
        return s
    }

    private static func note(_ s: inout SessionSummary, _ ts: Date) {
        s.startedAt = min(s.startedAt ?? ts, ts)
        s.lastAt = max(s.lastAt ?? ts, ts)
    }

    /// 真人输入：内容是字符串，或包含 text 块且不是工具结果。
    static func isHumanPrompt(_ obj: [String: Any], message: [String: Any]?) -> Bool {
        if obj["isMeta"] as? Bool == true || obj["isSidechain"] as? Bool == true { return false }
        if let origin = obj["turnOrigin"] as? String { return origin == "human" }
        guard let content = message?["content"] else { return false }
        if content is String { return true }
        guard let blocks = content as? [[String: Any]] else { return false }
        return !blocks.contains { $0["type"] as? String == "tool_result" } && blocks.contains { $0["type"] as? String == "text" }
    }

    static func tokenUsage(_ u: [String: Any]) -> TokenUsage {
        func int(_ k: String, _ d: [String: Any] = u) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
        var t = TokenUsage(input: int("input_tokens"), output: int("output_tokens"), cacheRead: int("cache_read_input_tokens"))
        if let c = u["cache_creation"] as? [String: Any] {
            t.cacheWrite5m = int("ephemeral_5m_input_tokens", c)
            t.cacheWrite1h = int("ephemeral_1h_input_tokens", c)
            let rest = int("cache_creation_input_tokens") - t.cacheWrite5m - t.cacheWrite1h
            if rest > 0 { t.cacheWrite5m += rest }
        } else {
            t.cacheWrite5m = int("cache_creation_input_tokens")
        }
        return t
    }
}
