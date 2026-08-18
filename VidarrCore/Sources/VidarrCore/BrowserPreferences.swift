import Foundation
import CoreGraphics

public final class BrowserPreferences {
    public static var shared = BrowserPreferences()
    public static let didChangeNotification = Notification.Name("BrowserPreferencesDidChange")

    public enum GestureOption: String, CaseIterable, Hashable {
        case nextTab
        case previousTab
        case closeTab
        case closeAllTabs
        case restoreClosedTab
        case reload
        case reloadAll
        case back
        case forward
        case search
        case newTab

        public var title: String {
            switch self {
            case .nextTab: return "次のタブ"
            case .previousTab: return "前のタブ"
            case .closeTab: return "現在のタブを閉じる"
            case .closeAllTabs: return "すべてのタブを閉じる"
            case .restoreClosedTab: return "閉じたタブを復元"
            case .reload: return "現在のタブを再読み込み"
            case .reloadAll: return "すべてのタブを再読み込み"
            case .back: return "戻る"
            case .forward: return "進む"
            case .search: return "検索"
            case .newTab: return "新規タブ"
            }
        }

        public var gestureLabel: String {
            switch self {
            case .nextTab: return "→"
            case .previousTab: return "←"
            case .closeTab: return "L（↓→）"
            case .closeAllTabs: return "LL（↓→↓→）"
            case .restoreClosedTab: return "U（↓→↑）"
            case .reload: return "O（↑→↓←）"
            case .reloadAll: return "◎"
            case .back: return "↑→"
            case .forward: return "↑←"
            case .search: return "S（斜めに折り返す）"
            case .newTab: return "↓←"
            }
        }

        public var helpText: String {
            switch self {
            case .nextTab, .previousTab:
                return "左右に払ってタブを切り替えます。"
            case .closeTab:
                return "L 字に書いて、開いているタブを閉じます。"
            case .closeAllTabs:
                return "L を 2 回続けて書いて、保護されていないタブをまとめて閉じます。"
            case .restoreClosedTab:
                return "U 字に書いて、最後に閉じたタブを戻します。"
            case .reload:
                return "O 字で、今のタブを再読み込みします。"
            case .reloadAll:
                return "円を続けて 2 周書いて、すべてのタブを再読み込みします。"
            case .back:
                return "上に払ってから右へ曲げて、ひとつ前のページへ戻ります。"
            case .forward:
                return "上に払ってから左へ曲げて、次のページへ進みます。"
            case .search:
                return "斜めに折り返す S 字を書いて、検索 UI を開きます。"
            case .newTab:
                return "左下へ曲げて、新しいタブを開きます。"
            }
        }

        public var strokePoints: [CGPoint] {
            switch self {
            case .nextTab:
                return [CGPoint(x: 0.18, y: 0.5), CGPoint(x: 0.82, y: 0.5)]
            case .previousTab:
                return [CGPoint(x: 0.82, y: 0.5), CGPoint(x: 0.18, y: 0.5)]
            case .closeTab:
                return [CGPoint(x: 0.3, y: 0.18), CGPoint(x: 0.3, y: 0.78), CGPoint(x: 0.78, y: 0.78)]
            case .closeAllTabs:
                return [
                    CGPoint(x: 0.24, y: 0.16),
                    CGPoint(x: 0.24, y: 0.54),
                    CGPoint(x: 0.5, y: 0.54),
                    CGPoint(x: 0.5, y: 0.84),
                    CGPoint(x: 0.76, y: 0.84)
                ]
            case .restoreClosedTab:
                return [CGPoint(x: 0.24, y: 0.18), CGPoint(x: 0.24, y: 0.72), CGPoint(x: 0.78, y: 0.72), CGPoint(x: 0.78, y: 0.18)]
            case .reload:
                return [
                    CGPoint(x: 0.5, y: 0.16),
                    CGPoint(x: 0.72, y: 0.22),
                    CGPoint(x: 0.84, y: 0.5),
                    CGPoint(x: 0.72, y: 0.78),
                    CGPoint(x: 0.5, y: 0.84),
                    CGPoint(x: 0.28, y: 0.78),
                    CGPoint(x: 0.16, y: 0.5),
                    CGPoint(x: 0.28, y: 0.22),
                    CGPoint(x: 0.5, y: 0.16)
                ]
            case .reloadAll:
                return [
                    CGPoint(x: 0.28, y: 0.34), CGPoint(x: 0.56, y: 0.24), CGPoint(x: 0.72, y: 0.46), CGPoint(x: 0.58, y: 0.72), CGPoint(x: 0.34, y: 0.64),
                    CGPoint(x: 0.44, y: 0.34), CGPoint(x: 0.68, y: 0.28), CGPoint(x: 0.78, y: 0.5), CGPoint(x: 0.64, y: 0.7), CGPoint(x: 0.44, y: 0.62)
                ]
            case .back:
                return [CGPoint(x: 0.3, y: 0.78), CGPoint(x: 0.3, y: 0.24), CGPoint(x: 0.78, y: 0.24)]
            case .forward:
                return [CGPoint(x: 0.7, y: 0.78), CGPoint(x: 0.7, y: 0.24), CGPoint(x: 0.22, y: 0.24)]
            case .search:
                // GestureRecognizer の S テンプレートと同じ、上下を斜めに
                // 折り返す形。角張った横・縦・横の記号にはしない。
                return [
                    CGPoint(x: 0.17, y: 0.86),
                    CGPoint(x: 0.4, y: 0.94),
                    CGPoint(x: 0.71, y: 0.78),
                    CGPoint(x: 0.88, y: 0.6),
                    CGPoint(x: 0.58, y: 0.48),
                    CGPoint(x: 0.31, y: 0.35),
                    CGPoint(x: 0.13, y: 0.15)
                ]
            case .newTab:
                return [CGPoint(x: 0.72, y: 0.22), CGPoint(x: 0.72, y: 0.74), CGPoint(x: 0.22, y: 0.74)]
            }
        }
    }

