import Foundation
import Combine

/// 语言选项：跟随系统 / 英文 / 中文
enum AppLanguage: String, CaseIterable, Identifiable, Hashable {
    case system, english, chinese
    var id: String { rawValue }
}

/// 轻量多语言层（纯 SwiftPM，无 Xcode .lproj 体系）
/// - 默认显示英文；支持「跟随系统」（系统中文→中文，否则英文）；可手动切换
/// - 未命中翻译时一律回退英文，保证不出现空白串
final class L10n: ObservableObject, @unchecked Sendable {
    static let shared = L10n()

    private let defaultsKey = "PortWatcher.Language"

    /// 当前选择的语言（UI 切换即写 UserDefaults，触发所有视图重渲染）
    @Published var language: AppLanguage

    private init() {
        let raw = UserDefaults.standard.string(forKey: "PortWatcher.Language") ?? "system"
        self.language = AppLanguage(rawValue: raw) ?? .system
    }

    /// 跟随系统时的判定：系统语言以 zh 开头视为中文，其余一律英文
    private var systemIsChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
    }

    /// 最终生效的语言码：en / zh
    private var resolvedCode: String {
        switch language {
        case .system:  return systemIsChinese ? "zh" : "en"
        case .english: return "en"
        case .chinese: return "zh"
        }
    }

    /// 给 RelativeDateTimeFormatter 等用的 Locale
    var locale: Locale {
        switch language {
        case .system:  return Locale.current
        case .english: return Locale(identifier: "en")
        case .chinese: return Locale(identifier: "zh_Hans")
        }
    }

    /// 当前生效语言码（en/zh），供数据层按语言选值
    var langCode: String { resolvedCode }

    private let table: [String: [String: String]] = [
        // 顶栏 / 通用
        "refresh":           ["en": "Refresh",            "zh": "刷新"],
        "autoRefresh":       ["en": "Auto Refresh",       "zh": "自动刷新"],
        "settings":          ["en": "Settings",           "zh": "设置"],
        "notRefreshed":      ["en": "Not refreshed",      "zh": "未刷新"],

        // 筛选栏
        "filterAll":         ["en": "All",                "zh": "全部"],
        "filterCommon":      ["en": "Favorites",          "zh": "常用"],
        "filterLocal":       ["en": "Local only",         "zh": "仅本地"],
        "filterLaunchd":     ["en": "Auto-launch",        "zh": "自启动"],
        "searchPlaceholder": ["en": "Search port/process", "zh": "搜索 端口/进程"],

        // 设置区
        "settingsTitle":     ["en": "Settings",           "zh": "设置"],
        "launchAtLogin":     ["en": "Launch at login (start on boot)", "zh": "登录时启动（开机自动运行）"],
        "quitApp":           ["en": "Quit PortWatcher",   "zh": "退出 PortWatcher"],
        "language":          ["en": "Language",           "zh": "语言"],
        "langSystem":        ["en": "System",             "zh": "跟随系统"],
        "langEnglish":       ["en": "English",            "zh": "English"],
        "langChinese":       ["en": "Chinese",            "zh": "中文"],

        // 资源条
        "mem":               ["en": "Memory",             "zh": "内存"],
        "disk":              ["en": "Disk",               "zh": "硬盘"],
        "readingResources":  ["en": "Reading system resources…", "zh": "读取系统资源…"],

        // 端口列表
        "noMatch":           ["en": "No matching ports",  "zh": "没有匹配的端口"],

        // 历史
        "historyTitle":      ["en": "Action history (last 48 hours)", "zh": "操作历史（近 48 小时）"],
        "clear":             ["en": "Clear",              "zh": "清空"],
        "noHistory":         ["en": "No actions yet",     "zh": "暂无操作记录"],

        // 折叠行标签
        "tagLocal":          ["en": "Local",              "zh": "本地"],
        "tagPublic":         ["en": "Public",             "zh": "对外"],
        "tagAutoLaunch":     ["en": "Auto-launch",        "zh": "自启动"],
        "tagRestart":        ["en": "⟳ Restart",          "zh": "⟳ 重启"],
        "favRemove":         ["en": "Remove from favorites", "zh": "取消常用"],
        "favAdd":            ["en": "Add to favorites",   "zh": "设为常用"],
        "openInBrowserHelp": ["en": "Open in browser %@", "zh": "在浏览器打开 %@"],

        // 展开详情
        "alias":             ["en": "Alias",              "zh": "备注名"],
        "aliasPlaceholder":  ["en": "Alias, e.g. My website", "zh": "备注业务，如：我的网站"],
        "save":              ["en": "Save",               "zh": "保存"],
        "listenAddr":        ["en": "Listen address",     "zh": "监听地址"],
        "user":              ["en": "User",               "zh": "用户"],
        "memUsage":          ["en": "Memory",             "zh": "内存占用"],
        "workDir":           ["en": "Working dir",        "zh": "工作目录"],
        "executable":        ["en": "Executable",         "zh": "可执行文件"],
        "sourceLaunchd":     ["en": "Source: launchd",   "zh": "启动源头：launchd"],
        "viewPlist":         ["en": "View plist",         "zh": "查看 plist"],
        "sourceUser":        ["en": "Source: user process (not launchd managed)", "zh": "启动源头：用户进程（非 launchd 托管）"],
        "fullCommand":       ["en": "Full command",       "zh": "完整命令"],
        "processLogs":       ["en": "Process logs",       "zh": "进程日志"],
        "loading":           ["en": "Loading…",           "zh": "加载中…"],
        "loadLogs":          ["en": "Load recent logs",   "zh": "加载最近日志"],
        "restart":           ["en": "Restart",            "zh": "重启"],
        "forceStop":         ["en": "Force stop",         "zh": "强制停止"],
        "showInFinder":      ["en": "Show in Finder",     "zh": "在 Finder 显示"],
        "openInBrowser":     ["en": "Open in browser",    "zh": "浏览器打开"],
        "copyCommand":       ["en": "Copy command",       "zh": "复制命令"],
        "confirmForceStop":  ["en": "Confirm force stop this process?", "zh": "确认强制停止该进程？"],
        "cancel":            ["en": "Cancel",             "zh": "取消"],

        // 变更摘要（数据层拼装）
        "portRestarted":     ["en": "%@ restarted",       "zh": "%@ 重启"],
        "portAdded":         ["en": "%@ added",           "zh": "%@ 新增"],
        "portClosed":        ["en": "%@ closed",          "zh": "%@ 关闭"],
        "loadedPorts":       ["en": "Loaded %d listening ports", "zh": "已加载 %d 个监听端口"],
        "added":             ["en": "Added %d",           "zh": "新增 %d"],
        "closed":            ["en": "Closed %d",          "zh": "关闭 %d"],
        "restarted":         ["en": "Restarted %d",       "zh": "重启 %d"],
        "eventSep":          ["en": ": ",                "zh": "："],

        // Actions 历史记录
        "launchFailed":      ["en": "Launch failed: %@", "zh": "启动失败: %@"],
        "actRestart":        ["en": "Restart",            "zh": "重启"],
        "actForceStop":      ["en": "Force stop",         "zh": "强制停止"],
        "restartedViaLaunchctl": ["en": "Restarted via launchctl kickstart", "zh": "已通过 launchctl kickstart 重启"],
        "restartedViaCmd":   ["en": "Restarted via original command", "zh": "已按原命令重新拉起进程"],
        "sigkillSent":       ["en": "SIGKILL sent",       "zh": "已发送 SIGKILL"],
        "noLogs":            ["en": "No logs for this process in the last 20 minutes", "zh": "该进程近 20 分钟无日志"],
        "logReadFailed":     ["en": "Failed to read logs: %@", "zh": "读取日志失败: %@"],

        // 错误提示
        "loginItemFailed":   ["en": "Failed to set login item: %@\n(If launched from a temporary directory, move PortWatcher.app to /Applications and retry)",
                              "zh": "登录项设置失败：%@\n（若从临时目录启动，请将 PortWatcher.app 移动到 /Applications 后重试）"],
        "plistReadFailed":   ["en": "Unable to read: %@", "zh": "无法读取：%@"],

        // AppDelegate 菜单 / 关于
        "aboutPortWatcher":  ["en": "About PortWatcher",  "zh": "关于 PortWatcher"],
        "quitPortWatcher":   ["en": "Quit PortWatcher",   "zh": "退出 PortWatcher"],
        "aboutText":         ["en": "Menu-bar port monitor\nReal-time view of local listening ports, processes and system resource usage\n\nAuthor: 2winter",
                              "zh": "顶部栏端口监视器\n实时查看本机监听端口、进程与系统资源占用\n\n作者：2winter"],
    ]

    /// 取翻译；未命中回退英文
    func loc(_ key: String) -> String {
        return table[key]?[resolvedCode] ?? table[key]?["en"] ?? key
    }

    /// 带参数的翻译：String(format:) 包装
    func locf(_ key: String, _ args: CVarArg...) -> String {
        return String(format: loc(key), arguments: args)
    }
}
