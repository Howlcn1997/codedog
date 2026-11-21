import Foundation
import Testing
@testable import CodedogCore

@Suite struct ClaudeCodeReaderTests {
    func line(_ obj: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: obj), as: UTF8.self)
    }

    func assistant(_ id: String, _ ts: String, stop: String?, usage: [String: Any]? = nil, model: String = "claude-opus-5-5") -> String {
        var message: [String: Any] = ["id": id, "role": "assistant", "model": model, "content": []]
        if let stop { message["stop_reason"] = stop }
        if let usage { message["usage"] = usage }
        return line(["type": "assistant", "timestamp": ts, "cwd": "/p/app", "sessionId": "s1", "message": message])
    }

    func human(_ ts: String, _ text: String = "hi") -> String {
        line(["type": "user", "timestamp": ts, "cwd": "/p/app", "sessionId": "s1", "turnOrigin": "human", "message": ["role": "user", "content": text]])
    }

    func toolResult(_ ts: String) -> String {
        line(["type": "user", "timestamp": ts, "cwd": "/p/app", "sessionId": "s1", "message": ["role": "user", "content": [["type": "tool_result", "content": "x"]]]])
    }

    @Test func summarizesSessionAndDedupesStreamedMessages() throws {
        let f = try Fixture()
        let usage: [String: Any] = ["input_tokens": 10, "output_tokens": 100, "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 300,
                                    "cache_creation": ["ephemeral_5m_input_tokens": 200, "ephemeral_1h_input_tokens": 100]]
        let text = [
            line(["type": "ai-title", "aiTitle": "重构界面", "sessionId": "s1"]),
            human("2026-11-20T10:00:00.000Z"),
            assistant("m1", "2026-11-20T10:00:05.000Z", stop: nil, usage: usage),
            assistant("m1", "2026-11-20T10:00:06.000Z", stop: "tool_use", usage: usage), // 同一消息的另一分片
            toolResult("2026-11-20T10:00:07.000Z"),
            assistant("m2", "2026-11-20T10:00:09.000Z", stop: "end_turn", usage: ["input_tokens": 1, "output_tokens": 1]),
            line(["type": "api-request-blob", "blob": String(repeating: "x", count: 1000)]),
        ].joined(separator: "\n")
        let path = try f.file("s1.jsonl", text)

        let s = ClaudeCodeReader.summarize(file: path)
        #expect(s.id == "s1")
        #expect(s.cwd == "/p/app")
        #expect(s.title == "重构界面")
        #expect(s.waiting)
        #expect(s.days.values.reduce(0, +) == 2)
        let t = try #require(s.tokens["claude-opus-5-5"])
        #expect(t.input == 11 && t.output == 101 && t.cacheRead == 1000)
        #expect(t.cacheWrite5m == 200 && t.cacheWrite1h == 100)
    }

    @Test func notWaitingAfterNewHumanPrompt() throws {
        let f = try Fixture()
        let path = try f.file("s.jsonl", [
            human("2026-11-20T10:00:00.000Z"),
            assistant("m1", "2026-11-20T10:00:05.000Z", stop: "end_turn"),
            human("2026-11-20T10:05:00.000Z", "继续"),
        ].joined(separator: "\n"))
        #expect(!ClaudeCodeReader.summarize(file: path).waiting)
    }

    @Test func notWaitingWhileToolRunning() throws {
        let f = try Fixture()
        let path = try f.file("s.jsonl", [
            human("2026-11-20T10:00:00.000Z"),
            assistant("m1", "2026-11-20T10:00:05.000Z", stop: "tool_use"),
        ].joined(separator: "\n"))
        #expect(!ClaudeCodeReader.summarize(file: path).waiting)
    }
}

