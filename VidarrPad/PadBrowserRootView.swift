import SwiftUI

struct PadBrowserRootView: View {
    @StateObject private var model = PadBrowserModel()
    @State private var isSettingsPresented = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            VStack(spacing: 0) {
                detailToolbar
                Divider()
                if let tab = model.selectedTab {
                    PadWebView(webView: tab.webView)
                        .id(tab.id)
                        .ignoresSafeArea(edges: .bottom)
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
                Text("Tabs")
                    .font(.headline)
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
                ForEach(model.tabs) { tab in
                    PadTabRow(tab: tab, isSelected: model.selectedTab?.id == tab.id) {
                        model.selectTab(id: tab.id)
                    } onClose: {
                        model.closeTab(id: tab.id)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(uiColor: .secondarySystemBackground))
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

                TextField("Search or enter website name", text: $model.addressInput)
                    .textFieldStyle(.roundedBorder)
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
        .background(.ultraThinMaterial)
    }

    private var selectedTabBinding: Binding<UUID?> {
        Binding(
            get: { model.selectedTab?.id },
            set: { newValue in
                guard let newValue else { return }
                model.selectTab(id: newValue)
            }
        )
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