    public enum GesturePattern: String, CaseIterable, Hashable {
        case left = "Left"
        case right = "Right"
        case downRight = "DownRight"
        case downRightDownRight = "DownRightDownRight"
        case u = "U"
        case o = "O"
        case oo = "OO"
        case upRight = "UpRight"
        case upLeft = "UpLeft"
        case downLeft = "DownLeft"
        case s = "S"

        public var label: String {
            switch self {
            case .left: return "←"
            case .right: return "→"
            case .downRight: return "↓→"
            case .downRightDownRight: return "↓→↓→"
            case .u: return "U"
            case .o: return "O"
            case .oo: return "◎"
            case .upRight: return "↑→"
            case .upLeft: return "↑←"
            case .downLeft: return "↓←"
            case .s: return "S"
            }
        }

        public var defaultAction: GestureOption {
            switch self {
            case .left: return .nextTab
            case .right: return .previousTab
            case .downRight: return .closeTab
            case .downRightDownRight: return .closeAllTabs
            case .u: return .restoreClosedTab
            case .o: return .reload
            case .oo: return .reloadAll
            case .upRight: return .back
            case .upLeft: return .forward
            case .downLeft: return .newTab
            case .s: return .search
            }
        }

        public var strokePoints: [CGPoint] { defaultAction.strokePoints }
    }

    public enum GestureInputKind: String, CaseIterable, Hashable {
        case touchSurface
        case rightDrag

        public var displayName: String {
            switch self {
            case .touchSurface: return "トラックパッド / Magic Mouse"
            case .rightDrag: return "マウスの右ドラッグ"
            }
        }
    }

    public enum PreferredContentLanguage: String, CaseIterable {
        case system
        case japanese
        case english

        public var displayName: String {
            switch self {
            case .system: return "System Default"
            case .japanese: return "Japanese"
            case .english: return "English"
            }
        }

        public var navigatorLanguage: String? {
            switch self {
            case .system: return nil
            case .japanese: return "ja-JP"
            case .english: return "en-US"
            }
        }
    }

    public enum GestureSensitivity: String, CaseIterable {
        case low
        case normal
        case high

        public var displayName: String {
            switch self {
            case .low: return "Low"
            case .normal: return "Normal"
            case .high: return "High"
            }
        }

        // >1.0 makes gesture capture easier, <1.0 makes stricter.
        public var multiplier: CGFloat {
            switch self {
            case .low: return 0.85
            case .normal: return 1.0
            case .high: return 1.18
            }
        }
    }

    public struct AppleAccount: Equatable {
        public let userID: String
        public let email: String?
        public let displayName: String?

