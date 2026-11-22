import AppKit
import Foundation

/// 界面语言：跟随系统 / 简体中文 / 繁体中文 / English。
/// 写入本 App 的 AppleLanguages（与系统设置里"App 语言"相同的机制），重启后生效。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en

    var id: String { rawValue }

    /// 语言名用它自己的文字书写，切错了也认得出来。
    var title: String {
        switch self {
        case .system: String(localized: "跟随系统")
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文"
        case .en: "English"
        }
    }

    private static let key = "AppleLanguages"

    /// 用户在设置里选的语言（只读本 App 自己的设置，不读全局的系统语言列表）。
    static var selected: AppLanguage {
        get {
            let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            guard let first = (domain?[key] as? [String])?.first else { return .system }
            return allCases.first { $0 != .system && first.hasPrefix($0.rawValue) } ?? .system
        }
        set {
            if newValue == .system {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set([newValue.rawValue], forKey: key)
            }
        }
    }

    /// 本次启动实际使用的界面语言，切换后到重启前不变。
    static let launched: String = Bundle.main.preferredLocalizations.first ?? "zh-Hans"

    /// 与界面语言一致的 Locale（保留系统的地区），用于日期、数字格式。
    /// 否则界面是英文时，日期仍会按系统语言显示成"11月22日"。
    static let locale: Locale = {
        let region = Locale.current.region?.identifier
        return Locale(identifier: region.map { "\(launched)_\($0)" } ?? launched)
    }()

    /// 选中的语言与正在使用的不同，需要重启才能生效。
    static var needsRelaunch: Bool {
        let target = selected == .system ? systemPreferred : selected.rawValue
        return target != launched
    }

    /// 跟随系统时会用到的语言：按系统首选语言在本 App 支持的语言里挑。
    private static var systemPreferred: String {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[key] as? [String] ?? Locale.preferredLanguages
        return Bundle.preferredLocalizations(from: Bundle.main.localizations.filter { $0 != "Base" }, forPreferences: global).first ?? "zh-Hans"
    }

    /// 等当前进程退出后重新打开 App。
    @MainActor static func relaunch() {
        let task = Process()
        task.executableURL = URL(filePath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                          Bundle.main.bundleURL.path(percentEncoded: false)]
        try? task.run()
        NSApp.terminate(nil)
    }
}

import SwiftUI

extension LocalizedStringKey {
    /// 已经是最终文字（项目名、路径、本地化好的字符串）时原样显示，不再查表。
    static func verbatim(_ s: String) -> LocalizedStringKey { "\(s)" }
}
