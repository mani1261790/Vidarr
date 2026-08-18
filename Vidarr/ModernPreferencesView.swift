import AppKit
import AuthenticationServices
import Combine
import SwiftUI
import VidarrCore

private struct TabGroupSymbolOption: Identifiable {
    let id: String
    let title: String

    static let all = [
        Self(id: "rectangle.stack", title: "タブ"),
        Self(id: "square.grid.2x2", title: "グリッド"),
        Self(id: "briefcase", title: "仕事"),
        Self(id: "text.magnifyingglass", title: "調査"),
        Self(id: "book.closed", title: "読書"),
        Self(id: "folder", title: "フォルダ"),
        Self(id: "graduationcap", title: "学習"),
        Self(id: "hammer", title: "開発"),
        Self(id: "paintbrush", title: "制作"),
        Self(id: "gamecontroller", title: "ゲーム")
    ]
}

private struct TabGroupColorOption: Identifiable {
    let id: String
    let title: String

    static let all = [
        Self(id: "blue", title: "ブルー"),
        Self(id: "purple", title: "パープル"),
        Self(id: "green", title: "グリーン"),
        Self(id: "pink", title: "ピンク"),
        Self(id: "orange", title: "オレンジ"),
        Self(id: "red", title: "レッド"),
        Self(id: "teal", title: "ティール"),
        Self(id: "indigo", title: "インディゴ")
    ]
}

private func tabGroupColor(_ colorID: String) -> Color {
    switch colorID {
    case "blue": return .blue
    case "purple": return .purple
    case "green": return .green
    case "pink": return .pink
    case "orange": return .orange
    case "red": return .red
    case "teal": return .teal
    case "indigo": return .indigo
    default: return .accentColor
    }
}

enum PreferencesSection: String, CaseIterable, Identifiable {
    case general
    case gestures
    case privacy
    case data
    case reset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "一般"
        case .gestures: return "ジェスチャー"
        case .privacy: return "プライバシー"
        case .data: return "保存データ"
        case .reset: return "リセット"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "起動、検索、同期"
        case .gestures: return "操作と感度"
        case .privacy: return "追跡防止と保護"
        case .data: return "履歴とダウンロード"
        case .reset: return "初期設定に戻す"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .gestures: return "hand.draw.fill"
        case .privacy: return "shield.lefthalf.filled"
        case .data: return "internaldrive.fill"
        case .reset: return "arrow.counterclockwise"
        }
    }

    var tint: Color {
        .accentColor
    }
}

@MainActor
final class PreferencesViewModel: ObservableObject {
    static let visibleGestureOptions: [BrowserPreferences.GestureOption] = [
        .back, .forward, .closeTab, .closeAllTabs, .reload,
        .newTab, .restoreClosedTab, .nextTab, .previousTab
    ]

    @Published var selectedSection: PreferencesSection = .general
    @Published var homePageURL = ""
    @Published var searchTemplate = ""
    @Published var tabGroups: [BrowserTabGroup] = []
    @Published var tabGroupRoutes: [String: String] = [:]
    @Published var routeDomain = ""
    @Published var routeTabGroupID = BrowserTabGroup.regular.id
    @Published var newTabGroupName = ""
    @Published var newTabGroupSymbolName = "rectangle.stack"
    @Published var newTabGroupColorID = "blue"
    @Published var contentLanguage: BrowserPreferences.PreferredContentLanguage = .system
    @Published var updatesEnabled = true
    @Published var reopenTabsOnLaunch = true
    @Published var restoreClosedTabHistory = true
    @Published var tabSleepingEnabled = true
    @Published var tabSleepingMinutes = 30

    @Published var gestureSensitivity: BrowserPreferences.GestureSensitivity = .normal
    @Published var enabledGestures: Set<BrowserPreferences.GestureOption> = []
    @Published var gestureSensitivities: [BrowserPreferences.GestureInputKind: BrowserPreferences.GestureSensitivity] = [:]
    @Published var gestureAssignments: [BrowserPreferences.GesturePattern: BrowserPreferences.GestureOption] = [:]

    @Published var antiTrackingEnabled = true
    @Published var contentBlockingEnabled = true
    @Published var popupBlockingEnabled = true
    @Published var harmfulSiteWarningEnabled = true
    @Published var ephemeralModeEnabled = false
    @Published var doNotTrackEnabled = true
    @Published var privacyTotals: [PrivacyEventKind: Int] = [:]
    @Published var recentPrivacyEvents: [PrivacyEvent] = []

    @Published var historyCount = 0
    @Published var bookmarkCount = 0
    @Published var downloadCount = 0
    @Published var siteControlCount = 0
    @Published var downloadFolderPath: String?
    @Published var cloudSyncAvailable = false
    @Published var appleAccountDescription = "未連携"
    @Published var hasAppleAccount = false
    @Published var isClearingData = false

