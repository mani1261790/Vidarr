import SwiftUI
import WebKit

struct PadBrowserRootView: View {
    enum LibraryPanel: String, Identifiable {
        case history
        case bookmarks
        case downloads

        var id: String { rawValue }
    }

    private struct TabSwitchTransition: Identifiable {
        enum Mode {
            case standard
            case newTab
        }

        let id = UUID()
        let fromTab: PadBrowserModel.Tab
        let toTab: PadBrowserModel.Tab
        let direction: CGFloat
        let mode: Mode
    }

    @StateObject private var model = PadBrowserModel()
    @State private var gestureHUD: PadGestureHUDState?
    @State private var gestureHUDTask: Task<Void, Never>?
    @State private var bottomBarVisible = true
    @State private var bottomBarHideTask: Task<Void, Never>?
    @State private var editingTabID: UUID?
    @State private var editingURL = ""
    @State private var showingSettings = false
    @State private var activeLibraryPanel: LibraryPanel?
    @State private var tabSwitchTransition: TabSwitchTransition?
    @State private var tabSwitchProgress: CGFloat = 0
    @State private var tabSwitchToken = UUID()
    @State private var interactiveTargetID: UUID?
    @FocusState private var editingURLFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            webLayer
            bottomBar
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
                .offset(y: bottomBarVisible ? 0 : 96)
                .opacity(bottomBarVisible ? 1 : 0.001)
                .allowsHitTesting(bottomBarVisible)
            if !bottomBarVisible {
                bottomRevealZone
            }
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(item: editingTabBinding) { tab in
            PadTabEditSheet(
                tab: tab,
                currentURL: bindingForEditingURL(),
                isBookmarked: model.isBookmarked(tab),
                onToggleBookmark: {
                    model.selectTab(id: tab.id)
                    model.toggleBookmarkForSelectedTab()
                },
                onOpenURL: {
                    model.selectTab(id: tab.id)
                    model.loadSelectedTab(with: editingURL)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .onAppear {
                editingURL = tab.urlString
            }
        }
        .sheet(isPresented: $showingSettings) {
            PadSettingsSheet(
                onOpenHistory: { activeLibraryPanel = .history },
                onOpenBookmarks: { activeLibraryPanel = .bookmarks },
                onOpenDownloads: { activeLibraryPanel = .downloads },
                onDone: {
                    model.refreshPreferences()
                    showingSettings = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $activeLibraryPanel) { panel in
            PadLibraryPanelSheet(
                panel: panel,
                model: model
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(item: $model.pendingHarmfulSitePrompt) { prompt in
            Alert(
                title: Text(prompt.title),
                message: Text(prompt.message),
                primaryButton: .default(Text("続行")) {
                    model.continueToHarmfulSite(permanentlyAllow: false)
                },
                secondaryButton: .destructive(Text("常に許可")) {
                    model.continueToHarmfulSite(permanentlyAllow: true)
                }
            )
        }
        .onAppear {
            scheduleBottomBarAutoHide()
        }
        .onChange(of: showingSettings) { _, isShowing in
            if isShowing {
                showBottomBar(persist: true)
            } else {
                scheduleBottomBarAutoHide()
            }
        }
        .onChange(of: editingTabID) { _, editingID in
            if editingID != nil {
                showBottomBar(persist: true)
            } else {
                scheduleBottomBarAutoHide()
            }
        }
    }

    private var webLayer: some View {
        GeometryReader { proxy in
            ZStack {
                if let transition = tabSwitchTransition {
                    let gap: CGFloat = 16
                    let width = max(proxy.size.width, 1)
                    let travel = width + gap
                    let fromX = -transition.direction * travel * tabSwitchProgress
                    let toX = transition.direction * travel * (1 - tabSwitchProgress)
                    let fromEdge = fromX + (transition.direction > 0 ? width : 0)
                    let toEdge = toX + (transition.direction > 0 ? 0 : width)
                    let gapX = ((fromEdge + toEdge) * 0.5) - (gap * 0.5)
                    let dimOpacity = transition.mode == .newTab ? 0.14 : 0.10

                    PadWebView(webView: transition.fromTab.webView)
                        .id("from-\(transition.id)")
                        .ignoresSafeArea()
                        .offset(x: fromX)
                        .overlay(Color.black.opacity(dimOpacity * tabSwitchProgress))
                    PadWebView(webView: transition.toTab.webView)
                        .id("to-\(transition.id)")
                        .ignoresSafeArea()
                        .offset(x: toX)
                        .scaleEffect(transition.mode == .newTab ? (0.985 + (0.015 * tabSwitchProgress)) : 1, anchor: .center)
                        .shadow(color: .black.opacity(0.14), radius: transition.mode == .newTab ? 16 : 10, y: 4)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground).opacity(0.96))
                        .frame(width: gap, height: proxy.size.height)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 0)
                        .offset(x: gapX)
                } else if let tab = model.selectedTab {
                    PadWebView(
                        webView: tab.webView,
                        gestureConfiguration: gestureConfiguration
                    )
                        .id(tab.id)
                        .ignoresSafeArea()
                } else {
                    ContentUnavailableView("No Tab", systemImage: "square.on.square")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let gestureHUD {
                    PadGestureHUD(state: gestureHUD)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                chromeButton(systemName: "chevron.left", disabled: !model.canGoBack(), action: model.goBack)
                chromeButton(systemName: "chevron.right", disabled: !model.canGoForward(), action: model.goForward)
                chromeButton(systemName: "arrow.clockwise", disabled: false, action: model.reload)
            }

            tabStrip

            HStack(spacing: 10) {
                chromeButton(systemName: "gearshape", disabled: false) {
                    showingSettings = true
                }
                chromeButton(systemName: "plus", disabled: false) {
                    animateNewTabCreation()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            PadLiquidGlassBackground(cornerRadius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.11), radius: 14, y: 6)
    }

    private var bottomRevealZone: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(height: 20)
            .ignoresSafeArea(edges: .bottom)
            .onTapGesture {
                showBottomBar()
            }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(model.tabs) { tab in
                    PadTabThumbnail(
                        tab: tab,
                        isSelected: model.selectedTab?.id == tab.id,
                        onSelect: {
                            animateTabSelection(to: tab.id)
                        },
                        onLongPress: {
                            animateTabSelection(to: tab.id)
                            editingURL = tab.urlString
                            editingTabID = tab.id
                        }
                    )
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func chromeButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary.opacity(0.45) : Color.primary)
        .disabled(disabled)
        .simultaneousGesture(
            TapGesture().onEnded {
                showBottomBar()
            }
        )
    }

    private func performGesture(_ action: PadGestureAction) {
        switch action {
        case .previousTab:
            if let currentID = model.selectedTab?.id,
               let currentIndex = model.tabIndex(for: currentID),
               currentIndex > 0 {
                commitInteractiveTabSwitchIfNeeded(to: model.tabs[currentIndex - 1].id) {
                    animateTabSelection(to: model.tabs[currentIndex - 1].id)
                }
            }
        case .nextTab:
            if let currentID = model.selectedTab?.id,
               let currentIndex = model.tabIndex(for: currentID),
               currentIndex < model.tabs.count - 1 {
                commitInteractiveTabSwitchIfNeeded(to: model.tabs[currentIndex + 1].id) {
                    animateTabSelection(to: model.tabs[currentIndex + 1].id)
                }
            }
        case .closeTab:
            if let id = model.selectedTab?.id {
                model.closeTab(id: id)
            }
        case .closeAllTabs:
            model.closeAllTabs()
        case .restoreClosedTab:
            model.restoreClosedTab()
        case .reload:
            model.reload()
        case .reloadAll:
            model.reloadAllTabs()
        case .back:
            model.goBack()
        case .forward:
            model.goForward()
        case .search:
            if let tab = model.selectedTab {
                editingURL = tab.urlString
                editingTabID = tab.id
            }
        case .newTab:
            animateNewTabCreation()
        }
        showBottomBar()
        if action != .previousTab && action != .nextTab {
            showCommittedGestureHUD(for: action)
        }
    }

    private func showCommittedGestureHUD(for action: PadGestureAction) {
        let committedState = PadGestureHUDState(
            action: action,
            title: "",
            systemImageName: symbol(for: action),
            confidence: 1,
            isCommitted: true
        )
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            gestureHUD = committedState
        }
        gestureHUDTask?.cancel()
        gestureHUDTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            hideGestureHUD()
        }
    }

    private func hideGestureHUD() {
        gestureHUDTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) {
            gestureHUD = nil
        }
    }

    private func title(for action: PadGestureAction) -> String {
        switch action {
        case .previousTab: return "Previous Tab"
        case .nextTab: return "Next Tab"
        case .closeTab: return "Close Tab"
        case .closeAllTabs: return "Close All Tabs"
        case .restoreClosedTab: return "Restore Tab"
        case .reload: return "Reload"
        case .reloadAll: return "Reload All"
        case .back: return "Back"
        case .forward: return "Forward"
        case .search: return "Search"
        case .newTab: return "New Tab"
        }
    }

    private func symbol(for action: PadGestureAction) -> String {
        switch action {
        case .previousTab: return "arrow.left.circle"
        case .nextTab: return "arrow.right.circle"
        case .closeTab: return "xmark.circle"
        case .closeAllTabs: return "xmark.circle.fill"
        case .restoreClosedTab: return "arrow.uturn.backward.circle"
        case .reload: return "arrow.clockwise.circle"
        case .reloadAll: return "square.stack.3d.up.fill"
        case .back: return "arrow.uturn.backward"
        case .forward: return "arrow.uturn.forward"
        case .search: return "magnifyingglass.circle"
        case .newTab: return "plus.circle"
        }
    }

    private var editingTabBinding: Binding<PadBrowserModel.Tab?> {
        Binding(
            get: {
                guard let editingTabID else { return nil }
                return model.tabs.first(where: { $0.id == editingTabID })
            },
            set: { newValue in
                editingTabID = newValue?.id
            }
        )
    }

    private func bindingForEditingURL() -> Binding<String> {
        Binding(
            get: { editingURL },
            set: { editingURL = $0 }
        )
    }

    private var gestureConfiguration: PadGestureConfiguration {
        PadGestureConfiguration(
            sensitivity: PadBrowserPreferences.shared.gestureSensitivity,
            onPreview: { state in
                withAnimation(.easeOut(duration: 0.16)) {
                    gestureHUD = state
                }
            },
            onHorizontalSwipeDrag: { action, progress in
                updateInteractiveTabSwitch(for: action, progress: progress)
            },
            onHorizontalSwipeCancel: {
                cancelInteractiveTabSwitch()
            },
            onCommit: { action in
                performGesture(action)
            },
            onCancel: {
                cancelInteractiveTabSwitch()
                hideGestureHUD()
            }
        )
    }

    private func animateTabSelection(to id: UUID) {
        showBottomBar()
        guard let fromTab = model.selectedTab,
              fromTab.id != id,
              let fromIndex = model.tabIndex(for: fromTab.id),
              let toIndex = model.tabIndex(for: id) else {
            model.selectTab(id: id)
            return
        }

        let direction: CGFloat = toIndex > fromIndex ? 1 : -1
        guard let toTab = model.tabs.first(where: { $0.id == id }) else { return }

        let token = UUID()
        tabSwitchToken = token
        tabSwitchTransition = TabSwitchTransition(fromTab: fromTab, toTab: toTab, direction: direction, mode: .standard)
        tabSwitchProgress = 0
        interactiveTargetID = nil

        withAnimation(.easeInOut(duration: 0.24)) {
            tabSwitchProgress = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard tabSwitchToken == token else { return }
            model.selectTab(id: id)
            tabSwitchTransition = nil
            tabSwitchProgress = 0
        }
    }

    private func updateInteractiveTabSwitch(for action: PadGestureAction, progress: CGFloat) {
        guard let currentID = model.selectedTab?.id,
              let currentIndex = model.tabIndex(for: currentID) else { return }

        let targetIndex: Int
        let direction: CGFloat
        switch action {
        case .previousTab:
            guard currentIndex > 0 else { return }
            targetIndex = currentIndex - 1
            direction = -1
        case .nextTab:
            guard currentIndex < model.tabs.count - 1 else { return }
            targetIndex = currentIndex + 1
            direction = 1
        default:
            return
        }

        let fromTab = model.tabs[currentIndex]
        let toTab = model.tabs[targetIndex]
        if interactiveTargetID != toTab.id || tabSwitchTransition == nil {
            tabSwitchTransition = TabSwitchTransition(fromTab: fromTab, toTab: toTab, direction: direction, mode: .standard)
            interactiveTargetID = toTab.id
        }
        tabSwitchProgress = min(0.82, max(0, progress))
    }

    private func cancelInteractiveTabSwitch() {
        guard tabSwitchTransition != nil, interactiveTargetID != nil else { return }
        let token = UUID()
        tabSwitchToken = token
        withAnimation(.easeInOut(duration: 0.18)) {
            tabSwitchProgress = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(190))
            guard tabSwitchToken == token else { return }
            tabSwitchTransition = nil
            tabSwitchProgress = 0
            interactiveTargetID = nil
        }
    }

    private func commitInteractiveTabSwitchIfNeeded(to id: UUID, fallback: () -> Void) {
        guard interactiveTargetID == id, tabSwitchTransition != nil else {
            fallback()
            return
        }

        let token = UUID()
        tabSwitchToken = token
        withAnimation(.easeInOut(duration: 0.16)) {
            tabSwitchProgress = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(170))
            guard tabSwitchToken == token else { return }
            model.selectTab(id: id)
            tabSwitchTransition = nil
            tabSwitchProgress = 0
            interactiveTargetID = nil
        }
    }

