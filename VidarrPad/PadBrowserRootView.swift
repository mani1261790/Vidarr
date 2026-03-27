import SwiftUI

struct PadBrowserRootView: View {
    @StateObject private var model = PadBrowserModel()
    @State private var isSettingsPresented = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var gestureHUD: PadGestureHUDState?
    @State private var gestureHUDTask: Task<Void, Never>?
    @FocusState private var addressFieldFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            VStack(spacing: 0) {
                detailToolbar
                Divider()
                if let tab = model.selectedTab {
                    ZStack {
                        PadWebView(webView: tab.webView)
                            .id(tab.id)
                            .ignoresSafeArea(edges: .bottom)
                        PadGestureOverlay(
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
                        if let gestureHUD {
                            PadGestureHUD(state: gestureHUD)
                                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        }
                    }
                } else {
                    ContentUnavailableView("No Tab", systemImage: "square.on.square")
                }
            }
            .background(Color(uiColor: .systemBackground))
        }
        .sheet(isPresented: $isSettingsPresented) {
            PadSettingsView {
                model.refreshPreferences()
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tabs")
                        .font(.headline)
                    Text(PadBrowserPreferences.shared.currentProfile.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.newTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            List(selection: selectedTabBinding) {
                if !model.recentHistory().isEmpty {
                    Section("Recent History") {
                        ForEach(model.recentHistory()) { entry in
                            Button {
                                if let url = URL(string: entry.urlString) {
                                    model.newTab(initialURL: url)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.title)
                                        .lineLimit(1)
                                    Text(URL(string: entry.urlString)?.host ?? entry.urlString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Open Tabs") {
                ForEach(model.tabs) { tab in
                    PadTabRow(tab: tab, isSelected: model.selectedTab?.id == tab.id) {
                        model.selectTab(id: tab.id)
                    } onClose: {
                        model.closeTab(id: tab.id)
                    }
                    .buttonStyle(.plain)
                }
                }
            }
            .listStyle(.sidebar)
        }
        .background(
            PadLiquidGlassBackground()
                .ignoresSafeArea()
        )
    }

    private var detailToolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: model.goBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canGoBack())

                Button(action: model.goForward) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canGoForward())

                Button(action: model.reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button(action: model.toggleBookmarkForSelectedTab) {
                    Image(systemName: model.selectedTab.map(model.isBookmarked) == true ? "star.fill" : "star")
                }
                .buttonStyle(.bordered)

                TextField("Search or enter website name", text: $model.addressInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($addressFieldFocused)
                    .onSubmit {
                        model.commitAddressBar()
                    }

                Button {
                    isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)

                Button(action: { model.newTab() }) {
                    Label("New Tab", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.tabs) { tab in
                        Button {
                            model.selectTab(id: tab.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tab.title)
                                    .lineLimit(1)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(tab.urlString.isEmpty ? "New Tab" : tab.urlString)
                                    .lineLimit(1)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 200, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(model.selectedTab?.id == tab.id ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(PadLiquidGlassBackground())
    }

    private var selectedTabBinding: Binding<UUID?> {
        Binding(
            get: { model.selectedSidebarTabID },
            set: { newValue in
                guard let newValue else { return }
                model.selectTab(id: newValue)
            }
        )
    }

    private func performGesture(_ action: PadGestureAction) {
        switch action {
        case .previousTab:
            model.selectPreviousTab()
        case .nextTab:
            model.selectNextTab()
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
        case .back:
            model.goBack()
        case .forward:
            model.goForward()
        case .search:
            addressFieldFocused = true
        case .newTab:
            model.newTab()
        }
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
        case .back: return "arrow.uturn.backward"
        case .forward: return "arrow.uturn.forward"
        case .search: return "magnifyingglass.circle"
        case .newTab: return "plus.circle"
        }
    }
}

private struct PadTabRow: View {
    @ObservedObject var tab: PadBrowserModel.Tab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tab.title)
                        .lineLimit(1)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    Text(hostText)
                        .lineLimit(1)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var hostText: String {
        URL(string: tab.urlString)?.host ?? tab.urlString.ifEmpty("New Tab")
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