@Suite struct CodexReaderTests {
    @Test func summarizesRollout() throws {
        let f = try Fixture()
        func l(_ o: [String: Any]) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: o), as: UTF8.self) }
        let path = try f.file("rollout.jsonl", [
            l(["timestamp": "2026-11-21T11:00:00.000Z", "type": "session_meta", "payload": ["id": "c1", "cwd": "/p/web"]]),
            l(["timestamp": "2026-11-21T11:00:01.000Z", "type": "event_msg", "payload": ["type": "thread_settings_applied", "thread_settings": ["model": "gpt-6.2-astra"]]]),
            l(["timestamp": "2026-11-21T11:00:02.000Z", "type": "event_msg", "payload": ["type": "task_started"]]),
            l(["timestamp": "2026-11-21T11:00:03.000Z", "type": "event_msg", "payload": ["type": "item_completed", "item": ["type": "UserMessage", "content": [["type": "text", "text": "帮我修登录页\n"]]]]]),
            l(["timestamp": "2026-11-21T11:00:05.000Z", "type": "event_msg", "payload": ["type": "token_count", "info": ["total_token_usage": ["input_tokens": 1000, "cached_input_tokens": 400, "output_tokens": 50]]]]),
            l(["timestamp": "2026-11-21T11:00:09.000Z", "type": "event_msg", "payload": ["type": "token_count", "info": ["total_token_usage": ["input_tokens": 1500, "cached_input_tokens": 600, "output_tokens": 80]]]]),
            l(["timestamp": "2026-11-21T11:00:10.000Z", "type": "event_msg", "payload": ["type": "task_complete", "last_agent_message": "完成了"]]),
        ].joined(separator: "\n"))
        let s = CodexReader.summarize(file: path)
        #expect(s.id == "c1" && s.cwd == "/p/web")
        #expect(s.title == "帮我修登录页")
        #expect(s.waiting)
        let t = try #require(s.tokens["gpt-6.2-astra"])
        #expect(t.input == 900 && t.cacheRead == 600 && t.output == 80)
    }
}

@Suite struct PricingTests {
    @Test func displayNames() {
        #expect(Pricing.displayName("claude-opus-5-5") == "Opus 5.5")
        #expect(Pricing.displayName("claude-fable-5-1") == "Fable 5.1")
        #expect(Pricing.displayName("claude-sonnet-4-6-20260101") == "Sonnet 4.6")
        #expect(Pricing.displayName("gpt-6.2-astra") == "gpt-6.2-astra")
    }

    @Test func costs() throws {
        // Opus 5.5：输入 $4、输出 $20、缓存读 $0.20、5 分钟写 $5、1 小时写 $8（每百万）
        let u = TokenUsage(input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000, cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000)
        let c = try #require(Pricing.cost(model: "claude-opus-5-5", usage: u))
        #expect(abs(c - (4 + 20 + 0.2 + 5 + 8)) < 0.0001)
        #expect(Pricing.cost(model: "gpt-6.2-astra", usage: u) == nil)
        // 前缀更具体的优先：fable-5-2 不应命中 fable-5
        #expect(Pricing.cost(model: "claude-fable-5-2", usage: TokenUsage(input: 1_000_000)) == 8)
    }
}

@Suite struct GitLogTests {
    @Test func countsOnlyMyCommits() {
        let log = "2026-11-21T10:00:00+08:00\u{1f}me@x.com\u{1f}feat: a\n2026-11-21T09:00:00+08:00\u{1f}other@x.com\u{1f}fix: b\n2026-11-20T09:00:00+08:00\u{1f}ME@x.com\u{1f}chore: c"
        let r = GitInspector.parseLog(log, myEmail: "me@x.com")
        #expect(r.commits.count == 3)
        #expect(r.commits.filter(\.mine).count == 2)
        #expect(r.days.values.reduce(0, +) == 2)
        #expect(GitInspector.parseLog(log, myEmail: "").days.values.reduce(0, +) == 3)
    }

    @Test func ownerMapping() {
        let projects: Set = ["/r/a", "/r/b"]
        #expect(AIIndex.owner(of: "/r/a/packages/x", in: projects) == "/r/a")
        #expect(AIIndex.owner(of: "/r/c", in: projects) == nil)
    }
}

@Suite struct UpdateCheckerTests {
    @Test func versionComparison() {
        #expect(UpdateChecker.isNewer("1.2.10", than: "1.2.9"))
        #expect(UpdateChecker.isNewer("2.0", than: "1.9.9"))
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0"))
        #expect(!UpdateChecker.isNewer("1.0.0-beta", than: "1.0.0"))
        #expect(!UpdateChecker.isNewer("0.3.5", than: "1.0.0"))
    }

    @Test func parsesReleaseAndSkipsPrerelease() {
        let ok: [String: Any] = ["tag_name": "v1.1.0", "html_url": "https://github.com/x/y/releases/tag/v1.1.0", "body": "notes", "draft": false, "prerelease": false]
        #expect(UpdateChecker.parse(ok)?.version == "1.1.0")
        var pre = ok
        pre["prerelease"] = true
        #expect(UpdateChecker.parse(pre) == nil)
    }
}
