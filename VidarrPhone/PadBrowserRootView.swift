import SwiftUI
import UIKit
import WebKit

struct PadBrowserRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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

    private struct ProtectedClosePrompt: Identifiable {
        let id = UUID()
        let tabID: UUID
        let title: String
    }

    @StateObject private var model = PadBrowserModel()
    @State private var gestureHUD: PadGestureHUDState?
    @State private var gestureHUDTask: Task<Void, Never>?
    @State private var bottomBarVisible = true
    @State private var bottomBarHideTask: Task<Void, Never>?
    @State private var bottomRevealHintOpacity: CGFloat = 0.92
    @State private var bottomRevealHintTask: Task<Void, Never>?
    @State private var showsGroupStripStack = false
    @State private var editingTabID: UUID?
    @State private var editingURL = ""
    @State private var showingQuickSearch = false
    @State private var quickSearchQuery = ""
    @State private var showingSettings = false
    @State private var activeLibraryPanel: LibraryPanel?
    @State private var protectedClosePrompt: ProtectedClosePrompt?
    @State private var tabSwitchTransition: TabSwitchTransition?
    @State private var tabSwitchVisualState: PadTabTransitionVisualState = .identity
    @State private var tabSwitchToken = UUID()
    @State private var interactiveTargetID: UUID?
    @State private var webViewportWidth: CGFloat = 1
    @State private var edgePreviewTabID: UUID?
    @State private var stripBirthTabID: UUID?
    @State private var destructiveDismissTabID: UUID?
    @State private var tabStripFrames: [UUID: CGRect] = [:]
    @State private var tabStripBounds: CGRect = .zero
    @State private var stripBirthPosition: CGPoint = .zero
    @State private var stripBirthOpacity: CGFloat = 0
    @State private var stripBirthScale: CGFloat = 0.7
    @State private var lastCommittedTabTransitionAt: CFTimeInterval = 0
    @FocusState private var editingURLFocused: Bool

    private var isPhoneLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact
    }

    private var stackedStripLeadingWidth: CGFloat { isPhoneLayout ? 78 : 164 }
    private var stackedStripTrailingWidth: CGFloat { isPhoneLayout ? 34 : 82 }
    private var bottomBarHorizontalPadding: CGFloat { isPhoneLayout ? 10 : 18 }
    private var bottomBarBottomPadding: CGFloat { isPhoneLayout ? 4 : 6 }
    private var bottomBarSpacing: CGFloat { isPhoneLayout ? 8 : 12 }
    private var chromeControlSpacing: CGFloat { isPhoneLayout ? 6 : 10 }
    private var chromeButtonSize: CGFloat { isPhoneLayout ? 28 : 30 }
    private var groupButtonSize: CGFloat { isPhoneLayout ? 28 : 30 }
    private var tabThumbnailWidth: CGFloat { isPhoneLayout ? 64 : 80 }
    private var tabThumbnailHeight: CGFloat { isPhoneLayout ? 38 : 46 }
    private var tabStripHeight: CGFloat { isPhoneLayout ? 44 : 52 }
    private var tabStripSpacing: CGFloat { isPhoneLayout ? 8 : 12 }
    private var barCornerRadius: CGFloat { isPhoneLayout ? 18 : 20 }
    private var groupStripHeight: CGFloat { isPhoneLayout ? 44 : 52 }
    private var groupStripOffsetStep: CGFloat { isPhoneLayout ? 52 : 60 }
    private var compactSheetDetents: Set<PresentationDetent> { isPhoneLayout ? [.large] : [.medium] }
    private var settingsSheetDetents: Set<PresentationDetent> { isPhoneLayout ? [.large] : [.medium, .large] }
    private var librarySheetDetents: Set<PresentationDetent> { isPhoneLayout ? [.large] : [.medium, .large] }
    private var quickSearchDetents: Set<PresentationDetent> { isPhoneLayout ? [.fraction(0.34)] : [.fraction(0.26)] }

    var body: some View {
        ZStack(alignment: .bottom) {
            webLayer
            if showsGroupStripStack {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissGroupStripStack()
                    }
            }
            if showsGroupStripStack {
                groupStripStackOverlay
                    .padding(.horizontal, bottomBarHorizontalPadding)
                    .padding(.bottom, bottomBarBottomPadding)
                    .transition(.identity)
            }
            bottomBar
                .padding(.horizontal, bottomBarHorizontalPadding)
                .padding(.bottom, bottomBarBottomPadding)
                .offset(y: bottomBarVisible ? 0 : 96)
                .opacity(bottomBarVisible ? 1 : 0.001)
                .allowsHitTesting(bottomBarVisible)
            if !bottomBarVisible && !showsGroupStripStack {
                bottomRevealZone
            }
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(item: editingTabBinding) { tab in
            PadTabEditSheet(
                tab: tab,
                currentURL: bindingForEditingURL(),
                isBookmarked: model.isBookmarked(tab),
                isDangerousSiteAllowed: model.isDangerousSiteAllowed(for: tab),
                onToggleBookmark: {
                    model.selectTab(id: tab.id)
                    model.toggleBookmarkForSelectedTab()
                },
                onToggleProtection: {
                    model.selectTab(id: tab.id)
                    model.toggleProtectionForSelectedTab()
                },
                onToggleDangerousSiteAllowed: {
                    model.selectTab(id: tab.id)
                    model.toggleDangerousSiteAllowedForSelectedTab()
                },
                onReload: {
                    model.selectTab(id: tab.id)
                    model.reload()
                },
                onShare: {
                    model.selectTab(id: tab.id)
                },
                onOpenURL: {
                    model.selectTab(id: tab.id)
                    model.loadSelectedTab(with: editingURL)
                },
                onFindInPage: { query, completion in
                    model.selectTab(id: tab.id)
                    model.findInSelectedPage(query, completion: completion)
                }
            )
            .presentationDetents(compactSheetDetents)
            .presentationDragIndicator(.visible)
            .onAppear {
                editingURL = tab.urlString
            }
        }
        .sheet(isPresented: $showingQuickSearch) {
            PadQuickSearchSheet(
                query: $quickSearchQuery,
                onSubmit: { input in
                    model.openQuickSearch(input)
                    showingQuickSearch = false
                    showBottomBar()
                }
            )
            .presentationDetents(quickSearchDetents)
            .presentationDragIndicator(.visible)
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
            .presentationDetents(settingsSheetDetents)
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $activeLibraryPanel) { panel in
            PadLibraryPanelSheet(
                panel: panel,
                model: model
            )
            .presentationDetents(librarySheetDetents)
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
        .alert(item: $protectedClosePrompt) { prompt in
            Alert(
                title: Text("保護されたタブを閉じますか？"),
                message: Text("「\(prompt.title)」は保護されています。閉じるには確認が必要です。"),
                primaryButton: .destructive(Text("閉じる")) {
                    model.closeTab(id: prompt.tabID)
                },
                secondaryButton: .cancel(Text("キャンセル"))
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
                PadWebStageView(
                    selectedWebView: tabSwitchTransition == nil ? model.selectedTab?.webView : nil,
                    transitionFromWebView: tabSwitchTransition?.fromTab.webView,
                    transitionToWebView: tabSwitchTransition?.toTab.webView,
                    transitionVisualState: tabSwitchTransition == nil ? nil : tabSwitchVisualState,
                    gestureConfiguration: (tabSwitchTransition != nil && interactiveTargetID != nil) || (tabSwitchTransition == nil)
                        ? gestureConfiguration
                        : nil
                )
                .ignoresSafeArea()

                if tabSwitchTransition == nil, model.selectedTab == nil {
                    ContentUnavailableView("No Tab", systemImage: "square.on.square")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let gestureHUD {
                    PadGestureHUD(state: gestureHUD)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .onAppear {
                webViewportWidth = max(proxy.size.width, 1)
            }
            .onChange(of: proxy.size.width) { _, width in
                webViewportWidth = max(width, 1)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: bottomBarSpacing) {
            HStack(spacing: chromeControlSpacing) {
                chromeButton(systemName: "chevron.left", disabled: !model.canGoBack(), action: model.goBack)
                chromeButton(systemName: "chevron.right", disabled: !model.canGoForward(), action: model.goForward)
                chromeButton(systemName: "arrow.clockwise", disabled: false, action: model.reload)
            }

            groupSwitcher

            tabStrip

            HStack(spacing: chromeControlSpacing) {
                chromeButton(systemName: "gearshape", disabled: false) {
                    showingSettings = true
                }
                chromeButton(systemName: "plus", disabled: false) {
                    animateNewTabCreation()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isPhoneLayout ? 5 : 6)
        .background(
            PadLiquidGlassBackground(cornerRadius: barCornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                .strokeBorder(chromeForegroundColor.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.11), radius: isPhoneLayout ? 12 : 14, y: isPhoneLayout ? 4 : 6)
    }

    private var groupSwitcher: some View {
        Button {
            if showsGroupStripStack {
                dismissGroupStripStack()
            } else {
                showGroupStripStack()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(uiColor: model.currentGroup.accentColor).opacity(0.14))
                Image(systemName: model.currentGroup.systemImage)
                    .font(.system(size: isPhoneLayout ? 14 : 15, weight: .semibold))
                    .foregroundStyle(chromeForegroundColor)
            }
            .frame(width: groupButtonSize, height: groupButtonSize)
        }
        .buttonStyle(.plain)
    }

    private var groupStripStackOverlay: some View {
        let groups = stackedGroups
        return ZStack(alignment: .bottom) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                groupStripStackRow(for: group, index: index)
            }
        }
        .allowsHitTesting(showsGroupStripStack)
    }

    private func groupStripStackRow(for group: PadBrowserTabGroup, index: Int) -> some View {
        let yOffset = showsGroupStripStack ? -(CGFloat(index + 1) * groupStripOffsetStep) : 0
        let rowScale: CGFloat = showsGroupStripStack ? 1 : 0.96
        let rowOpacity: CGFloat = showsGroupStripStack ? 1 : 0
        let animation = Animation.spring(response: 0.34, dampingFraction: 0.86).delay(Double(index) * 0.03)

        return compactGroupStrip(for: group)
            .offset(y: yOffset)
            .opacity(rowOpacity)
            .scaleEffect(rowScale, anchor: .bottom)
            .animation(animation, value: showsGroupStripStack)
    }

    private var bottomRevealZone: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(chromeForegroundColor.opacity(0.92))
                .frame(width: 42, height: 5)
            Image(systemName: "chevron.up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(chromeForegroundColor.opacity(0.92))
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, revealGradientColor.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .contentShape(Rectangle())
        .ignoresSafeArea(edges: .bottom)
        .opacity(bottomRevealHintOpacity)
        .onTapGesture {
            showBottomBar()
        }
    }

    private var tabStrip: some View {
        interactiveTabStrip(
            tabs: model.tabs,
            group: model.currentGroup,
            selectedTabID: model.selectedTab?.id
        )
        .coordinateSpace(name: "PadTabStripSpace")
        .onPreferenceChange(PadTabFramePreferenceKey.self) { frames in
            tabStripFrames = frames
        }
        .overlay(alignment: .topLeading) {
            if stripBirthOpacity > 0.001 {
                ZStack {
                    Circle()
                        .fill(chromeForegroundColor.opacity(0.96))
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(chromeBackgroundAccent.opacity(0.82))
                }
                .frame(width: 20, height: 20)
                .position(stripBirthPosition)
                .scaleEffect(stripBirthScale)
                .opacity(stripBirthOpacity)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: tabStripHeight)
    }

    private func interactiveTabStrip(
        tabs: [PadBrowserModel.Tab],
        group: PadBrowserTabGroup,
        selectedTabID: UUID?
    ) -> some View {
        GeometryReader { stripProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: tabStripSpacing) {
                    ForEach(tabs) { tab in
                        PadTabThumbnail(
                            tab: tab,
                            isSelected: selectedTabID == tab.id,
                            isBookmarked: model.isBookmarked(tab),
                            groupAccentColor: Color(uiColor: group.accentColor),
                            showsBirthPulse: stripBirthTabID == tab.id,
                            showsDestructiveDismiss: destructiveDismissTabID == tab.id,
                            onSelect: {
                                animateTabSelection(to: tab.id)
                            },
                            onLongPress: {
                                animateTabSelection(to: tab.id)
                                editingURL = tab.urlString
                                editingTabID = tab.id
                            },
                            onDoubleTap: {
                                animateTabSelection(to: tab.id)
                                model.toggleProtectionForSelectedTab()
                                showBottomBar()
                            },
                            onSwipeDown: {
                                animateTabSelection(to: tab.id)
                                if tab.isProtected {
                                    protectedClosePrompt = ProtectedClosePrompt(tabID: tab.id, title: tab.title)
                                } else {
                                    animateDestructiveClose(for: tab.id)
                                }
                                showBottomBar()
                            },
                            thumbnailWidth: tabThumbnailWidth,
                            thumbnailHeight: tabThumbnailHeight
                        )
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(
                                        key: PadTabFramePreferenceKey.self,
                                        value: [tab.id: proxy.frame(in: .named("PadTabStripSpace"))]
                                    )
                            }
                        )
                    }
                }
                .frame(minWidth: stripProxy.size.width, alignment: .center)
                .padding(.horizontal, 4)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            tabStripBounds = proxy.frame(in: .named("PadTabStripSpace"))
                        }
                        .onChange(of: proxy.size) { _, _ in
                            tabStripBounds = proxy.frame(in: .named("PadTabStripSpace"))
                        }
                }
            )
        }
    }

    private func compactGroupStrip(for group: PadBrowserTabGroup) -> some View {
        let groupTabs = model.tabs(in: group)
        let selectedTabID = model.selectedTabID(in: group)
        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: group.systemImage)
                    .font(.system(size: isPhoneLayout ? 14 : 15, weight: .semibold))
                    .foregroundStyle(Color(uiColor: group.accentColor))
            }
            .padding(.leading, isPhoneLayout ? 12 : 16)
            .frame(width: stackedStripLeadingWidth, alignment: .leading)

            GeometryReader { stripProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: tabStripSpacing) {
                        if groupTabs.isEmpty {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color(uiColor: group.accentColor).opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(Color(uiColor: group.accentColor).opacity(0.26), lineWidth: 1)
                                )
                                .frame(width: tabThumbnailWidth, height: tabThumbnailHeight)
                        } else {
                            ForEach(groupTabs) { tab in
                                PadTabThumbnail(
                                    tab: tab,
                                    isSelected: selectedTabID == tab.id,
                                    isBookmarked: model.isBookmarked(tab),
                                    groupAccentColor: Color(uiColor: group.accentColor),
                                    showsBirthPulse: false,
                                    showsDestructiveDismiss: false,
                                    onSelect: {
                                        model.selectTab(in: group, id: tab.id)
                                        dismissGroupStripStack()
                                        showBottomBar()
                                    },
                                    onLongPress: {},
                                    onDoubleTap: {},
                                    onSwipeDown: {},
                                    thumbnailWidth: tabThumbnailWidth,
                                    thumbnailHeight: tabThumbnailHeight
                                )
                            }
                        }
                    }
                    .frame(minWidth: stripProxy.size.width, alignment: .center)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Button {
                    model.closeAllTabs(in: group)
                    showBottomBar(persist: true)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: isPhoneLayout ? 13 : 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(chromeForegroundColor.opacity(0.92))
            }
            .padding(.trailing, isPhoneLayout ? 12 : 16)
            .frame(width: stackedStripTrailingWidth, alignment: .trailing)
        }
        .frame(height: groupStripHeight)
        .background(PadLiquidGlassBackground(cornerRadius: isPhoneLayout ? 16 : 18))
        .overlay(
            RoundedRectangle(cornerRadius: isPhoneLayout ? 16 : 18, style: .continuous)
                .stroke(Color(uiColor: group.accentColor).opacity(0.20), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: isPhoneLayout ? 16 : 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: isPhoneLayout ? 8 : 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: isPhoneLayout ? 16 : 18, style: .continuous))
        .onTapGesture {
            if groupTabs.isEmpty {
                model.switchGroup(group)
                dismissGroupStripStack()
                showBottomBar()
            }
        }
    }

    private var stackedGroups: [PadBrowserTabGroup] {
        model.availableGroups.filter { $0 != model.currentGroup }
    }

    private func chromeButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: isPhoneLayout ? 14 : 15, weight: .semibold))
                .frame(width: chromeButtonSize, height: chromeButtonSize)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? chromeDisabledColor : chromeForegroundColor)
        .disabled(disabled)
        .simultaneousGesture(
            TapGesture().onEnded {
                showBottomBar()
            }
        )
    }

    private var chromeForegroundColor: Color {
        prefersLightChrome
            ? Color.white.opacity(0.96)
            : Color.black.opacity(0.80)
    }

    private var chromeDisabledColor: Color {
        chromeForegroundColor.opacity(0.42)
    }

    private var revealGradientColor: Color {
        prefersLightChrome ? .black : .white
    }

    private var chromeBackgroundAccent: Color {
        prefersLightChrome ? .black : .white
    }

    private var prefersLightChrome: Bool {
        if let thumbnail = model.selectedTab?.thumbnail,
           let brightness = thumbnail.averagePerceivedBrightness {
            return brightness < 0.57
        }
        return colorScheme == .dark
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
                if let tab = model.selectedTab, tab.isProtected {
                    protectedClosePrompt = ProtectedClosePrompt(tabID: id, title: tab.title)
                } else {
                    model.closeTab(id: id)
                }
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
            model.openSearchPageInNewTab()
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
            onHorizontalSwipeDrag: { action, totalX in
                updateInteractiveTabSwitch(for: action, totalX: totalX)
            },
            onHorizontalSwipeFinish: { action, totalX in
                finishInteractiveTabSwitch(for: action, totalX: totalX)
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
        tabSwitchVisualState = initialVisualState(for: direction, emphasizeBirth: false)
        interactiveTargetID = nil
        edgePreviewTabID = nil
        runCommitAnimation(
            token: token,
            transition: tabSwitchTransition!,
            shouldSelectTarget: true,
            startFromCurrentFrames: false,
            emphasizeBirth: false
        )
    }

    private func updateInteractiveTabSwitch(for action: PadGestureAction, totalX: CGFloat) {
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
            guard currentIndex < model.tabs.count - 1 else {
                prepareRightEdgeNewTabPreview(totalX: totalX)
                return
            }
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
            edgePreviewTabID = nil
        }
        tabSwitchVisualState = interactiveVisualState(for: direction, totalX: totalX)
    }

    private func cancelInteractiveTabSwitch() {
        guard tabSwitchTransition != nil, interactiveTargetID != nil else { return }
        let token = UUID()
        tabSwitchToken = token
        let width = max(webViewportWidth, 1)
        let travel = width + 16
        let remaining = abs(tabSwitchVisualState.fromX)
        let normalized = min(1.0, max(0.0, remaining / max(travel, 1)))
        let duration = 0.16 + (0.08 * normalized)

        withAnimation(.easeInOut(duration: duration)) {
            tabSwitchVisualState = .identity
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int((duration * 1000).rounded(.up)) + 10))
            guard tabSwitchToken == token else { return }
            if let edgePreviewTabID {
                model.discardTab(id: edgePreviewTabID)
                self.edgePreviewTabID = nil
            }
            tabSwitchTransition = nil
            tabSwitchVisualState = .identity
            interactiveTargetID = nil
        }
    }

    private func finishInteractiveTabSwitch(for action: PadGestureAction, totalX: CGFloat) {
        guard let transition = tabSwitchTransition, interactiveTargetID != nil else {
            performGesture(action)
            return
        }

        let width = max(webViewportWidth, 1)
        let gap: CGFloat = 16
        let fullTravel = width + gap
        let commitThreshold = max(84, width * 0.18)
        let shouldCommit: Bool

        switch action {
        case .nextTab:
            shouldCommit = totalX <= -commitThreshold
        case .previousTab:
            shouldCommit = totalX >= commitThreshold
        default:
            shouldCommit = true
        }

        let currentFromX = tabSwitchVisualState.fromX
        let fromTargetX: CGFloat = shouldCommit ? (-transition.direction * fullTravel) : 0
        let remaining = abs(fromTargetX - currentFromX)
        let normalized = min(1.0, max(0.0, remaining / max(fullTravel, 1)))
        let duration = 0.16 + (0.08 * normalized)
        let token = UUID()
        tabSwitchToken = token

        if shouldCommit {
            runCommitAnimation(
                token: token,
                transition: transition,
                shouldSelectTarget: true,
                startFromCurrentFrames: true,
                emphasizeBirth: false
            )
        } else {
            withAnimation(.easeInOut(duration: duration)) {
                tabSwitchVisualState = .identity
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int((duration * 1000).rounded(.up)) + 10))
                guard tabSwitchToken == token else { return }
                if let edgePreviewTabID {
                    model.discardTab(id: edgePreviewTabID)
                    self.edgePreviewTabID = nil
                }
                tabSwitchTransition = nil
                tabSwitchVisualState = .identity
                interactiveTargetID = nil
            }
        }
    }

    private func animateNewTabCreation() {
        showBottomBar()
        let fromTab = model.selectedTab
        model.newTab()
        guard let fromTab, let toTab = model.selectedTab else { return }
        triggerStripBirth(for: toTab.id, fromRightEdge: false)

        let token = UUID()
        tabSwitchToken = token
        tabSwitchTransition = TabSwitchTransition(fromTab: fromTab, toTab: toTab, direction: 1, mode: .newTab)
        tabSwitchVisualState = initialVisualState(for: 1, emphasizeBirth: true)
        interactiveTargetID = nil
        edgePreviewTabID = nil
        runCommitAnimation(
            token: token,
            transition: tabSwitchTransition!,
            shouldSelectTarget: false,
            startFromCurrentFrames: false,
            emphasizeBirth: true
        )
    }

    private func prepareRightEdgeNewTabPreview(totalX: CGFloat) {
        guard let fromTab = model.selectedTab else { return }
        let previewTab: PadBrowserModel.Tab
        if let edgePreviewTabID,
           let existing = model.tabs.first(where: { $0.id == edgePreviewTabID }) {
            previewTab = existing
        } else {
            let created = model.addBackgroundTab(initialURL: PadBrowserPreferences.shared.homePageURL)
            edgePreviewTabID = created.id
            triggerStripBirth(for: created.id, fromRightEdge: true)
            previewTab = created
        }

        if interactiveTargetID != previewTab.id || tabSwitchTransition == nil {
            tabSwitchTransition = TabSwitchTransition(fromTab: fromTab, toTab: previewTab, direction: 1, mode: .newTab)
            interactiveTargetID = previewTab.id
        }
        tabSwitchVisualState = interactiveVisualState(for: 1, totalX: totalX)
    }

    private func showBottomBar(persist: Bool = false) {
        bottomBarHideTask?.cancel()
        bottomRevealHintTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            bottomBarVisible = true
        }
        if !persist {
            scheduleBottomBarAutoHide()
        }
    }

    private func showGroupStripStack() {
        showBottomBar(persist: true)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            showsGroupStripStack = true
        }
    }

    private func dismissGroupStripStack() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            showsGroupStripStack = false
        }
        scheduleBottomBarAutoHide()
    }

    private func scheduleBottomBarAutoHide() {
        bottomBarHideTask?.cancel()
        guard PadBrowserPreferences.shared.autoHideBottomBar else {
            withAnimation(.easeOut(duration: 0.18)) {
                bottomBarVisible = true
            }
            return
        }
        guard !showingSettings, editingTabID == nil, !showsGroupStripStack else { return }
        let delay = PadBrowserPreferences.shared.bottomBarAutoHideDelay.seconds
        bottomBarHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                bottomBarVisible = false
            }
            scheduleBottomRevealHintFade()
        }
    }

    private func triggerStripBirth(for tabID: UUID, fromRightEdge: Bool) {
        stripBirthTabID = tabID
        Task { @MainActor in
            if fromRightEdge {
                try? await Task.sleep(for: .milliseconds(16))
                if let targetFrame = tabStripFrames[tabID] {
                    let start = CGPoint(x: max(18, tabStripBounds.maxX - 14), y: targetFrame.midY)
                    stripBirthPosition = start
                    stripBirthScale = 0.85
                    stripBirthOpacity = 0
                    withAnimation(.easeOut(duration: 0.10)) {
                        stripBirthOpacity = 1
                        stripBirthScale = 1.05
                    }
                    withAnimation(.easeInOut(duration: 0.24)) {
                        stripBirthPosition = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
                        stripBirthScale = 0.92
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation(.easeOut(duration: 0.14)) {
                        stripBirthOpacity = 0
                        stripBirthScale = 0.74
                    }
                } else {
                    stripBirthOpacity = 0
                }
            }
            try? await Task.sleep(for: .milliseconds(520))
            if stripBirthTabID == tabID {
                stripBirthTabID = nil
            }
        }
    }

    private func interactiveVisualState(for direction: CGFloat, totalX: CGFloat) -> PadTabTransitionVisualState {
        let width = max(webViewportWidth, 1)
        let gap: CGFloat = 16
        let travel = width + gap
        let clampedFromX = min(travel * 0.82, max(-travel * 0.82, totalX))
        let toX = (direction * travel) + clampedFromX
        let progress = min(1, abs(clampedFromX) / max(travel, 1))
        return PadTabTransitionVisualState(
            fromX: clampedFromX,
            toX: toX,
            fromAlpha: 1.0 - (progress * 0.18),
            toAlpha: 0.9 + (progress * 0.1),
            dimAlpha: progress * 0.10,
            gapAlpha: 0.9,
            toShadowOpacity: Float(0.12 + (progress * 0.10))
        )
    }

    private func initialVisualState(for direction: CGFloat, emphasizeBirth: Bool) -> PadTabTransitionVisualState {
        let width = max(webViewportWidth, 1)
        let gap: CGFloat = 16
        let travel = width + gap
        let entryTravel = travel + (emphasizeBirth ? 24 : 0)
        return PadTabTransitionVisualState(
            fromX: 0,
            toX: direction * entryTravel,
            fromAlpha: 1,
            toAlpha: 0.9,
            dimAlpha: 0,
            gapAlpha: 0.9,
            toShadowOpacity: 0.22
        )
    }

    private func runCommitAnimation(
        token: UUID,
        transition: TabSwitchTransition,
        shouldSelectTarget: Bool,
        startFromCurrentFrames: Bool,
        emphasizeBirth: Bool
    ) {
        let width = max(webViewportWidth, 1)
        let gap: CGFloat = 16
        let offscreenTravel = width + gap
        let directionSign = -transition.direction
        let now = CACurrentMediaTime()
        let isChained = (now - lastCommittedTabTransitionAt) < 0.42

        let fromMidX = directionSign * width * (emphasizeBirth ? (isChained ? 0.34 : 0.40) : (isChained ? 0.24 : 0.30))
        let fromFinalX = directionSign * offscreenTravel
        let fromOvershootMagnitude = max(isChained ? 4 : 8, min(isChained ? 12 : 18, width * (isChained ? 0.010 : 0.016)))
        let fromOvershootX = fromFinalX + (directionSign * fromOvershootMagnitude)
        let toMidX = -directionSign * width * (emphasizeBirth ? (isChained ? 0.10 : 0.14) : (isChained ? 0.08 : 0.11))
        let toOvershootMagnitude = max(isChained ? 4 : 8, min(isChained ? 10 : 16, width * (isChained ? 0.009 : 0.014)))
        let toOvershootX = directionSign * toOvershootMagnitude

        if !startFromCurrentFrames {
            tabSwitchVisualState = initialVisualState(for: transition.direction, emphasizeBirth: emphasizeBirth)
        }

        let phase1Duration = emphasizeBirth ? (isChained ? 0.10 : 0.14) : (isChained ? 0.09 : 0.12)
        let phase2Duration = emphasizeBirth ? (isChained ? 0.12 : 0.18) : (isChained ? 0.11 : 0.16)
        let phase3Duration = emphasizeBirth ? (isChained ? 0.10 : 0.13) : (isChained ? 0.09 : 0.12)
        let phase1State = PadTabTransitionVisualState(
            fromX: fromMidX,
            toX: toMidX,
            fromAlpha: isChained ? 0.82 : 0.76,
            toAlpha: 1.0,
            dimAlpha: emphasizeBirth ? (isChained ? 0.14 : 0.20) : (isChained ? 0.10 : 0.16),
            gapAlpha: 0.90,
            toShadowOpacity: 0.22
        )
        let phase2State = PadTabTransitionVisualState(
            fromX: fromOvershootX,
            toX: toOvershootX,
            fromAlpha: isChained ? 0.72 : 0.62,
            toAlpha: 1.0,
            dimAlpha: emphasizeBirth ? (isChained ? 0.14 : 0.20) : (isChained ? 0.10 : 0.16),
            gapAlpha: 0.90,
            toShadowOpacity: isChained ? 0.24 : 0.32
        )
        let phase3State = PadTabTransitionVisualState(
            fromX: fromFinalX,
            toX: 0,
            fromAlpha: 1.0,
            toAlpha: 1.0,
            dimAlpha: 0,
            gapAlpha: 0.16,
            toShadowOpacity: 0.12
        )

        withAnimation(.easeOut(duration: phase1Duration)) {
            tabSwitchVisualState = phase1State
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int((phase1Duration * 1000).rounded(.up)) + 4))
            guard tabSwitchToken == token else { return }
            withAnimation(.easeInOut(duration: phase2Duration)) {
                tabSwitchVisualState = phase2State
            }

            try? await Task.sleep(for: .milliseconds(Int((phase2Duration * 1000).rounded(.up)) + 4))
            guard tabSwitchToken == token else { return }
            withAnimation(.easeOut(duration: phase3Duration)) {
                tabSwitchVisualState = phase3State
            }

            try? await Task.sleep(for: .milliseconds(Int((phase3Duration * 1000).rounded(.up)) + 10))
            guard tabSwitchToken == token else { return }
            lastCommittedTabTransitionAt = CACurrentMediaTime()
            if shouldSelectTarget {
                model.selectTab(id: transition.toTab.id)
            }
            edgePreviewTabID = nil
            tabSwitchTransition = nil
            tabSwitchVisualState = .identity
            interactiveTargetID = nil
        }
    }

    private func animateDestructiveClose(for tabID: UUID) {
        destructiveDismissTabID = tabID
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard destructiveDismissTabID == tabID else { return }
            model.closeTab(id: tabID)
            destructiveDismissTabID = nil
        }
    }

    private func scheduleBottomRevealHintFade() {
        bottomRevealHintTask?.cancel()
        bottomRevealHintOpacity = 0.92
        bottomRevealHintTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                bottomRevealHintOpacity = 0.18
            }
        }
    }
}

