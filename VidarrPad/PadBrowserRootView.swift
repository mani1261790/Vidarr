import SwiftUI

struct PadBrowserRootView: View {
    @StateObject private var model = PadBrowserModel()
    @State private var gestureHUD: PadGestureHUDState?
    @State private var gestureHUDTask: Task<Void, Never>?
    @State private var editingTabID: UUID?
    @State private var editingURL = ""
    @FocusState private var editingURLFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            webLayer
            bottomBar
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
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
    }

    private var webLayer: some View {
        ZStack {
            if let tab = model.selectedTab {
                PadWebView(webView: tab.webView)
                    .id(tab.id)
                    .ignoresSafeArea()
                    .overlay {
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
                    }
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

    private var bottomBar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 10) {
                chromeButton(systemName: "chevron.left", disabled: !model.canGoBack(), action: model.goBack)
                chromeButton(systemName: "chevron.right", disabled: !model.canGoForward(), action: model.goForward)
                chromeButton(systemName: "arrow.clockwise", disabled: false, action: model.reload)
            }

            tabStrip

            chromeButton(systemName: "plus", disabled: false) {
                model.newTab()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            PadLiquidGlassBackground(cornerRadius: 28)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 20, y: 10)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(model.tabs) { tab in
                    PadTabThumbnail(
                        tab: tab,
                        isSelected: model.selectedTab?.id == tab.id,
                        onSelect: {
                            model.selectTab(id: tab.id)
                        },
                        onLongPress: {
                            model.selectTab(id: tab.id)
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
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary.opacity(0.45) : Color.primary)
        .disabled(disabled)
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
            if let tab = model.selectedTab {
                editingURL = tab.urlString
                editingTabID = tab.id
            }
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
            .frame(width: 118, height: 70)
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
