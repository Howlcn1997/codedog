import Foundation

/// 根据项目文件推断技术栈、项目类型和描述。只读文件，不执行命令。
public enum ProjectClassifier {
    public struct Result: Sendable, Hashable {
        public var stacks: [TechStack] = []
        public var kind: ProjectKind = .other
        public var description: String?
        public var readmeFile: String?
        public var readmeText: String?
        public var dependencies: [String] = []
    }

    static let webDeps: Set<String> = ["react", "vue", "next", "nuxt", "svelte", "@sveltejs/kit", "vite", "astro", "@angular/core", "solid-js", "@remix-run/react", "preact", "umi", "@umijs/max", "gatsby", "webpack"]
    static let appDeps: Set<String> = ["electron", "@tauri-apps/api", "@tauri-apps/cli", "react-native", "expo"]
    static let serviceDeps: Set<String> = ["express", "koa", "fastify", "@nestjs/core", "hono", "@hapi/hapi", "egg", "midway"]
    static let pyServiceDeps = ["fastapi", "flask", "django", "uvicorn", "aiohttp", "tornado", "sanic"]

    public static func classify(path: String, markers: [String]) -> Result {
        var r = Result()
        let has = Set(markers)
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        func read(_ file: String) -> String? {
            guard let data = fm.contents(atPath: path + "/" + file), data.count < 2_000_000 else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        var kind: ProjectKind?

        // Apple
        if markers.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            r.stacks.append(.swift); kind = .app
        }
        if has.contains("Package.swift") {
            if !r.stacks.contains(.swift) { r.stacks.append(.swift) }
            kind = kind ?? .library
        }

        // Node
        if has.contains("package.json"), let text = read("package.json"),
           let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] {
            let runtime = Set(((json["dependencies"] as? [String: Any]) ?? [:]).keys)
            let deps = runtime.union(((json["devDependencies"] as? [String: Any]) ?? [:]).keys)
            r.dependencies += deps.sorted()
            r.stacks.append(deps.contains("typescript") || names.contains("tsconfig.json") ? .typescript : .javascript)
            r.description = (json["description"] as? String).flatMap(nonEmpty)
            if kind == nil {
                if !deps.isDisjoint(with: appDeps) { kind = .app }
                else if !deps.isDisjoint(with: webDeps) { kind = .web }
                else if !runtime.isDisjoint(with: serviceDeps) { kind = .service }
                else if json["bin"] != nil { kind = .tool }
                else if json["main"] != nil || json["exports"] != nil { kind = .library }
            }
        } else if has.contains("deno.json") {
            r.stacks.append(.typescript)
        }

        // Go
        if has.contains("go.mod") || has.contains("go.work") {
            r.stacks.append(.go)
            if let mod = read("go.mod") { r.dependencies += goDependencies(mod) }
            kind = kind ?? (names.contains("cmd") || names.contains("main.go") && !names.contains("internal") ? .tool : .service)
        }

        // Python
        if has.contains("pyproject.toml") || has.contains("requirements.txt") || has.contains("setup.py") || has.contains("Pipfile") {
            r.stacks.append(.python)
            let text = [read("pyproject.toml"), read("requirements.txt"), read("Pipfile")].compactMap { $0 }.joined(separator: "\n").lowercased()
            if r.description == nil, let pyproject = read("pyproject.toml") { r.description = tomlString(pyproject, key: "description") }
            r.dependencies += pythonDependencies(requirements: read("requirements.txt"), pyproject: read("pyproject.toml"))
            if kind == nil {
                if pyServiceDeps.contains(where: { text.contains($0) }) { kind = .service }
                else if text.contains("streamlit") || text.contains("gradio") { kind = .web }
                else { kind = .tool }
            }
        }

        // Rust
        if has.contains("Cargo.toml") {
            r.stacks.append(.rust)
            if let cargo = read("Cargo.toml") {
                if r.description == nil { r.description = tomlString(cargo, key: "description") }
                r.dependencies += cargoDependencies(cargo)
            }
            if kind == nil {
                let src = (try? fm.contentsOfDirectory(atPath: path + "/src")) ?? []
                kind = src.contains("main.rs") ? .tool : .library
            }
        }