        public init(userID: String, email: String?, displayName: String?) {
            self.userID = userID
            self.email = email
            self.displayName = displayName
        }
    }

    private enum Key {
        static let homePageURL = "prefs.homePageURL"
        static let searchTemplate = "prefs.searchTemplate"
        static let updatesEnabled = "prefs.updatesEnabled"
        static let preferredContentLanguage = "prefs.preferredContentLanguage"
        static let preferredDownloadDirectoryBookmark = "prefs.preferredDownloadDirectoryBookmark"
        static let preferredDownloadDirectoryPath = "prefs.preferredDownloadDirectoryPath"
        static let gestureSensitivity = "prefs.gestureSensitivity"
        static let gestureSensitivityPrefix = "prefs.gestureSensitivity.device."
        static let gestureActionPrefix = "prefs.gestureAction."
        static let antiTrackingEnabled = "prefs.antiTrackingEnabled"
        static let contentBlockingEnabled = "prefs.contentBlockingEnabled"
        static let contentBlockingDisabledHosts = "prefs.contentBlockingDisabledHosts"
        static let harmfulSiteAllowedHosts = "prefs.harmfulSiteAllowedHosts"
        static let popupBlockingEnabled = "prefs.popupBlockingEnabled"
        static let harmfulSiteWarningEnabled = "prefs.harmfulSiteWarningEnabled"
        static let ephemeralModeEnabled = "prefs.ephemeralModeEnabled"
        static let sendDoNotTrack = "prefs.sendDoNotTrack"
        static let restoreClosedTabPageHistory = "prefs.restoreClosedTabPageHistory"
        static let reopenTabsOnLaunch = "prefs.reopenTabsOnLaunch"
        static let tabSleepingEnabled = "prefs.tabSleepingEnabled"
        static let tabSleepingMinutes = "prefs.tabSleepingMinutes"
        static let appleAccountUserID = "prefs.appleAccountUserID"
        static let appleAccountEmail = "prefs.appleAccountEmail"
        static let appleAccountDisplayName = "prefs.appleAccountDisplayName"
        static let gestureEnabledPrefix = "prefs.gestureEnabled."
    }

