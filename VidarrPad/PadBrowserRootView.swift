import SwiftUI

struct PadBrowserRootView: View {
    @StateObject private var model = PadBrowserModel()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if let tab = model.selectedTab {
                PadWebView(webView: tab.webView)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("No Tab", systemImage: "square.on.square")
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.tabs) { tab in
                        Button {
                            model.selectTab(id: tab.id)
                        } label: {
                            Text(tab.title)
                                .lineLimit(1)
                                .font(.system(size: 13, weight: model.selectedTab?.id == tab.id ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minWidth: 120)
                                .background(model.selectedTab?.id == tab.id ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        model.newTab()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 10) {
                Button(action: model.goBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)

                Button(action: model.goForward) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)

                Button(action: model.reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                TextField("Search or enter website name", text: $model.addressInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        model.commitAddressBar()
                    }

                Button(action: { model.newTab() }) {
                    Label("New Tab", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }
}