    private func animateNewTabCreation() {
        showBottomBar()
        let fromTab = model.selectedTab
        model.newTab()
        guard let fromTab, let toTab = model.selectedTab else { return }

        let token = UUID()
        tabSwitchToken = token
        tabSwitchTransition = TabSwitchTransition(fromTab: fromTab, toTab: toTab, direction: 1, mode: .newTab)
        tabSwitchProgress = 0
        interactiveTargetID = nil

        withAnimation(.easeInOut(duration: 0.20)) {
            tabSwitchProgress = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(210))
            guard tabSwitchToken == token else { return }
            tabSwitchTransition = nil
            tabSwitchProgress = 0
        }
    }

    private func showBottomBar(persist: Bool = false) {
        bottomBarHideTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            bottomBarVisible = true
        }
        if !persist {
            scheduleBottomBarAutoHide()
        }
    }

    private func scheduleBottomBarAutoHide() {
        bottomBarHideTask?.cancel()
        guard PadBrowserPreferences.shared.autoHideBottomBar else {
            withAnimation(.easeOut(duration: 0.18)) {
                bottomBarVisible = true
            }
            return
        }
        guard !showingSettings, editingTabID == nil else { return }
        let delay = PadBrowserPreferences.shared.bottomBarAutoHideDelay.seconds
        bottomBarHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                bottomBarVisible = false
            }
        }
    }
}