private struct PadTabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
    @State private var reopenTabsOnLaunch = PadBrowserPreferences.shared.reopenTabsOnLaunch
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
                        Section("スタートページ") {
                            TextField("", text: $homePageURLString, prompt: Text("Vidarr Start"))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Text("空欄にすると Vidarr Start を開きます。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if !isHomePageInputValid && !homePageURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("スタートページは http または https の URL を入力してください。")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }

                        Section("検索") {
                            TextField("検索するときのURL", text: $searchTemplate)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Text("検索語は {query} に入ります。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if !isSearchTemplateInputValid {
                                Text("検索URLは空欄にできません。{query} を含む http または https の URL を入力してください。")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
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

                        Section("タブと下部バー") {
                            Toggle("前回終了時のタブを次回も開く", isOn: $reopenTabsOnLaunch)
                            Toggle("閉じたタブを復元したとき、前に見ていたページ履歴も戻す", isOn: $restoreClosedTabPageHistory)
                            Toggle("下部のタブバーを自動で隠す", isOn: $autoHideBottomBar)
                            if autoHideBottomBar {
                                Picker("隠れるまでの時間", selection: $bottomBarAutoHideDelay) {
                                    ForEach(PadBottomBarAutoHideDelay.allCases, id: \.self) { delay in
                                        Text(delay.displayName).tag(delay)
                                    }
                                }
                            }
                        }

                        Section("ブックマーク共有") {
                            HStack {
                                Label(
                                    PadBrowserPreferences.shared.bookmarkSyncEnabled ? "同期中" : "未接続",
                                    systemImage: PadBrowserPreferences.shared.bookmarkSyncEnabled ? "checkmark.icloud.fill" : "icloud.slash"
                                )
                                .foregroundStyle(PadBrowserPreferences.shared.bookmarkSyncEnabled ? .green : .secondary)
                                Spacer()
                            }
                            Text(PadBrowserPreferences.shared.bookmarkSyncStatusText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("同期されるのはブックマークのみです。履歴、開いているタブ、Cookie、ダウンロード一覧は同期しません。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
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
                        PadBrowserPreferences.shared.reopenTabsOnLaunch = reopenTabsOnLaunch
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
                    .disabled(!canSave)
                }
            }
        }
    }

    private var isSearchTemplateInputValid: Bool {
        let trimmed = searchTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains("{query}") else { return false }
        let probe = trimmed.replacingOccurrences(of: "{query}", with: "vidarr")
        guard let url = URL(string: probe), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private var isHomePageInputValid: Bool {
        let trimmed = homePageURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private var canSave: Bool {
        isSearchTemplateInputValid && isHomePageInputValid
    }
}

@MainActor
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
    @GestureState private var swipeTranslation: CGSize = .zero
    let isSelected: Bool
    let isBookmarked: Bool
    let groupAccentColor: Color
    let showsBirthPulse: Bool
    let showsDestructiveDismiss: Bool
    let onSelect: () -> Void
    let onLongPress: () -> Void
    let onDoubleTap: () -> Void
    let onSwipeDown: () -> Void
    let thumbnailWidth: CGFloat
    let thumbnailHeight: CGFloat

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(backgroundFill)
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
            .frame(width: thumbnailWidth, height: thumbnailHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topLeading) {
                if tab.isProtected || isBookmarked {
                    ZStack {
                        Circle()
                            .fill(
                                tab.isProtected
                                    ? Color(red: 0.29, green: 0.67, blue: 1.0).opacity(0.96)
                                    : Color(red: 1.0, green: 0.80, blue: 0.15).opacity(0.96)
                            )
                        Image(systemName: tab.isProtected ? "pin.fill" : "star.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.96))
                    }
                    .frame(width: 16, height: 16)
                    .offset(x: 4, y: -4)
                }
            }
            .overlay(alignment: .center) {
                if showsBirthPulse {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.92))
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.78))
                    }
                    .frame(width: 22, height: 22)
                    .scaleEffect(showsBirthPulse ? 1 : 0.7)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .overlay {
                if destructiveVisualProgress > 0 {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.red.opacity(0.18 + (0.18 * destructiveVisualProgress)))
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.96))
                                .scaleEffect(0.84 + (0.16 * destructiveVisualProgress))
                                .opacity(0.72 + (0.28 * destructiveVisualProgress))
                        )
                }
            }
            .shadow(color: shadowColor, radius: 16, y: 6)
            .scaleEffect(destructiveVisualProgress > 0 ? (1 - (0.08 * destructiveVisualProgress)) : 1)
            .offset(y: previewOffsetY)
            .animation(.easeOut(duration: 0.14), value: showsDestructiveDismiss)
            .animation(.easeOut(duration: 0.10), value: destructivePreviewProgress)
        }
        .buttonStyle(.plain)
        .highPriorityGesture(
            TapGesture(count: 2)
                .onEnded {
                    onDoubleTap()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .updating($swipeTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    guard value.translation.height >= 24 else { return }
                    guard abs(value.translation.height) > abs(value.translation.width) * 1.2 else { return }
                    onSwipeDown()
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    onLongPress()
                }
        )
    }

    private var destructivePreviewProgress: CGFloat {
        guard swipeTranslation.height > 0 else { return 0 }
        guard abs(swipeTranslation.height) > abs(swipeTranslation.width) * 1.1 else { return 0 }
        return min(1, max(0, (swipeTranslation.height - 8) / 32))
    }

    private var destructiveVisualProgress: CGFloat {
        max(destructivePreviewProgress, showsDestructiveDismiss ? 1 : 0)
    }

    private var previewOffsetY: CGFloat {
        min(12, max(0, swipeTranslation.height * 0.24))
    }

    private var borderColor: Color {
        if tab.isProtected {
            return Color(red: 1.0, green: 0.48, blue: 0.06).opacity(isSelected ? 0.95 : 0.82)
        }
        if isBookmarked {
            return Color(red: 1.0, green: 0.80, blue: 0.16).opacity(isSelected ? 0.90 : 0.78)
        }
        return isSelected ? groupAccentColor.opacity(0.88) : Color.white.opacity(0.08)
    }

    private var shadowColor: Color {
        if tab.isProtected {
            return Color(red: 1.0, green: 0.48, blue: 0.06).opacity(isSelected ? 0.62 : 0.36)
        }
        if isBookmarked {
            return Color(red: 1.0, green: 0.80, blue: 0.16).opacity(isSelected ? 0.28 : 0.18)
        }
        return isSelected ? groupAccentColor.opacity(0.26) : .clear
    }

    private var backgroundFill: Color {
        if destructiveVisualProgress > 0 {
            return Color.red.opacity(0.16 + (0.16 * destructiveVisualProgress))
        }
        return isSelected ? Color.white.opacity(0.22) : Color.black.opacity(0.14)
    }
}