    private let tabGroupContext = BrowserProfileManager.shared
    private let appleSignInCoordinator = AppleSignInCoordinator()
    private let openDownloadsAction: () -> Void
    private let openHistoryAction: () -> Void
    private let openBookmarksAction: () -> Void
    private let openSiteControlsAction: () -> Void
    private let windowProvider: () -> NSWindow?
    private var gesturePracticeWindowController: GesturePracticeWindowController?

    private var prefs: BrowserPreferences { .shared }

    init(
        openDownloads: @escaping () -> Void,
        openHistory: @escaping () -> Void,
        openBookmarks: @escaping () -> Void,
        openSiteControls: @escaping () -> Void,
        windowProvider: @escaping () -> NSWindow?
    ) {
        openDownloadsAction = openDownloads
        openHistoryAction = openHistory
        openBookmarksAction = openBookmarks
        openSiteControlsAction = openSiteControls
        self.windowProvider = windowProvider
        reload()
    }

    func reload() {
        let prefs = self.prefs
        homePageURL = prefs.homePageURLString
        searchTemplate = prefs.searchTemplate
        tabGroups = TabGroupStore.shared.groups
        tabGroupRoutes = tabGroupContext.tabGroupRouteRules
        if !tabGroups.contains(where: { $0.id == routeTabGroupID }) {
            routeTabGroupID = BrowserTabGroup.regular.id
        }
        contentLanguage = prefs.preferredContentLanguage
        updatesEnabled = prefs.updatesEnabled
        reopenTabsOnLaunch = prefs.reopenTabsOnLaunch
        restoreClosedTabHistory = prefs.restoreClosedTabPageHistory
        tabSleepingEnabled = prefs.tabSleepingEnabled
        tabSleepingMinutes = prefs.tabSleepingMinutes
        gestureSensitivity = prefs.gestureSensitivity
        enabledGestures = Set(Self.visibleGestureOptions.filter(prefs.isGestureEnabled))
        gestureSensitivities = Dictionary(uniqueKeysWithValues: BrowserPreferences.GestureInputKind.allCases.map {
            ($0, prefs.gestureSensitivity(for: $0))
        })
        gestureAssignments = Dictionary(uniqueKeysWithValues: BrowserPreferences.GesturePattern.allCases.compactMap { pattern in
            prefs.gestureAction(for: pattern).map { (pattern, $0) }
        })
        antiTrackingEnabled = prefs.antiTrackingEnabled
        contentBlockingEnabled = prefs.contentBlockingEnabled
        popupBlockingEnabled = prefs.popupBlockingEnabled
        harmfulSiteWarningEnabled = prefs.harmfulSiteWarningEnabled
        ephemeralModeEnabled = prefs.ephemeralModeEnabled
        doNotTrackEnabled = prefs.sendDoNotTrack
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        privacyTotals = Dictionary(uniqueKeysWithValues: PrivacyEventKind.allCases.map {
            ($0, PrivacyReportStore.shared.total(for: $0, since: sevenDaysAgo))
        })
        recentPrivacyEvents = Array(PrivacyReportStore.shared.recent().prefix(8))

        historyCount = BrowsingHistoryStore.shared.all().count
        bookmarkCount = BookmarkStore.shared.all().count
        downloadCount = DownloadStore.shared.all().count
        siteControlCount = prefs.contentBlockingDisabledHosts.count
            + prefs.harmfulSiteAllowedHosts.count
            + MediaPermissionStore.shared.all().count
        downloadFolderPath = prefs.preferredDownloadDirectoryPath
        cloudSyncAvailable = BookmarkStore.shared.isCloudSyncAvailable

        if let account = prefs.appleAccount {
            hasAppleAccount = true
            appleAccountDescription = [account.displayName, account.email]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            if appleAccountDescription.isEmpty { appleAccountDescription = "連携済み" }
        } else {
            hasAppleAccount = false
            appleAccountDescription = "未連携"
        }
    }

    func commitTextFields() {
        prefs.homePageURLString = homePageURL
        prefs.searchTemplate = searchTemplate
        reload()
    }