        // JVM
        if has.contains("pom.xml") || has.contains("build.gradle") || has.contains("build.gradle.kts") {
            r.stacks.append(has.contains("build.gradle.kts") ? .kotlin : .java)
            let gradle = (read("build.gradle") ?? "") + (read("build.gradle.kts") ?? "")
            kind = kind ?? (gradle.contains("com.android.application") ? .app : .service)
        }

        if has.contains("Gemfile") { r.stacks.append(.ruby); kind = kind ?? (names.contains("config.ru") ? .service : .tool) }
        if has.contains("composer.json") { r.stacks.append(.php); kind = kind ?? .web }
        if has.contains("pubspec.yaml") { r.stacks.append(.dart); kind = kind ?? .app }
        if has.contains("CMakeLists.txt") { r.stacks.append(.cpp); kind = kind ?? .tool }

        if has.contains("index.html") {
            if r.stacks.isEmpty { r.stacks.append(.html) }
            kind = kind ?? .web
        }

        // 只有 .git 的仓库：看看是不是脚本集合。
        if kind == nil {
            let scriptExts: Set<String> = ["sh", "zsh", "py", "js", "rb", "pl"]
            if names.contains(where: { scriptExts.contains(($0 as NSString).pathExtension) }) { kind = .tool }
            if names.contains(where: { ($0 as NSString).pathExtension.lowercased() == "html" }) {
                kind = .web
                if r.stacks.isEmpty { r.stacks.append(.html) }
            }
        }
        r.kind = kind ?? .other

        r.readmeFile = names.first { $0.range(of: #"^readme(\.(md|markdown|txt|rst))?$"#, options: [.regularExpression, .caseInsensitive]) != nil }
        if let readme = r.readmeFile, let text = read(readme) {
            r.readmeText = text.count > 32_768 ? String(text.prefix(32_768)) : text
            if r.description == nil { r.description = readmeSummary(text) }
        }
        r.dependencies = Array(NSOrderedSet(array: r.dependencies)) as? [String] ?? r.dependencies
        return r
    }

    static func goDependencies(_ mod: String) -> [String] {
        mod.split(separator: "\n").compactMap { line in
            let m = line.firstMatch(of: /^\s*(?:require\s+)?([\w.\-\/]+)\s+v[^\s]+/)
            return m.map { String($0.1) }
        }
    }

    static func pythonDependencies(requirements: String?, pyproject: String?) -> [String] {
        var out: [String] = []
        for line in (requirements ?? "").split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#"), !t.hasPrefix("-") else { continue }
            if let m = t.firstMatch(of: /^[A-Za-z0-9_.\-\[\]]+/) { out.append(String(m.0).components(separatedBy: "[")[0]) }
        }
        if let py = pyproject, let start = py.range(of: #"dependencies\s*=\s*\["#, options: .regularExpression),
           let end = py[start.upperBound...].firstIndex(of: "]") {
            for m in py[start.upperBound..<end].matches(of: /["']([A-Za-z0-9_.\-]+)/) { out.append(String(m.1)) }
        }
        return out
    }

    static func cargoDependencies(_ cargo: String) -> [String] {
        var out: [String] = [], inDeps = false
        for line in cargo.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") { inDeps = t.contains("dependencies]"); continue }
            if inDeps, let m = t.firstMatch(of: /^([A-Za-z0-9_\-]+)\s*=/) { out.append(String(m.1)) }
        }
        return out
    }

    static func nonEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func tomlString(_ toml: String, key: String) -> String? {
        for line in toml.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key else { continue }
            return nonEmpty(parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
        }
        return nil
    }

    /// README 中第一段正文（跳过标题、徽章、HTML、代码块），截断到 140 字。
    static func readmeSummary(_ text: String) -> String? {
        var inCode = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inCode.toggle(); continue }
            if inCode || line.isEmpty || line.hasPrefix("#") || line.hasPrefix("<") || line.hasPrefix("[![") || line.hasPrefix("![")
                || line.hasPrefix("|") || line.hasPrefix("---") || line.hasPrefix("===") || line.hasPrefix(">") { continue }
            var clean = line.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            clean = clean.replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
            clean = clean.replacingOccurrences(of: #"^[-+] "#, with: "", options: .regularExpression)
            guard let t = nonEmpty(clean) else { continue }
            return t.count > 140 ? String(t.prefix(140)) + "…" : t
        }
        return nil
    }
}
