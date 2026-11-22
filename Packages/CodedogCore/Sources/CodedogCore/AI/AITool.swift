import Foundation

/// 与项目有关联的 AI / 编辑工具。
public enum AITool: String, Codable, Sendable, CaseIterable, Hashable {
    case claudeCode, codex, cursor, vscode, windsurf, trae

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .vscode: "VS Code"
        case .windsurf: "Windsurf"
        case .trae: "Trae"
        }
    }

    /// 用于取图标的本机 App（按优先级）。
    public var iconBundleIDs: [String] {
        switch self {
        case .claudeCode: ["com.anthropic.claudefordesktop"]
        case .codex: ["com.openai.codex", "com.openai.chat"]
        case .cursor: ["com.todesktop.230313mzl4w4u92"]
        case .vscode: ["com.microsoft.VSCode"]
        case .windsurf: ["com.exafunction.windsurf"]
        case .trae: ["com.trae.app"]
        }
    }

    /// 是否是对话型 AI 智能体（有会话、token）。
    public var isAgent: Bool { self == .claudeCode || self == .codex }
}

/// token 用量。缓存写入区分 5 分钟与 1 小时（价格不同）。
public struct TokenUsage: Codable, Sendable, Hashable {
    public var input = 0
    public var output = 0
    public var cacheRead = 0
    public var cacheWrite5m = 0
    public var cacheWrite1h = 0

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
    }

    public var total: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }

    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(input: a.input + b.input, output: a.output + b.output, cacheRead: a.cacheRead + b.cacheRead,
                   cacheWrite5m: a.cacheWrite5m + b.cacheWrite5m, cacheWrite1h: a.cacheWrite1h + b.cacheWrite1h)
    }

    public static func += (a: inout TokenUsage, b: TokenUsage) { a = a + b }
}

/// 一个会话（一个日志文件）的摘要。
public struct SessionSummary: Codable, Sendable, Hashable {
    public var tool: AITool
    public var id: String
    public var file: String
    public var cwd: String?
    public var title: String?
    public var lastPrompt: String?
    /// AI 最后一句回复的开头（最多 200 字）
    public var lastReply: String?
    public var startedAt: Date?
    public var lastAt: Date?
    /// 按天（yyyy-MM-dd，本地时区）统计的 AI 回复数。
    public var days: [String: Int] = [:]
    public var tokens: [String: TokenUsage] = [:]
    /// AI 已经答完、在等用户回复。
    public var waiting = false
    /// 会话由谁发起。Codex 取 session_meta.originator（如 "Codex Desktop"、"codex_cli_rs"）。
    public var origin: String?

    public init(tool: AITool, id: String, file: String) {
        self.tool = tool
        self.id = id
        self.file = file
    }
}

/// 某个工具在某个项目上的汇总。
public struct ToolUsage: Codable, Sendable, Hashable {
    public var tool: AITool
    public var firstAt: Date?
    public var lastAt: Date?
    public var days: [String: Int] = [:]
    public var tokens: [String: TokenUsage] = [:]
    public var sessionCount = 0
    public var lastSession: SessionSummary?
    /// 最近 5 个会话（不含按天统计与 token 明细），按时间倒序。
    public var recentSessions: [SessionSummary] = []

    public init(tool: AITool) { self.tool = tool }

    public var waiting: Bool { lastSession?.waiting ?? false }

    mutating func merge(_ s: SessionSummary) {
        sessionCount += 1
        if let d = s.startedAt { firstAt = min(firstAt ?? d, d) }
        if let d = s.lastAt {
            if lastAt == nil || d > lastAt! { lastAt = d }
            var light = s
            light.days = [:]
            light.tokens = [:]
            if lastSession?.lastAt == nil || d > lastSession!.lastAt! { lastSession = light }
            recentSessions.append(light)
            recentSessions.sort { ($0.lastAt ?? .distantPast) > ($1.lastAt ?? .distantPast) }
            if recentSessions.count > 5 { recentSessions.removeLast(recentSessions.count - 5) }
        }
        days.merge(s.days, uniquingKeysWith: +)
        for (m, t) in s.tokens { tokens[m, default: TokenUsage()] += t }
    }
}

enum DayKey {
    static func string(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func parseISO(_ s: String) -> Date? {
        if let d = try? Date(s, strategy: .iso8601) { return d }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