private struct PadSettingsSheet: View {
    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general
        case gestures
        case privacy
        case data

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "基本"
            case .gestures: return "ジェスチャー"
            case .privacy: return "プライバシー"
            case .data: return "保存データ"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .general
    @State private var homePageURLString = PadBrowserPreferences.shared.homePageURLString
    @State private var searchTemplate = PadBrowserPreferences.shared.searchTemplate
    @State private var preferredContentLanguage = PadBrowserPreferences.shared.preferredContentLanguage
    @State private var gestureSensitivity = PadBrowserPreferences.shared.gestureSensitivity
    @State private var restoreClosedTabPageHistory = PadBrowserPreferences.shared.restoreClosedTabPageHistory
    @State private var autoHideBottomBar = PadBrowserPreferences.shared.autoHideBottomBar
    @State private var bottomBarAutoHideDelay = PadBrowserPreferences.shared.bottomBarAutoHideDelay
    @State private var allowsJavaScript = PadBrowserPreferences.shared.allowsJavaScript
    @State private var preferHTTPS = PadBrowserPreferences.shared.preferHTTPS
    @State private var stripTrackingParameters = PadBrowserPreferences.shared.stripTrackingParameters
    @State private var harmfulSiteWarningEnabled = PadBrowserPreferences.shared.harmfulSiteWarningEnabled
    @State private var cookiePolicy = PadBrowserPreferences.shared.cookiePolicy
    @State private var historyCount = PadBrowsingHistoryStore.shared.all().count
    @State private var bookmarkCount = PadBookmarkStore.shared.all().count