    func setUpdates(_ value: Bool) { prefs.updatesEnabled = value; reload() }
    func setRestoreHistory(_ value: Bool) { prefs.restoreClosedTabPageHistory = value; reload() }
    func setReopenTabs(_ value: Bool) {
        prefs.reopenTabsOnLaunch = value
        if !value { BrowserSessionStore.shared.clear() }
        reload()
    }
    func setTabSleeping(_ value: Bool) { prefs.tabSleepingEnabled = value; reload() }
    func setTabSleepingMinutes(_ value: Int) { prefs.tabSleepingMinutes = value; reload() }
    func setLanguage(_ value: BrowserPreferences.PreferredContentLanguage) {
        prefs.preferredContentLanguage = value
        reload()
    }
    func setSensitivity(_ value: BrowserPreferences.GestureSensitivity) {
        prefs.gestureSensitivity = value
        reload()
    }
    func setSensitivity(_ value: BrowserPreferences.GestureSensitivity, for input: BrowserPreferences.GestureInputKind) {
        prefs.setGestureSensitivity(value, for: input)
        reload()
    }
    func setGestureAction(_ action: BrowserPreferences.GestureOption?, for pattern: BrowserPreferences.GesturePattern) {
        prefs.setGestureAction(action, for: pattern)
        reload()
    }
    func gestureAction(for pattern: BrowserPreferences.GesturePattern) -> BrowserPreferences.GestureOption? {
        gestureAssignments[pattern]
    }
    var duplicateGestureActions: Set<BrowserPreferences.GestureOption> {
        let groups = Dictionary(grouping: gestureAssignments.values, by: { $0 })
        return Set(groups.compactMap { $0.value.count > 1 ? $0.key : nil })
    }
    func openGesturePractice() {
        let controller = gesturePracticeWindowController ?? GesturePracticeWindowController()
        gesturePracticeWindowController = controller
        controller.show(relativeTo: windowProvider())
    }
    func addTabGroupRoute() {
        guard tabGroupContext.setRoute(domain: routeDomain, tabGroupID: routeTabGroupID) else {
            showAlert(style: .warning, title: "ドメインを確認してください", message: "example.com のような形式で入力してください。")
            return
        }
        routeDomain = ""
        reload()
    }
    func removeTabGroupRoute(domain: String) {
        tabGroupContext.removeTabGroupRoute(domain: domain)
        reload()
    }
    func tabGroupName(for id: String) -> String {
        tabGroups.first(where: { $0.id == id })?.displayName ?? "不明なタブグループ"
    }
    func createTabGroup() {
        guard let group = TabGroupStore.shared.add(
            name: newTabGroupName,
            symbolName: newTabGroupSymbolName,
            colorID: newTabGroupColorID
        ) else {
            showAlert(style: .warning, title: "名前を入力してください", message: "タブグループ名は空にできません。")
            return
        }
        newTabGroupName = ""
        routeTabGroupID = group.id
        reload()
    }
    func setGesture(_ option: BrowserPreferences.GestureOption, enabled: Bool) {
        prefs.setGestureEnabled(enabled, for: option)
        reload()
    }
    func setAntiTracking(_ value: Bool) { prefs.antiTrackingEnabled = value; reload() }
    func setContentBlocking(_ value: Bool) { prefs.contentBlockingEnabled = value; reload() }
    func setPopupBlocking(_ value: Bool) { prefs.popupBlockingEnabled = value; reload() }
    func setHarmfulWarning(_ value: Bool) { prefs.harmfulSiteWarningEnabled = value; reload() }
    func setEphemeralMode(_ value: Bool) { prefs.ephemeralModeEnabled = value; reload() }
    func setDoNotTrack(_ value: Bool) { prefs.sendDoNotTrack = value; reload() }
    func clearPrivacyReport() { PrivacyReportStore.shared.clear(); reload() }
    func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    func beginAppleSignIn() {
        guard let window = windowProvider() else { return }
        appleSignInCoordinator.begin(window: window) { [weak self] result in
            guard let self else { return }
            let name = [result.fullName?.givenName, result.fullName?.familyName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            self.prefs.setAppleAccount(
                userID: result.userID,
                email: result.email,
                displayName: name.isEmpty ? nil : name
            )
            BookmarkStore.shared.forceSynchronize()
            self.reload()
        } onFailure: { [weak self] error in
            guard let self else { return }
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            self.showAlert(style: .warning, title: "Apple でサインインできませんでした", message: error.localizedDescription)
        }
    }

    func signOutAppleAccount() {
        let alert = confirmation(
            title: "Apple アカウント連携を解除しますか？",
            message: "Vidarr に保存している表示情報だけを削除します。iCloudからはサインアウトしません。",
            actionTitle: "解除"
        )
        present(alert) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.prefs.clearAppleAccount()
            self.reload()
        }
    }

    func synchronizeBookmarks() {
        BookmarkStore.shared.forceSynchronize()
        reload()
    }