private struct PadTabEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tab: PadBrowserModel.Tab
    @Binding var currentURL: String
    let isBookmarked: Bool
    let isDangerousSiteAllowed: Bool
    let onToggleBookmark: () -> Void
    let onToggleProtection: () -> Void
    let onToggleDangerousSiteAllowed: () -> Void
    let onReload: () -> Void
    let onShare: () -> Void
    let onOpenURL: () -> Void
    let onFindInPage: (String, @escaping (String?) -> Void) -> Void
    @State private var pageSearchQuery = ""
    @State private var pageSearchResult: String?
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tab.title)
                            .font(.title2.weight(.semibold))
                            .lineLimit(2)
                        if let host = currentHost {
                            Text(host)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("ページ")
                            .font(.headline)
                        TextField("URL または検索語", text: $currentURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.go)
                            .onSubmit { onOpenURL() }
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("タブの操作")
                            .font(.headline)
                        HStack(spacing: 12) {
                            actionButton("開く", systemImage: "arrow.up.right.circle.fill", role: .primary, action: onOpenURL)
                            actionButton("再読み込み", systemImage: "arrow.clockwise.circle.fill", action: onReload)
                        }
                        HStack(spacing: 12) {
                            actionButton("共有", systemImage: "square.and.arrow.up.fill", action: {
                                onShare()
                                showingShareSheet = true
                            })
                            actionButton(isBookmarked ? "ブックマーク解除" : "ブックマーク", systemImage: isBookmarked ? "star.slash.fill" : "star.fill", action: onToggleBookmark)
                            actionButton(tab.isProtected ? "保護を解除" : "保護する", systemImage: tab.isProtected ? "lock.open.fill" : "lock.fill", action: onToggleProtection)
                        }
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("ページ内検索")
                            .font(.headline)
                        HStack(spacing: 12) {
                            TextField("このページを検索", text: $pageSearchQuery)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                                .submitLabel(.search)
                                .onSubmit {
                                    onFindInPage(pageSearchQuery) { result in
                                        pageSearchResult = result
                                    }
                                }
                            Button("検索") {
                                onFindInPage(pageSearchQuery) { result in
                                    pageSearchResult = result
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        if let pageSearchResult, !pageSearchResult.isEmpty {
                            Text(pageSearchResult)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    if currentHost != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("このサイト")
                                .font(.headline)
                            Toggle("危険サイト警告をこのサイトではスキップ", isOn: Binding(
                                get: { isDangerousSiteAllowed },
                                set: { _ in onToggleDangerousSiteAllowed() }
                            ))
                        }
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }
                .padding(20)
            }
            .navigationTitle("タブ設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .presentationBackground(.thinMaterial)
        .sheet(isPresented: $showingShareSheet) {
            if let shareURL = URL(string: currentURL.isEmpty ? tab.urlString : currentURL) {
                PadShareSheet(items: [shareURL])
            }
        }
    }

    private var currentHost: String? {
        URL(string: currentURL.isEmpty ? tab.urlString : currentURL)?.host
    }

    @ViewBuilder
    private func actionButton(_ title: String, systemImage: String, role: ActionRole = .secondary, action: @escaping () -> Void) -> some View {
        if role == .primary {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
    }

    private enum ActionRole {
        case primary
        case secondary
    }
}

private struct PadQuickSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var query: String
    let onSubmit: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("検索")
                    .font(.system(size: 30, weight: .semibold))
                Text("検索語または URL を入力します。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("検索語または URL", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.go)
                    .onSubmit { onSubmit(query) }
                HStack(spacing: 12) {
                    Button("Vidarr Start を開く") {
                        onSubmit("")
                    }
                    .buttonStyle(.bordered)
                    Button("開く") {
                        onSubmit(query)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle("検索")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationBackground(.regularMaterial)
    }
}

private struct PadShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension UIImage {
    var averagePerceivedBrightness: CGFloat? {
        guard let cgImage else { return nil }
        let sampleSize = CGSize(width: 8, height: 8)
        let bytesPerRow = Int(sampleSize.width) * 4
        var data = [UInt8](repeating: 0, count: Int(sampleSize.height) * bytesPerRow)
        guard let context = CGContext(
            data: &data,
            width: Int(sampleSize.width),
            height: Int(sampleSize.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(origin: .zero, size: sampleSize))

        var totalBrightness: CGFloat = 0
        let pixelCount = Int(sampleSize.width * sampleSize.height)
        for pixel in 0..<pixelCount {
            let offset = pixel * 4
            let red = CGFloat(data[offset]) / 255
            let green = CGFloat(data[offset + 1]) / 255
            let blue = CGFloat(data[offset + 2]) / 255
            totalBrightness += (0.299 * red) + (0.587 * green) + (0.114 * blue)
        }

        return totalBrightness / CGFloat(pixelCount)
    }
}
