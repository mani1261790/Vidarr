import SwiftUI

struct PadBrowserRootView: View {
    private struct TabSwitchTransition: Identifiable {
        let id = UUID()
        let fromTab: PadBrowserModel.Tab
        let toTab: PadBrowserModel.Tab
        let direction: CGFloat
    }

    @StateObject private var model = PadBrowserModel()
    @State private var gestureHUD: PadGestureHUDState?
    @State private var gestureHUDTask: Task<Void, Never>?
    @State private var bottomBarVisible = true
    @State private var bottomBarHideTask: Task<Void, Never>?
    @State private var editingTabID: UUID?
    @State private var editingURL = ""
    @State private var showingSettings = false
    @State private var tabSwitchTransition: TabSwitchTransition?
    @State private var tabSwitchProgress: CGFloat = 0
    @State private var tabSwitchToken = UUID()
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
                onDone: {
                    model.refreshPreferences()
                    showingSettings = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
                    let width = max(proxy.size.width, 1)
                    PadWebView(webView: transition.fromTab.webView)
                        .id("from-\(transition.id)")
                        .ignoresSafeArea()
                        .offset(x: -transition.direction * width * tabSwitchProgress)
                    PadWebView(webView: transition.toTab.webView)
                        .id("to-\(transition.id)")
                        .ignoresSafeArea()
                        .offset(x: transition.direction * width * (1 - tabSwitchProgress))
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
                    model.newTab()
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
                animateTabSelection(to: model.tabs[currentIndex - 1].id)
            }
        case .nextTab:
            if let currentID = model.selectedTab?.id,
               let currentIndex = model.tabIndex(for: currentID),
               currentIndex < model.tabs.count - 1 {
                animateTabSelection(to: model.tabs[currentIndex + 1].id)
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
            model.newTab()
        }
        showBottomBar()
        showCommittedGestureHUD(for: action)
    }

    private func showCommittedGestureHUD(for action: PadGestureAction) {
        let committedState = PadGestureHUDState(
            action: action,
            title: title(for: action),
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
            onCommit: { action in
                performGesture(action)
            },
            onCancel: {
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
        model.selectTab(id: id)
        guard let toTab = model.selectedTab else { return }

        let token = UUID()
        tabSwitchToken = token
        tabSwitchTransition = TabSwitchTransition(fromTab: fromTab, toTab: toTab, direction: direction)
        tabSwitchProgress = 0

        withAnimation(.easeInOut(duration: 0.24)) {
            tabSwitchProgress = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
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
    @State private var homePageURLString = PadBrowserPreferences.shared.homePageURLString
    @State private var searchTemplate = PadBrowserPreferences.shared.searchTemplate
    @State private var preferredContentLanguage = PadBrowserPreferences.shared.preferredContentLanguage
    @State private var gestureSensitivity = PadBrowserPreferences.shared.gestureSensitivity
    @State private var restoreClosedTabPageHistory = PadBrowserPreferences.shared.restoreClosedTabPageHistory
    @State private var autoHideBottomBar = PadBrowserPreferences.shared.autoHideBottomBar
    @State private var bottomBarAutoHideDelay = PadBrowserPreferences.shared.bottomBarAutoHideDelay

    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("スタートページ", text: $homePageURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("検索するときのURL", text: $searchTemplate)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Webページの表示言語", selection: $preferredContentLanguage) {
                        ForEach(PadPreferredContentLanguage.allCases, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                }

                Section("ジェスチャー") {
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
                        Picker("再表示までの時間", selection: $bottomBarAutoHideDelay) {
                            ForEach(PadBottomBarAutoHideDelay.allCases, id: \.self) { delay in
                                Text(delay.displayName).tag(delay)
                            }
                        }
                    }
                }

                Section("タブ") {
                    Toggle("閉じたタブを復元したとき、前に見ていたページ履歴も戻す", isOn: $restoreClosedTabPageHistory)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        PadBrowserPreferences.shared.homePageURLString = homePageURLString
                        PadBrowserPreferences.shared.searchTemplate = searchTemplate
                        PadBrowserPreferences.shared.preferredContentLanguage = preferredContentLanguage
                        PadBrowserPreferences.shared.gestureSensitivity = gestureSensitivity
                        PadBrowserPreferences.shared.autoHideBottomBar = autoHideBottomBar
                        PadBrowserPreferences.shared.bottomBarAutoHideDelay = bottomBarAutoHideDelay
                        PadBrowserPreferences.shared.restoreClosedTabPageHistory = restoreClosedTabPageHistory
                        onDone()
                    }
                }
            }
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