    func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "選択"
        panel.directoryURL = prefs.preferredDownloadDirectoryURL()
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                try self.prefs.setPreferredDownloadDirectory(url)
                self.reload()
            } catch {
                self.showAlert(style: .warning, title: "ダウンロード先を保存できませんでした", message: error.localizedDescription)
            }
        }
        if let window = windowProvider() {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    func clearDownloadFolder() {
        _ = try? prefs.setPreferredDownloadDirectory(nil)
        reload()
    }

    func clearBrowsingData() {
        let alert = confirmation(
            title: "閲覧データを削除しますか？",
            message: "Cookie、キャッシュ、保存済みサイトデータを削除します。履歴やブックマークは残ります。",
            actionTitle: "削除"
        )
        present(alert) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.isClearingData = true
            BrowserDataCleaner.clearPersistentBrowsingData { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isClearingData = false
                    switch result {
                    case .success:
                        self.showAlert(style: .informational, title: "閲覧データを削除しました", message: "Cookie、キャッシュ、保存済みサイトデータを削除しました。")
                    case .failure(let error):
                        self.showAlert(style: .warning, title: "閲覧データの削除に失敗しました", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    func resetDefaults() {
        let alert = confirmation(
            title: "設定をデフォルトに戻しますか？",
            message: "ホームページ、検索、ジェスチャー、プライバシー設定を初期状態に戻します。保存データは削除しません。",
            actionTitle: "戻す"
        )
        present(alert) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.prefs.resetDefaults()
            self.reload()
        }
    }

    func openDownloads() { openDownloadsAction() }
    func openHistory() { openHistoryAction() }
    func openBookmarks() { openBookmarksAction() }
    func openSiteControls() { openSiteControlsAction() }

    private func confirmation(title: String, message: String, actionTitle: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "キャンセル")
        return alert
    }

    private func showAlert(style: NSAlert.Style, title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        present(alert, completion: nil)
    }

    private func present(_ alert: NSAlert, completion: ((NSApplication.ModalResponse) -> Void)?) {
        if let window = windowProvider() {
            alert.beginSheetModal(for: window) { response in completion?(response) }
        } else {
            let response = alert.runModal()
            completion?(response)
        }
    }
}

struct ModernPreferencesView: View {
    @ObservedObject var model: PreferencesViewModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
            Divider().opacity(0.45)
            content
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor)
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Preferences").font(.headline)
                    Text("Vidarr の設定").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 24)

            VStack(spacing: 7) {
                ForEach(PreferencesSection.allCases) { section in
                    categoryButton(section)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            Label("設定は自動的に保存されます", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(18)
        }
        .background(.ultraThinMaterial)
    }

    private func categoryButton(_ section: PreferencesSection) -> some View {
        let isSelected = model.selectedSection == section
        return Button {
            model.commitTextFields()
            withAnimation(.easeOut(duration: 0.18)) { model.selectedSection = section }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? section.tint : Color.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title).font(.system(size: 13, weight: .semibold))
                    Text(section.subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(section.tint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? section.tint.opacity(0.13) : .clear)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityValue(isSelected ? "選択中" : "")
        .accessibilityIdentifier("preferences.category.\(section.rawValue)")
    }

    private var content: some View {
        VStack(spacing: 0) {
            sectionHeader
            Divider().opacity(0.35)
            ScrollView {
                sectionContent
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.selectedSection.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(model.selectedSection.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch model.selectedSection {
        case .general: generalSection
        case .gestures: gesturesSection
        case .privacy: privacySection
        case .data: dataSection
        case .reset: resetSection
        }
    }

    private var generalSection: some View {
        VStack(spacing: 18) {
            PreferenceCard(title: "ブラウジング", subtitle: "起動時のページと検索先", symbol: "safari.fill", tint: .secondary) {
                ModernTextField(title: "スタートページ URL", text: $model.homePageURL, placeholder: "https://example.com/")
                ModernTextField(title: "検索URL", text: $model.searchTemplate, placeholder: "https://example.com/?q={query}")
                Button("入力内容を保存") { model.commitTextFields() }
                    .buttonStyle(RoundedActionButtonStyle(tint: .accentColor, prominent: true))
            }

            PreferenceCard(title: "タブグループ", subtitle: "用途ごとにタブとサイトデータを分ける", symbol: "square.grid.2x2", tint: .secondary) {
                Text("通常・仕事・リサーチなどのタブをまとめ、Cookieとサイトデータもグループごとに分離します。履歴、ブックマーク、言語などの設定はVidarr全体で共通です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider().opacity(0.35)
                Text("タブグループを作成")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 10) {
                    TextField("グループ名", text: $model.newTabGroupName)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 160)
                    Picker("アイコン", selection: $model.newTabGroupSymbolName) {
                        ForEach(TabGroupSymbolOption.all) { option in
                            Label(option.title, systemImage: option.id).tag(option.id)
                        }
                    }
                    .frame(width: 150)
                    Picker("色", selection: $model.newTabGroupColorID) {
                        ForEach(TabGroupColorOption.all) { option in
                            HStack {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(tabGroupColor(option.id))
                                Text(option.title)
                            }
                            .tag(option.id)
                        }
                    }
                    .frame(width: 135)
                    Button("作成") { model.createTabGroup() }
                        .buttonStyle(RoundedActionButtonStyle(tint: .accentColor))
                        .disabled(model.newTabGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(model.tabGroups, id: \.id) { group in
                    HStack(spacing: 9) {
                        Image(systemName: group.displaySymbolName)
                            .foregroundStyle(tabGroupColor(group.displayColorID))
                            .frame(width: 18)
                        Text(group.displayName)
                            .font(.system(size: 12, weight: .medium))
                        if group.kind != .custom {
                            Text("標準")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                Divider().opacity(0.35)
                Text("外部リンクの自動振り分け")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 10) {
                    TextField("example.com", text: $model.routeDomain)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180)
                    Picker("", selection: $model.routeTabGroupID) {
                        ForEach(model.tabGroups, id: \.id) { Text($0.displayName).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                    Button("追加") { model.addTabGroupRoute() }
                        .buttonStyle(RoundedActionButtonStyle(tint: .accentColor))
                }
                ForEach(model.tabGroupRoutes.keys.sorted(), id: \.self) { domain in
                    HStack(spacing: 10) {
                        Image(systemName: "globe").foregroundStyle(.secondary).frame(width: 18)
                        Text(domain).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(model.tabGroupName(for: model.tabGroupRoutes[domain] ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button { model.removeTabGroupRoute(domain: domain) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(domain)の振り分けを削除")
                    }
                    .padding(.vertical, 4)
                }
            }

            PreferenceCard(title: "Webページの表示言語", subtitle: "サイトへ伝える優先言語", symbol: "globe", tint: .secondary) {
                LabeledPicker(title: "Webページの表示言語", selection: Binding(
                    get: { model.contentLanguage },
                    set: { model.setLanguage($0) }
                )) {
                    ForEach(BrowserPreferences.PreferredContentLanguage.allCases, id: \.rawValue) {
                        Text($0.displayName).tag($0)
                    }
                }
            }

            PreferenceCard(title: "起動と復元", subtitle: "前回の作業状態を引き継ぐ", symbol: "clock.arrow.circlepath", tint: .secondary) {
                ModernToggle(title: "アップデート通知", subtitle: "新しいバージョンを通知します", symbol: "bell.badge.fill", tint: .secondary, isOn: Binding(get: { model.updatesEnabled }, set: { model.setUpdates($0) }))
                ModernToggle(title: "前回のタブを開く", subtitle: "終了時のタブを次回起動時に復元します", symbol: "rectangle.stack.fill", tint: .secondary, isOn: Binding(get: { model.reopenTabsOnLaunch }, set: { model.setReopenTabs($0) }))
                ModernToggle(title: "ページ履歴も復元", subtitle: "閉じたタブを戻した際の閲覧履歴を保持します", symbol: "clock.fill", tint: .secondary, isOn: Binding(get: { model.restoreClosedTabHistory }, set: { model.setRestoreHistory($0) }))
                Divider().opacity(0.35)
                ModernToggle(title: "使っていないタブを休止", subtitle: "ページを解放し、選択時に同じURLを復元します", symbol: "moon.zzz", tint: .secondary, isOn: Binding(get: { model.tabSleepingEnabled }, set: { model.setTabSleeping($0) }))
                if model.tabSleepingEnabled {
                    LabeledPicker(title: "休止までの時間", selection: Binding(
                        get: { model.tabSleepingMinutes },
                        set: { model.setTabSleepingMinutes($0) }
                    )) {
                        Text("15分").tag(15)
                        Text("30分").tag(30)
                        Text("1時間").tag(60)
                        Text("2時間").tag(120)
                    }
                }
            }

            PreferenceCard(title: "Apple アカウントと同期", subtitle: "ブックマークをiCloud経由で同期", symbol: "icloud.fill", tint: .secondary) {
                StatusRow(title: model.appleAccountDescription, detail: model.cloudSyncAvailable ? "iCloud同期を利用できます" : "iCloud同期は現在利用できません", symbol: model.hasAppleAccount ? "checkmark.seal.fill" : "person.crop.circle.badge.questionmark", tint: model.hasAppleAccount ? .green : .secondary)
                HStack {
                    if model.hasAppleAccount {
                        Button("連携を解除") { model.signOutAppleAccount() }
                            .buttonStyle(RoundedActionButtonStyle(tint: .red))
                    } else {
                        Button { model.beginAppleSignIn() } label: { Label("Sign in with Apple", systemImage: "apple.logo") }
                            .buttonStyle(RoundedActionButtonStyle(tint: .primary, prominent: true))
                    }
                    Button { model.synchronizeBookmarks() } label: { Label("今すぐ同期", systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(RoundedActionButtonStyle(tint: .accentColor))
                        .disabled(!model.cloudSyncAvailable)
                }
            }
        }
        .onDisappear { model.commitTextFields() }
    }

    private var gesturesSection: some View {
        VStack(spacing: 18) {
            PreferenceCard(title: "入力ごとの感度", subtitle: "使うデバイスに合わせて認識の開始条件を調整", symbol: "dial.medium.fill", tint: .secondary) {
                ForEach(BrowserPreferences.GestureInputKind.allCases, id: \.rawValue) { input in
                    HStack {
                        Text(input.displayName).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { model.gestureSensitivities[input] ?? .normal },
                            set: { model.setSensitivity($0, for: input) }
                        )) {
                            ForEach(BrowserPreferences.GestureSensitivity.allCases, id: \.rawValue) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                    if input != BrowserPreferences.GestureInputKind.allCases.last { Divider().opacity(0.35) }
                }
            }

            PreferenceCard(title: "ジェスチャーの割り当て", subtitle: "描く形ごとに実行する操作を選択", symbol: "hand.draw.fill", tint: .secondary) {
                ForEach(BrowserPreferences.GesturePattern.allCases, id: \.rawValue) { pattern in
                    HStack(spacing: 14) {
                        GesturePatternGlyph(pattern: pattern)
                            .frame(width: 46, height: 30)
                            .padding(6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pattern.label).font(.system(size: 13, weight: .semibold))
                            if let action = model.gestureAction(for: pattern), model.duplicateGestureActions.contains(action) {
                                Text("同じ操作が別の形にも割り当てられています")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Picker("操作", selection: Binding<BrowserPreferences.GestureOption?>(
                            get: { model.gestureAction(for: pattern) },
                            set: { model.setGestureAction($0, for: pattern) }
                        )) {
                            Text("無効").tag(nil as BrowserPreferences.GestureOption?)
                            ForEach(BrowserPreferences.GestureOption.allCases, id: \.rawValue) { action in
                                Text(action.title).tag(Optional(action))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 210)
                    }
                    if pattern != BrowserPreferences.GesturePattern.allCases.last { Divider().opacity(0.35) }
                }
            }

            PreferenceCard(title: "ジェスチャーテスト", subtitle: "設定画面とは別のウィンドウで入力を確認", symbol: "scribble.variable", tint: .secondary) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("本番と同じ認識器を使用")
                            .font(.system(size: 13, weight: .semibold))
                        Text("感度・開始条件・割り当てもそのまま反映されます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.openGesturePractice() } label: {
                        Label("テストを開く", systemImage: "macwindow")
                    }
                    .buttonStyle(RoundedActionButtonStyle(tint: .accentColor, prominent: true))
                    .accessibilityIdentifier("preferences.gestures.openTest")
                }
            }
        }
    }

    private var privacySection: some View {
        VStack(spacing: 18) {
            PreferenceCard(title: "プライバシーレポート", subtitle: "過去7日間に行った保護", symbol: "checkmark.shield", tint: .secondary) {
                HStack(spacing: 18) {
                    PrivacyMetric(value: (model.privacyTotals[.blockedRequest] ?? 0) + (model.privacyTotals[.blockedElement] ?? 0), label: "ブロック")
                    PrivacyMetric(value: model.privacyTotals[.trackingParameter] ?? 0, label: "追跡パラメータ")
                    PrivacyMetric(value: model.privacyTotals[.popup] ?? 0, label: "ポップアップ")
                    PrivacyMetric(value: (model.privacyTotals[.permissionDenied] ?? 0) + (model.privacyTotals[.harmfulSite] ?? 0), label: "拒否・警告")
                }
                if model.recentPrivacyEvents.isEmpty {
                    Text("まだ保護イベントはありません。閲覧中の処理がここに記録されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    Divider().opacity(0.35)
                    ForEach(model.recentPrivacyEvents) { event in
                        HStack(spacing: 10) {
                            Image(systemName: event.kind.symbol)
                                .frame(width: 18)
                                .foregroundStyle(.secondary)
                            Text(event.kind.title).font(.system(size: 12, weight: .medium))
                            Text(event.host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            if event.count > 1 { Text("×\(event.count)").font(.caption.monospacedDigit()) }
                            Text(model.relativeTime(for: event.createdAt)).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    HStack {
                        Spacer()
                        Button("履歴を消去") { model.clearPrivacyReport() }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            PreferenceCard(title: "Web保護", subtitle: "閲覧時の追跡と危険な挙動を抑制", symbol: "shield.checkered", tint: .secondary) {
                ModernToggle(title: "追跡パラメータを除去", subtitle: "URL内の不要なトラッキング情報を取り除きます", symbol: "link", tint: .secondary, isOn: Binding(get: { model.antiTrackingEnabled }, set: { model.setAntiTracking($0) }))
                ModernToggle(title: "広告・追跡スクリプトをブロック", subtitle: "既知の広告とトラッカーを読み込み前に遮断します", symbol: "hand.raised.fill", tint: .secondary, isOn: Binding(get: { model.contentBlockingEnabled }, set: { model.setContentBlocking($0) }))
                ModernToggle(title: "ポップアップを抑止", subtitle: "意図せず開くウィンドウやタブを防ぎます", symbol: "macwindow.badge.plus", tint: .secondary, isOn: Binding(get: { model.popupBlockingEnabled }, set: { model.setPopupBlocking($0) }))
                ModernToggle(title: "有害サイト警告", subtitle: "危険性があるサイトを開く前に確認します", symbol: "exclamationmark.shield.fill", tint: .red, isOn: Binding(get: { model.harmfulSiteWarningEnabled }, set: { model.setHarmfulWarning($0) }))
            }
            PreferenceCard(title: "プライバシーシグナル", subtitle: "サイトへ伝えるプライバシー設定", symbol: "eye.slash.fill", tint: .secondary) {
                ModernToggle(title: "プライバシー優先モード", subtitle: "終了時に履歴とCookieを残しません", symbol: "sparkles", tint: .secondary, isOn: Binding(get: { model.ephemeralModeEnabled }, set: { model.setEphemeralMode($0) }))
                ModernToggle(title: "DNT / GPC を送信", subtitle: "追跡を拒否する意思をWebサイトへ送信します", symbol: "antenna.radiowaves.left.and.right.slash", tint: .secondary, isOn: Binding(get: { model.doNotTrackEnabled }, set: { model.setDoNotTrack($0) }))
            }
        }
    }

    private var dataSection: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                StatTile(value: model.historyCount, label: "履歴", symbol: "clock.fill", tint: .secondary)
                StatTile(value: model.bookmarkCount, label: "ブックマーク", symbol: "star.fill", tint: .secondary)
                StatTile(value: model.downloadCount, label: "ダウンロード", symbol: "arrow.down.circle.fill", tint: .secondary)
                StatTile(value: model.siteControlCount, label: "サイト設定", symbol: "switch.2", tint: .secondary)
            }

            PreferenceCard(title: "ライブラリ", subtitle: "保存されている項目を管理", symbol: "books.vertical.fill", tint: .secondary) {
                HStack(spacing: 12) {
                    DataActionButton(title: "履歴", count: model.historyCount, symbol: "clock.arrow.circlepath", tint: .secondary, action: model.openHistory)
                    DataActionButton(title: "ブックマーク", count: model.bookmarkCount, symbol: "star.fill", tint: .secondary, action: model.openBookmarks)
                }
                HStack(spacing: 12) {
                    DataActionButton(title: "ダウンロード", count: model.downloadCount, symbol: "arrow.down.circle.fill", tint: .secondary, action: model.openDownloads)
                    DataActionButton(title: "サイトごとの例外", count: model.siteControlCount, symbol: "switch.2", tint: .secondary, action: model.openSiteControls)
                }
            }

            PreferenceCard(title: "ダウンロード先", subtitle: model.downloadFolderPath ?? "ファイルごとに保存先を確認", symbol: "folder.fill", tint: .secondary) {
                HStack {
                    Button { model.chooseDownloadFolder() } label: { Label("フォルダを選択", systemImage: "folder.badge.plus") }
                        .buttonStyle(RoundedActionButtonStyle(tint: .accentColor, prominent: true))
                    Button("既定に戻す") { model.clearDownloadFolder() }
                        .buttonStyle(RoundedActionButtonStyle(tint: .secondary))
                        .disabled(model.downloadFolderPath == nil)
                }
            }

            PreferenceCard(title: "Webサイトデータ", subtitle: "Cookie、キャッシュ、保存済みデータ", symbol: "trash.fill", tint: .red) {
                HStack {
                    Text("履歴、ブックマーク、ダウンロード履歴、サイト設定は削除されません。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.clearBrowsingData() } label: {
                        if model.isClearingData { ProgressView().controlSize(.small) } else { Label("閲覧データを削除", systemImage: "trash") }
                    }
                    .buttonStyle(RoundedActionButtonStyle(tint: .red, prominent: true))
                    .disabled(model.isClearingData)
                }
            }
        }
    }

    private var resetSection: some View {
        VStack(spacing: 18) {
            PreferenceCard(title: "設定を初期化", subtitle: "保存データを残したまま設定だけを戻す", symbol: "arrow.counterclockwise", tint: .red) {
                StatusRow(title: "初期化される項目", detail: "ホームページ、検索、ジェスチャー、プライバシー設定", symbol: "slider.horizontal.3", tint: .red)
                StatusRow(title: "保持される項目", detail: "履歴、ブックマーク、ダウンロード履歴", symbol: "checkmark.shield.fill", tint: .green)
                Button { model.resetDefaults() } label: { Label("デフォルト設定に戻す", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(RoundedActionButtonStyle(tint: .red, prominent: true))
            }
        }
    }
}

struct PreferenceCard<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    @ViewBuilder let content: Content

    init(title: String, subtitle: String, symbol: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

struct ModernTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 13)
                .frame(height: 38)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.12)) }
        }
    }
}

struct ModernToggle: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

struct LabeledPicker<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    @ViewBuilder let content: Content

    init(title: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.title = title
        _selection = selection
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
            Picker("", selection: $selection) { content }
                .labelsHidden()
                .frame(minWidth: 180)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct StatusRow: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct StatTile: View {
    let value: Int
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 22, alignment: .center)
            Text("\(value)").font(.system(size: 24, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .center)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08)) }
    }
}

struct DataActionButton: View {
    let title: String
    let count: Int
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text("\(count)件").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("preferences.data.\(title)")
    }
}

struct RoundedActionButtonStyle: ButtonStyle {
    let tint: Color
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                prominent ? tint.opacity(configuration.isPressed ? 0.72 : 0.92) : Color.primary.opacity(configuration.isPressed ? 0.1 : 0.055),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.1))
                }
            }
    }
}

struct GestureGlyph: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }
        return path
    }
}

struct GestureOptionGlyph: View {
    let option: BrowserPreferences.GestureOption

    var body: some View {
        Group {
            switch option {
            case .reload:
                SmoothLoopGlyph(loopCount: 1, lineWidth: 2.2)
            case .reloadAll:
                DoubleLoopSpiralGlyph()
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .padding(3)
            default:
                GestureGlyph(points: option.strokePoints)
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

struct GesturePatternGlyph: View {
    let pattern: BrowserPreferences.GesturePattern

    var body: some View {
        Group {
            switch pattern {
            case .o:
                SmoothLoopGlyph(loopCount: 1, lineWidth: 2)
            case .oo:
                DoubleLoopSpiralGlyph()
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(2)
            case .s:
                SearchGestureGlyph()
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(.horizontal, 3)
            default:
                GestureGlyph(points: pattern.strokePoints)
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

struct SmoothLoopGlyph: View {
    let loopCount: Int
    let lineWidth: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<loopCount, id: \.self) { _ in
                Circle()
                    .stroke(.secondary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, loopCount == 1 ? 8 : 1)
    }
}

/// ◎ 専用の一筆書きグリフ。
/// 閉じた円を2つ接続するのではなく、外側から内側へ連続して巻くベジェスパスとして描く。
struct DoubleLoopSpiralGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let diameter = min(rect.width, rect.height)
        guard diameter > 0 else { return path }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = diameter * 0.44
        let innerRadius = diameter * 0.25
        let startAngle = -CGFloat.pi / 2
        let endAngle = startAngle + 4 * CGFloat.pi
        let radialChangePerRadian = (innerRadius - outerRadius) / (endAngle - startAngle)

        func radius(at angle: CGFloat) -> CGFloat {
            outerRadius + radialChangePerRadian * (angle - startAngle)
        }

        func point(at angle: CGFloat) -> CGPoint {
            let r = radius(at: angle)
            return CGPoint(
                x: center.x + cos(angle) * r,
                y: center.y + sin(angle) * r
            )
        }

        func derivative(at angle: CGFloat) -> CGVector {
            let r = radius(at: angle)
            return CGVector(
                dx: radialChangePerRadian * cos(angle) - r * sin(angle),
                dy: radialChangePerRadian * sin(angle) + r * cos(angle)
            )
        }

        // 1/4周ごとの3次ベジェ。隣接セグメントは同じ解析接線を共有するため、
        // 1周目と2周目の境界に角や継ぎ目が発生しない。
        let segmentCount = 8
        let angleStep = (endAngle - startAngle) / CGFloat(segmentCount)
        path.move(to: point(at: startAngle))

        for index in 0..<segmentCount {
            let angle0 = startAngle + CGFloat(index) * angleStep
            let angle1 = angle0 + angleStep
            let point0 = point(at: angle0)
            let point1 = point(at: angle1)
            let tangent0 = derivative(at: angle0)
            let tangent1 = derivative(at: angle1)
            let controlScale = angleStep / 3

            path.addCurve(
                to: point1,
                control1: CGPoint(
                    x: point0.x + tangent0.dx * controlScale,
                    y: point0.y + tangent0.dy * controlScale
                ),
                control2: CGPoint(
                    x: point1.x - tangent1.dx * controlScale,
                    y: point1.y - tangent1.dy * controlScale
                )
            )
        }

        // 2周目の接線をそのまま引き継いだ、軌道から少し外れる終端。
        let spiralEnd = point(at: endAngle)
        let endTangent = derivative(at: endAngle)
        let tangentLength = hypot(endTangent.dx, endTangent.dy)
        let tangent = CGVector(
            dx: endTangent.dx / tangentLength,
            dy: endTangent.dy / tangentLength
        )
        let tailEnd = CGPoint(
            x: spiralEnd.x + diameter * 0.18,
            y: spiralEnd.y + diameter * 0.10
        )
        path.addCurve(
            to: tailEnd,
            control1: CGPoint(
                x: spiralEnd.x + tangent.dx * diameter * 0.09,
                y: spiralEnd.y + tangent.dy * diameter * 0.09
            ),
            control2: CGPoint(
                x: tailEnd.x - diameter * 0.055,
                y: tailEnd.y - diameter * 0.015
            )
        )

        return path
    }
}

/// 認識器の S は丸文字ではなく、反転した Z の順序で斜めに折り返す形。
/// 一覧表示では専用のベジェ曲線にして、折り返し方向を保ちつつ角だけを滑らかにする。
struct SearchGestureGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        var path = Path()
        path.move(to: point(0.82, 0.18))
        path.addCurve(
            to: point(0.22, 0.31),
            control1: point(0.64, 0.08),
            control2: point(0.25, 0.08)
        )
        path.addCurve(
            to: point(0.76, 0.66),
            control1: point(0.18, 0.48),
            control2: point(0.72, 0.48)
        )
        path.addCurve(
            to: point(0.18, 0.82),
            control1: point(0.78, 0.89),
            control2: point(0.38, 0.94)
        )
        return path
    }
}

struct PrivacyMetric: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted())
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