    let onOpenHistory: () -> Void
    let onOpenBookmarks: () -> Void
    let onOpenDownloads: () -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("設定", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Form {
                    switch selectedTab {
                    case .general:
                        Section("新しく開くページ") {
                            TextField("スタートページのURL", text: $homePageURLString)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            LabeledContent("新規タブ") {
                                Text("このURLを開く")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section("検索") {
                            TextField("検索するときのURL", text: $searchTemplate)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Text("検索語は {query} に入ります。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Section("Webページの表示") {
                            Picker("表示言語", selection: $preferredContentLanguage) {
                                ForEach(PadPreferredContentLanguage.allCases, id: \.self) { language in
                                    Text(language.displayName).tag(language)
                                }
                            }
                            Toggle("JavaScript を使う", isOn: $allowsJavaScript)
                            Toggle("HTTPS を優先する", isOn: $preferHTTPS)
                        }

                    case .gestures:
                        Section("ジェスチャーの反応") {
                            Picker("感度", selection: $gestureSensitivity) {
                                ForEach(PadGestureSensitivity.allCases, id: \.self) { sensitivity in
                                    Text(sensitivity.displayName).tag(sensitivity)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Section("下部バー") {
                            Toggle("自動で隠す", isOn: $autoHideBottomBar)
                            if autoHideBottomBar {
                                Picker("隠れるまでの時間", selection: $bottomBarAutoHideDelay) {
                                    ForEach(PadBottomBarAutoHideDelay.allCases, id: \.self) { delay in
                                        Text(delay.displayName).tag(delay)
                                    }
                                }
                            }
                        }

                        Section("タブの復元") {
                            Toggle("閉じたタブを復元したとき、前に見ていたページ履歴も戻す", isOn: $restoreClosedTabPageHistory)
                        }

                    case .privacy:
                        Section("プライバシー") {
                            Picker("Cookie の扱い", selection: $cookiePolicy) {
                                ForEach(PadCookiePolicy.allCases, id: \.self) { policy in
                                    Text(policy.displayName).tag(policy)
                                }
                            }
                            Toggle("URL 内の追跡パラメータを取り除く", isOn: $stripTrackingParameters)
                            Toggle("危険なサイトを警告する", isOn: $harmfulSiteWarningEnabled)
                        }
                        Section("メモ") {
                            Text("広告や追跡の強いブロック、サイトごとの権限管理、ダウンロード一覧は iPad 版で順次追加します。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                    case .data:
                        Section("保存データ") {
                            LabeledContent("履歴") {
                                Text("\(historyCount)件")
                            }
                            LabeledContent("ブックマーク") {
                                Text("\(bookmarkCount)件")
                            }
                        }
                        Section("一覧を開く") {
                            Button("履歴を見る") {
                                dismiss()
                                onOpenHistory()
                            }
                            Button("ブックマークを見る") {
                                dismiss()
                                onOpenBookmarks()
                            }
                            Button("ダウンロードを見る") {
                                dismiss()
                                onOpenDownloads()
                            }
                        }
                        Section("消去") {
                            Button("履歴を削除") {
                                PadBrowsingHistoryStore.shared.clear()
                                historyCount = 0
                            }
                            Button("ブックマークを削除") {
                                PadBookmarkStore.shared.clear()
                                bookmarkCount = 0
                            }
                            Button("Cookie とキャッシュを削除") {
                                Task {
                                    await PadWebsiteDataCleaner.clearCookiesAndCache()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        PadBrowserPreferences.shared.homePageURLString = homePageURLString
                        PadBrowserPreferences.shared.searchTemplate = searchTemplate
                        PadBrowserPreferences.shared.preferredContentLanguage = preferredContentLanguage
                        PadBrowserPreferences.shared.gestureSensitivity = gestureSensitivity
                        PadBrowserPreferences.shared.autoHideBottomBar = autoHideBottomBar
                        PadBrowserPreferences.shared.bottomBarAutoHideDelay = bottomBarAutoHideDelay
                        PadBrowserPreferences.shared.restoreClosedTabPageHistory = restoreClosedTabPageHistory
                        PadBrowserPreferences.shared.allowsJavaScript = allowsJavaScript
                        PadBrowserPreferences.shared.preferHTTPS = preferHTTPS
                        PadBrowserPreferences.shared.stripTrackingParameters = stripTrackingParameters
                        PadBrowserPreferences.shared.harmfulSiteWarningEnabled = harmfulSiteWarningEnabled
                        PadBrowserPreferences.shared.cookiePolicy = cookiePolicy
                        onDone()
                        dismiss()
                    }
                }
            }
        }
    }
}

private enum PadWebsiteDataCleaner {
    static func clearCookiesAndCache() async {
        let store = WKWebsiteDataStore.default()
        let types: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeOfflineWebApplicationCache
        ]
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records)
    }
}

private struct PadLibraryPanelSheet: View {
    let panel: PadBrowserRootView.LibraryPanel
    @ObservedObject var model: PadBrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                switch panel {
                case .history:
                    ForEach(filteredHistory) { item in
                        Button {
                            model.openHistoryItem(item)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline).lineLimit(1)
                                Text(item.urlString).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.map { filteredHistory[$0].id })
                        model.removeHistoryItems(ids)
                    }

                case .bookmarks:
                    ForEach(filteredBookmarks) { item in
                        Button {
                            model.openBookmarkItem(item)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline).lineLimit(1)
                                Text(item.urlString).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.map { filteredBookmarks[$0].id })
                        model.removeBookmarkItems(ids)
                    }

                case .downloads:
                    ForEach(filteredDownloads) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.destinationURL.lastPathComponent)
                                .font(.headline)
                                .lineLimit(1)
                            Text(item.sourceURL?.host ?? item.sourceURLString)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            ShareLink(item: item.destinationURL) {
                                Label("開く / 共有", systemImage: "square.and.arrow.up")
                                    .font(.footnote)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .searchable(text: $searchText, prompt: searchPrompt)
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch panel {
        case .history: return "履歴"
        case .bookmarks: return "ブックマーク"
        case .downloads: return "ダウンロード"
        }
    }

    private var searchPrompt: String {
        switch panel {
        case .history: return "履歴を検索"
        case .bookmarks: return "ブックマークを検索"
        case .downloads: return "ダウンロードを検索"
        }
    }

    private var filteredHistory: [PadBrowsingItem] {
        let items = model.allHistory()
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.urlString.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredBookmarks: [PadBrowsingItem] {
        let items = model.allBookmarks()
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.urlString.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredDownloads: [PadDownloadItem] {
        let items = model.allDownloads()
        guard !searchText.isEmpty else { return items }
        return items.filter {
            $0.destinationURL.lastPathComponent.localizedCaseInsensitiveContains(searchText) ||
            $0.sourceURLString.localizedCaseInsensitiveContains(searchText)
        }
    }
}

private struct PadTabThumbnail: View {
    @ObservedObject var tab: PadBrowserModel.Tab
    let isSelected: Bool
    let onSelect: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.22) : Color.black.opacity(0.14))
                Group {
                    if let image = tab.thumbnail {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.black.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "globe")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(3)
            }
            .frame(width: 80, height: 46)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.24) : .clear, radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    onLongPress()
                }
        )
    }
}

private struct PadTabEditSheet: View {
    @ObservedObject var tab: PadBrowserModel.Tab
    @Binding var currentURL: String
    let isBookmarked: Bool
    let onToggleBookmark: () -> Void
    let onOpenURL: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Edit Tab")
                    .font(.title3.weight(.semibold))
                Text(tab.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TextField("Enter URL or search", text: $currentURL)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.go)
                .onSubmit {
                    onOpenURL()
                }

            HStack(spacing: 12) {
                Button(action: onOpenURL) {
                    Label("Open", systemImage: "arrow.forward.circle")
                }
                .buttonStyle(.borderedProminent)

                Button(action: onToggleBookmark) {
                    Label(isBookmarked ? "Remove Bookmark" : "Add Bookmark", systemImage: isBookmarked ? "star.slash" : "star")
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .presentationBackground(.regularMaterial)
    }
}