    private let defaults: UserDefaults
    private var isBatchUpdating = false
    private var needsNotifyChanged = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.homePageURL: "https://search.fenrir-inc.com/",
            Key.searchTemplate: "https://search.fenrir-inc.com/?q={query}",
            Key.updatesEnabled: true,
            Key.preferredContentLanguage: PreferredContentLanguage.system.rawValue,
            Key.gestureSensitivity: GestureSensitivity.normal.rawValue,
            Key.antiTrackingEnabled: true,
            Key.contentBlockingEnabled: true,
            Key.contentBlockingDisabledHosts: [],
            Key.harmfulSiteAllowedHosts: [],
            Key.popupBlockingEnabled: true,
            Key.harmfulSiteWarningEnabled: true,
            Key.ephemeralModeEnabled: false,
            Key.sendDoNotTrack: true,
            Key.restoreClosedTabPageHistory: true,
            Key.reopenTabsOnLaunch: true,
            Key.tabSleepingEnabled: true,
            Key.tabSleepingMinutes: 30
        ])
    }

    public static func useSharedDefaults(_ defaults: UserDefaults) {
        shared = BrowserPreferences(defaults: defaults)
        NotificationCenter.default.post(name: didChangeNotification, object: shared)
    }

    public var homePageURLString: String {
        get { defaults.string(forKey: Key.homePageURL) ?? "https://search.fenrir-inc.com/" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed.isEmpty ? "https://search.fenrir-inc.com/" : trimmed, forKey: Key.homePageURL)
            notifyChanged()
        }
    }

    public var searchTemplate: String {
        get { defaults.string(forKey: Key.searchTemplate) ?? "https://search.fenrir-inc.com/?q={query}" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed.isEmpty ? "https://search.fenrir-inc.com/?q={query}" : trimmed, forKey: Key.searchTemplate)
            notifyChanged()
        }
    }

    public var updatesEnabled: Bool {
        get { defaults.bool(forKey: Key.updatesEnabled) }
        set {
            defaults.set(newValue, forKey: Key.updatesEnabled)
            notifyChanged()
        }
    }

    public var preferredContentLanguage: PreferredContentLanguage {
        get {
            let raw = defaults.string(forKey: Key.preferredContentLanguage) ?? PreferredContentLanguage.system.rawValue
            return PreferredContentLanguage(rawValue: raw) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.preferredContentLanguage)
            notifyChanged()
        }
    }

    public var preferredDownloadDirectoryPath: String? {
        defaults.string(forKey: Key.preferredDownloadDirectoryPath)
    }

    public func preferredDownloadDirectoryURL() -> URL? {
        guard let data = defaults.data(forKey: Key.preferredDownloadDirectoryBookmark) else { return nil }
        var isStale = false
#if os(macOS)
        let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
#else
        let resolutionOptions: URL.BookmarkResolutionOptions = []
#endif
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        if isStale {
            _ = try? setPreferredDownloadDirectory(url)
        }
        return url
    }

    @discardableResult
    public func setPreferredDownloadDirectory(_ url: URL?) throws -> URL? {
        if let url {
#if os(macOS)
            let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
#else
            let bookmarkOptions: URL.BookmarkCreationOptions = []
#endif
            let bookmark = try url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Key.preferredDownloadDirectoryBookmark)
            defaults.set(url.path, forKey: Key.preferredDownloadDirectoryPath)
            notifyChanged()
            return url
        } else {
            defaults.removeObject(forKey: Key.preferredDownloadDirectoryBookmark)
            defaults.removeObject(forKey: Key.preferredDownloadDirectoryPath)
            notifyChanged()
            return nil
        }
    }

    public var gestureSensitivity: GestureSensitivity {
        get {
            let raw = defaults.string(forKey: Key.gestureSensitivity) ?? GestureSensitivity.normal.rawValue
            return GestureSensitivity(rawValue: raw) ?? .normal
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.gestureSensitivity)
            notifyChanged()
        }
    }

    public func gestureSensitivity(for input: GestureInputKind) -> GestureSensitivity {
        let key = Key.gestureSensitivityPrefix + input.rawValue
        guard let raw = defaults.string(forKey: key) else { return gestureSensitivity }
        return GestureSensitivity(rawValue: raw) ?? gestureSensitivity
    }

    public func setGestureSensitivity(_ sensitivity: GestureSensitivity, for input: GestureInputKind) {
        defaults.set(sensitivity.rawValue, forKey: Key.gestureSensitivityPrefix + input.rawValue)
        notifyChanged()
    }

    public func gestureAction(for pattern: GesturePattern) -> GestureOption? {
        let key = Key.gestureActionPrefix + pattern.rawValue
        if let raw = defaults.string(forKey: key) {
            return GestureOption(rawValue: raw)
        }
        return isGestureEnabled(pattern.defaultAction) ? pattern.defaultAction : nil
    }

    public func setGestureAction(_ action: GestureOption?, for pattern: GesturePattern) {
        let key = Key.gestureActionPrefix + pattern.rawValue
        if let action {
            defaults.set(action.rawValue, forKey: key)
        } else {
            defaults.set("disabled", forKey: key)
        }
        notifyChanged()
    }

    public var enabledGesturePatternNames: Set<String> {
        Set(GesturePattern.allCases.compactMap { gestureAction(for: $0) == nil ? nil : $0.rawValue })
    }

    public func gesturePatterns(assignedTo action: GestureOption) -> [GesturePattern] {
        GesturePattern.allCases.filter { gestureAction(for: $0) == action }
    }

    public func isGestureEnabled(_ option: GestureOption) -> Bool {
        if defaults.object(forKey: Key.gestureEnabledPrefix + option.rawValue) == nil {
            return true
        }
        return defaults.bool(forKey: Key.gestureEnabledPrefix + option.rawValue)
    }

    public func setGestureEnabled(_ enabled: Bool, for option: GestureOption) {
        defaults.set(enabled, forKey: Key.gestureEnabledPrefix + option.rawValue)
        notifyChanged()
    }

    public var enabledGestureOptions: Set<GestureOption> {
        Set(GestureOption.allCases.filter(isGestureEnabled(_:)))
    }

    public var tabSleepingEnabled: Bool {
        get { defaults.bool(forKey: Key.tabSleepingEnabled) }
        set { defaults.set(newValue, forKey: Key.tabSleepingEnabled); notifyChanged() }
    }

    public var tabSleepingMinutes: Int {
        get { max(5, defaults.integer(forKey: Key.tabSleepingMinutes)) }
        set { defaults.set(max(5, newValue), forKey: Key.tabSleepingMinutes); notifyChanged() }
    }

    public var antiTrackingEnabled: Bool {
        get { defaults.bool(forKey: Key.antiTrackingEnabled) }
        set {
            defaults.set(newValue, forKey: Key.antiTrackingEnabled)
            notifyChanged()
        }
    }

    public var contentBlockingEnabled: Bool {
        get { defaults.bool(forKey: Key.contentBlockingEnabled) }
        set {
            defaults.set(newValue, forKey: Key.contentBlockingEnabled)
            notifyChanged()
        }
    }

    public var popupBlockingEnabled: Bool {
        get { defaults.bool(forKey: Key.popupBlockingEnabled) }
        set {
            defaults.set(newValue, forKey: Key.popupBlockingEnabled)
            notifyChanged()
        }
    }

    public var contentBlockingDisabledHosts: Set<String> {
        get {
            let values = defaults.array(forKey: Key.contentBlockingDisabledHosts) as? [String] ?? []
            return Set(values.compactMap(Self.normalizeHost(_:)))
        }
        set {
            let normalized = newValue.compactMap(Self.normalizeHost(_:)).sorted()
            defaults.set(normalized, forKey: Key.contentBlockingDisabledHosts)
            notifyChanged()
        }
    }

    public var harmfulSiteAllowedHosts: Set<String> {
        get {
            let values = defaults.array(forKey: Key.harmfulSiteAllowedHosts) as? [String] ?? []
            return Set(values.compactMap(Self.normalizeHost(_:)))
        }
        set {
            let normalized = newValue.compactMap(Self.normalizeHost(_:)).sorted()
            defaults.set(normalized, forKey: Key.harmfulSiteAllowedHosts)
            notifyChanged()
        }
    }

    public var harmfulSiteWarningEnabled: Bool {
        get { defaults.bool(forKey: Key.harmfulSiteWarningEnabled) }
        set {
            defaults.set(newValue, forKey: Key.harmfulSiteWarningEnabled)
            notifyChanged()
        }
    }

    public var ephemeralModeEnabled: Bool {
        get { defaults.bool(forKey: Key.ephemeralModeEnabled) }
        set {
            defaults.set(newValue, forKey: Key.ephemeralModeEnabled)
            notifyChanged()
        }
    }

    public var sendDoNotTrack: Bool {
        get { defaults.bool(forKey: Key.sendDoNotTrack) }
        set {
            defaults.set(newValue, forKey: Key.sendDoNotTrack)
            notifyChanged()
        }
    }

    public var restoreClosedTabPageHistory: Bool {
        get { defaults.bool(forKey: Key.restoreClosedTabPageHistory) }
        set {
            defaults.set(newValue, forKey: Key.restoreClosedTabPageHistory)
            notifyChanged()
        }
    }

    public var reopenTabsOnLaunch: Bool {
        get { defaults.bool(forKey: Key.reopenTabsOnLaunch) }
        set {
            defaults.set(newValue, forKey: Key.reopenTabsOnLaunch)
            notifyChanged()
        }
    }

    public var appleAccount: AppleAccount? {
        guard let userID = defaults.string(forKey: Key.appleAccountUserID), !userID.isEmpty else {
            return nil
        }
        let email = defaults.string(forKey: Key.appleAccountEmail)
        let displayName = defaults.string(forKey: Key.appleAccountDisplayName)
        return AppleAccount(userID: userID, email: email, displayName: displayName)
    }

    public func setAppleAccount(userID: String, email: String?, displayName: String?) {
        defaults.set(userID, forKey: Key.appleAccountUserID)
        defaults.set(email, forKey: Key.appleAccountEmail)
        defaults.set(displayName, forKey: Key.appleAccountDisplayName)
        notifyChanged()
    }

    public func clearAppleAccount() {
        defaults.removeObject(forKey: Key.appleAccountUserID)
        defaults.removeObject(forKey: Key.appleAccountEmail)
        defaults.removeObject(forKey: Key.appleAccountDisplayName)
        notifyChanged()
    }

    public var homePageURL: URL {
        if let url = URL(string: homePageURLString), url.scheme != nil {
            return url
        }
        return URL(string: "https://search.fenrir-inc.com/")!
    }

    public func searchURL(for query: String) -> URL {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedQuery = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let template = searchTemplate.isEmpty ? "https://search.fenrir-inc.com/?q={query}" : searchTemplate

        if template.contains("{query}") {
            let resolved = template.replacingOccurrences(of: "{query}", with: encodedQuery)
            if let url = URL(string: resolved), url.scheme != nil {
                return url
            }
        } else if let url = URL(string: template), url.scheme != nil {
            if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var items = components.queryItems ?? []
                items.append(URLQueryItem(name: "q", value: trimmed))
                components.queryItems = items
                if let resolved = components.url {
                    return resolved
                }
            }
        }

        var fallback = URLComponents(string: "https://search.fenrir-inc.com/")!
        fallback.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return fallback.url!
    }

    public func resetDefaults() {
        performBatchUpdate {
            defaults.set("https://search.fenrir-inc.com/", forKey: Key.homePageURL)
            defaults.set("https://search.fenrir-inc.com/?q={query}", forKey: Key.searchTemplate)
            defaults.set(true, forKey: Key.updatesEnabled)
            defaults.set(PreferredContentLanguage.system.rawValue, forKey: Key.preferredContentLanguage)
            defaults.removeObject(forKey: Key.preferredDownloadDirectoryBookmark)
            defaults.removeObject(forKey: Key.preferredDownloadDirectoryPath)
            defaults.set(GestureSensitivity.normal.rawValue, forKey: Key.gestureSensitivity)
            GestureInputKind.allCases.forEach { input in
                defaults.removeObject(forKey: Key.gestureSensitivityPrefix + input.rawValue)
            }
            defaults.set(true, forKey: Key.antiTrackingEnabled)
            defaults.set(true, forKey: Key.contentBlockingEnabled)
            defaults.set([], forKey: Key.contentBlockingDisabledHosts)
            defaults.set([], forKey: Key.harmfulSiteAllowedHosts)
            defaults.set(true, forKey: Key.popupBlockingEnabled)
            defaults.set(true, forKey: Key.harmfulSiteWarningEnabled)
            defaults.set(false, forKey: Key.ephemeralModeEnabled)
            defaults.set(true, forKey: Key.sendDoNotTrack)
            defaults.set(true, forKey: Key.restoreClosedTabPageHistory)
            defaults.set(true, forKey: Key.reopenTabsOnLaunch)
            defaults.set(true, forKey: Key.tabSleepingEnabled)
            defaults.set(30, forKey: Key.tabSleepingMinutes)
            GestureOption.allCases.forEach { option in
                defaults.set(true, forKey: Key.gestureEnabledPrefix + option.rawValue)
            }
            GesturePattern.allCases.forEach { pattern in
                defaults.removeObject(forKey: Key.gestureActionPrefix + pattern.rawValue)
            }
        }
    }

    public func isContentBlockingDisabled(for host: String) -> Bool {
        guard let normalized = Self.normalizeHost(host) else { return false }
        return contentBlockingDisabledHosts.contains(normalized)
    }

    public func setContentBlockingDisabled(_ disabled: Bool, for host: String) {
        guard let normalized = Self.normalizeHost(host) else { return }
        var hosts = contentBlockingDisabledHosts
        if disabled {
            hosts.insert(normalized)
        } else {
            hosts.remove(normalized)
        }
        contentBlockingDisabledHosts = hosts
    }

    public var contentBlockingExceptionSignature: String {
        contentBlockingDisabledHosts.sorted().joined(separator: "|")
    }

    public func isHarmfulSiteAllowed(for host: String) -> Bool {
        guard let normalized = Self.normalizeHost(host) else { return false }
        return harmfulSiteAllowedHosts.contains(normalized)
    }

    public func setHarmfulSiteAllowed(_ allowed: Bool, for host: String) {
        guard let normalized = Self.normalizeHost(host) else { return }
        var hosts = harmfulSiteAllowedHosts
        if allowed {
            hosts.insert(normalized)
        } else {
            hosts.remove(normalized)
        }
        harmfulSiteAllowedHosts = hosts
    }

    nonisolated private static func normalizeHost(_ host: String) -> String? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private func notifyChanged() {
        if isBatchUpdating {
            needsNotifyChanged = true
            return
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func performBatchUpdate(_ updates: () -> Void) {
        isBatchUpdating = true
        updates()
        isBatchUpdating = false

        if needsNotifyChanged {
            needsNotifyChanged = false
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }
}
