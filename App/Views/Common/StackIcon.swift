import CodedogCore
import SwiftUI

/// 项目徽章用的图标：资源名（Stack/<slug>）、官方品牌色、显示名。
struct StackIcon {
    var asset: String
    var brand: Color
    var label: String

    /// 优先框架，其次语言；纯 JS 的服务/工具显示 Node.js。
    static func of(_ p: DiscoveredProject) -> StackIcon? {
        if let fw = p.frameworks.first { return framework(fw) }
        guard let stack = p.stacks.first else { return nil }
        if stack == .javascript, p.kind == .service || p.kind == .tool { return make("nodedotjs", 0x5FA04E, "Node.js") }
        return language(stack)
    }

    static func framework(_ f: Framework) -> StackIcon {
        switch f {
        case .nextjs: make("nextdotjs", 0x000000, f.displayName)
        case .nuxt: make("nuxt", 0x00DC82, f.displayName)
        case .astro: make("astro", 0xBC52EE, f.displayName)
        case .svelte: make("svelte", 0xFF3E00, f.displayName)
        case .angular: make("angular", 0x0F0F11, f.displayName)
        case .vue: make("vuedotjs", 0x4FC08D, f.displayName)
        case .react: make("react", 0x61DAFB, f.displayName)
        case .electron: make("electron", 0x47848F, f.displayName)
        case .tauri: make("tauri", 0x24C8D8, f.displayName)
        case .flutter: make("flutter", 0x02569B, f.displayName)
        case .nestjs: make("nestjs", 0xE0234E, f.displayName)
        case .express: make("express", 0x0A0A0A, f.displayName)
        case .fastapi: make("fastapi", 0x009688, f.displayName)
        case .django: make("django", 0x092E20, f.displayName)
        case .flask: make("flask", 0x3BABC3, f.displayName)
        case .springboot: make("springboot", 0x6DB33F, f.displayName)
        case .deno: make("deno", 0x000000, f.displayName)
        }
    }

    static func language(_ s: TechStack) -> StackIcon {
        switch s {
        case .swift: make("swift", 0xF05138, s.displayName)
        case .typescript: make("typescript", 0x3178C6, s.displayName)
        case .javascript: make("javascript", 0xF7DF1E, s.displayName)
        case .go: make("go", 0x00ADD8, s.displayName)
        case .python: make("python", 0x3776AB, s.displayName)
        case .rust: make("rust", 0x000000, s.displayName)
        case .java: make("openjdk", 0x000000, s.displayName)
        case .kotlin: make("kotlin", 0x7F52FF, s.displayName)
        case .ruby: make("ruby", 0xCC342D, s.displayName)
        case .php: make("php", 0x777BB4, s.displayName)
        case .dart: make("dart", 0x0175C2, s.displayName)
        case .cpp: make("cplusplus", 0x00599C, s.displayName)
        case .html: make("html5", 0xE34F26, s.displayName)
        case .shell: make("gnubash", 0x4EAA25, s.displayName)
        }
    }

    private static func make(_ slug: String, _ hex: UInt32, _ label: String) -> StackIcon {
        StackIcon(asset: "Stack/\(slug)", brand: Color(hex: hex), label: label)
    }

    /// 品牌色足够亮时用深色图形，否则用白色。
    var glyph: Color { brand.relativeLuminance > 0.6 ? Color.black.opacity(0.82) : .white }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// WCAG 相对亮度（0 黑 – 1 白）
    var relativeLuminance: Double {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        func lin(_ v: CGFloat) -> Double { let v = Double(v); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }
}
