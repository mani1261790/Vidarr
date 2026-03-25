import AppKit
import Foundation

struct DownloadItem: Codable {
    let sourceURLString: String
    let destinationPath: String
    let createdAt: Date

    var sourceURL: URL? { URL(string: sourceURLString) }
    var destinationURL: URL { URL(fileURLWithPath: destinationPath) }
}

final class DownloadStore {
    static let shared = DownloadStore()

    private enum Key {
        static let items = "downloads.items"
    }

    private let defaults: UserDefaults
    private var items: [DownloadItem]
    private let maxItems = 100

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.items),
           let decoded = try? JSONDecoder().decode([DownloadItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    func add(sourceURL: URL?, destinationURL: URL) {
        let item = DownloadItem(
            sourceURLString: sourceURL?.absoluteString ?? destinationURL.absoluteString,
            destinationPath: destinationURL.path,
            createdAt: Date()
        )
        items.removeAll { $0.destinationPath == item.destinationPath }
        items.insert(item, at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        persist()
    }

    func all() -> [DownloadItem] {
        items
    }

    func clear() {
        items.removeAll()
        persist()
    }

    func remove(destinationPaths: Set<String>) {
        guard !destinationPaths.isEmpty else { return }
        items.removeAll { destinationPaths.contains($0.destinationPath) }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Key.items)
    }
}

final class BrowserSessionStore {
    static let shared = BrowserSessionStore()

    private enum Key {
        static let snapshot = "browser.session.snapshot"
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ snapshot: BrowserSessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Key.snapshot)
    }

    func load() -> BrowserSessionSnapshot? {
        guard let data = defaults.data(forKey: Key.snapshot) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(BrowserSessionSnapshot.self, from: data) else {
            defaults.removeObject(forKey: Key.snapshot)
            return nil
        }
        return snapshot
    }
}

enum MediaPermissionKind: String, Codable {
    case camera
    case microphone
    case cameraAndMicrophone
}

enum MediaPermissionDecision: String, Codable {
    case allow
    case deny
}

struct StoredMediaPermission {
    let host: String
    let kind: MediaPermissionKind
    let decision: MediaPermissionDecision
}

final class MediaPermissionStore {
    static let shared = MediaPermissionStore()

    private enum Key {
        static let decisions = "media.permissions.decisions"
    }

    private let defaults: UserDefaults
    private var decisions: [String: MediaPermissionDecision]

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.decisions),
           let decoded = try? JSONDecoder().decode([String: MediaPermissionDecision].self, from: data) {
            decisions = decoded
        } else {
            decisions = [:]
        }
    }

    func decision(for host: String, kind: MediaPermissionKind) -> MediaPermissionDecision? {
        decisions[key(host: host, kind: kind)]
    }

    func setDecision(_ decision: MediaPermissionDecision, for host: String, kind: MediaPermissionKind) {
        decisions[key(host: host, kind: kind)] = decision
        persist()
    }

    func all() -> [StoredMediaPermission] {
        decisions.compactMap { entry in
            let parts = entry.key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let kind = MediaPermissionKind(rawValue: parts[1]) else {
                return nil
            }
            return StoredMediaPermission(host: parts[0], kind: kind, decision: entry.value)
        }
        .sorted {
            if $0.host == $1.host {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.host < $1.host
        }
    }

    func remove(host: String, kind: MediaPermissionKind) {
        decisions.removeValue(forKey: key(host: host, kind: kind))
        persist()
    }

    func clear() {
        decisions.removeAll()
        persist()
    }

    private func key(host: String, kind: MediaPermissionKind) -> String {
        host.lowercased() + "|" + kind.rawValue
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(decisions) else { return }
        defaults.set(data, forKey: Key.decisions)
    }
}

final class DownloadsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let searchField = NSSearchField()
    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let emptyStateLabel = NSTextField(labelWithString: "")
    private let tableView = SelectionAwareTableView()
    private let scrollView = NSScrollView()
    private let openButton = NSButton(title: "Open", target: nil, action: nil)
    private let revealButton = NSButton(title: "Reveal", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    private var items: [DownloadItem] = []
    private var filteredItems: [DownloadItem] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Downloads"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupUI()
        reloadData()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndReload() {
        reloadData()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        titleLabel.stringValue = "Downloads"

        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        summaryLabel.textColor = .secondaryLabelColor

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.placeholderString = "Search Downloads"
        searchField.controlSize = .large

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        tableView.headerView = nil
        tableView.rowHeight = 72
        tableView.intercellSpacing = NSSize(width: 0, height: 8)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedDownload)
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = true
        tableView.menu = makeContextMenu()

        let itemColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        itemColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(itemColumn)

        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.alignment = .center
        emptyStateLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.stringValue = "No downloads yet"
        emptyStateLabel.isHidden = true

        let headerStack = NSStackView(views: [titleLabel, summaryLabel])
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 4

        scrollView.documentView = tableView
        contentView.addSubview(headerStack)
        contentView.addSubview(searchField)
        contentView.addSubview(scrollView)
        contentView.addSubview(emptyStateLabel)

        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.target = self
        openButton.action = #selector(openSelectedDownload)
        contentView.addSubview(openButton)

        revealButton.translatesAutoresizingMaskIntoConstraints = false
        revealButton.target = self
        revealButton.action = #selector(revealSelectedDownload)
        contentView.addSubview(revealButton)

        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.target = self
        removeButton.action = #selector(removeSelectedDownloads)
        contentView.addSubview(removeButton)

        let clearButton = NSButton(title: "Clear Downloads", target: self, action: #selector(clearDownloads))
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(clearButton)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            headerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),

            searchField.centerYAnchor.constraint(equalTo: headerStack.centerYAnchor),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            searchField.widthAnchor.constraint(equalToConstant: 280),

            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            scrollView.bottomAnchor.constraint(equalTo: revealButton.topAnchor, constant: -12),

            emptyStateLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            clearButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            clearButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),

            revealButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            revealButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),

            removeButton.trailingAnchor.constraint(equalTo: revealButton.leadingAnchor, constant: -8),
            removeButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),

            openButton.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -8),
            openButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])

        updateActionButtons()
    }

    private func reloadData() {
        items = DownloadStore.shared.all()
        applyFilter()
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter { item in
                let haystacks = [
                    item.destinationURL.lastPathComponent.lowercased(),
                    item.sourceURL?.host?.lowercased() ?? "",
                    item.sourceURLString.lowercased(),
                    item.destinationPath.lowercased()
                ]
                return haystacks.contains { $0.contains(query) }
            }
        }
        updateSummary()
        emptyStateLabel.isHidden = !filteredItems.isEmpty
        tableView.reloadData()
        updateActionButtons()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filteredItems.count else { return nil }
        let item = filteredItems[row]
        let identifier = NSUserInterfaceItemIdentifier("DownloadItemCardView")
        let cardView = (tableView.makeView(withIdentifier: identifier, owner: self) as? DownloadItemCardView)
            ?? DownloadItemCardView(frame: .zero)
        cardView.identifier = identifier
        cardView.configure(item: item)
        return cardView
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = BrowsingItemRowView()
        rowView.setSelected(tableView.selectedRowIndexes.contains(row))
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        _ = notification
        for row in 0..<tableView.numberOfRows {
            if let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) as? BrowsingItemRowView {
                rowView.setSelected(tableView.selectedRowIndexes.contains(row))
            }
        }
        updateActionButtons()
    }

    @objc private func openSelectedDownload() {
        let selectedItems = selectedDownloadItems()
        guard !selectedItems.isEmpty else { return }
        for item in selectedItems {
            NSWorkspace.shared.open(item.destinationURL)
        }
    }

    @objc private func revealSelectedDownload() {
        let selectedItems = selectedDownloadItems()
        guard !selectedItems.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(selectedItems.map(\.destinationURL))
    }

    @objc private func removeSelectedDownloads() {
        let selectedItems = selectedDownloadItems()
        guard !selectedItems.isEmpty else { return }
        let title = selectedItems.count == 1 ? "Remove selected download?" : "Remove \(selectedItems.count) downloads?"
        presentConfirmation(
            title: title,
            message: "This removes the selected items from Vidarr's download list. Downloaded files themselves are not deleted."
        ) { [weak self] in
            DownloadStore.shared.remove(destinationPaths: Set(selectedItems.map(\.destinationPath)))
            self?.reloadData()
        }
    }

    @objc private func clearDownloads() {
        presentConfirmation(
            title: "Clear download history?",
            message: "This removes the download list from Vidarr. Downloaded files themselves are not deleted."
        ) { [weak self] in
            DownloadStore.shared.clear()
            self?.reloadData()
        }
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        _ = sender
        applyFilter()
    }

    private func updateSummary() {
        let total = "\(items.count) downloads"
        if filteredItems.count == items.count {
            summaryLabel.stringValue = total
        } else {
            summaryLabel.stringValue = "\(filteredItems.count) shown of \(total)"
        }
    }

    private func selectedDownloadItems() -> [DownloadItem] {
        let rows = tableView.selectedRowIndexes
        return rows.compactMap { row in
            guard row >= 0, row < filteredItems.count else { return nil }
            return filteredItems[row]
        }
    }

    private func updateActionButtons() {
        let count = selectedDownloadItems().count
        let hasSelection = count > 0
        openButton.isEnabled = hasSelection
        revealButton.isEnabled = hasSelection
        removeButton.isEnabled = hasSelection
        openButton.title = count > 1 ? "Open Selected" : "Open"
        revealButton.title = count > 1 ? "Reveal Selected" : "Reveal"
        removeButton.title = count > 1 ? "Remove Selected" : "Remove"
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Downloads")
        menu.addItem(NSMenuItem(title: "Open", action: #selector(openSelectedDownload), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reveal in Finder", action: #selector(revealSelectedDownload), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Remove from List", action: #selector(removeSelectedDownloads), keyEquivalent: ""))
        menu.items.forEach { $0.target = self }
        return menu
    }

    private func presentConfirmation(title: String, message: String, confirmed: @escaping () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            confirmed()
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }
}

private final class DownloadItemCardView: NSTableCellView {
    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        symbolView.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        symbolView.contentTintColor = .secondaryLabelColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        metadataLabel.textColor = .secondaryLabelColor
        metadataLabel.lineBreakMode = .byTruncatingTail

        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle

        addSubview(symbolView)
        addSubview(titleLabel)
        addSubview(metadataLabel)
        addSubview(pathLabel)

        NSLayoutConstraint.activate([
            symbolView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 18),
            symbolView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            metadataLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            metadataLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metadataLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            pathLabel.topAnchor.constraint(equalTo: metadataLabel.bottomAnchor, constant: 2),
            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: DownloadItem) {
        let sourceHost = item.sourceURL?.host ?? item.sourceURLString
        titleLabel.stringValue = item.destinationURL.lastPathComponent
        metadataLabel.stringValue = "\(sourceHost)  •  \(relativeDateString(for: item.createdAt))"
        pathLabel.stringValue = item.destinationPath
    }

    private func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

final class BrowsingItemsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    enum Mode {
        case history
        case bookmarks
    }

    private let searchField = NSSearchField()
    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let emptyStateLabel = NSTextField(labelWithString: "")
    private let tableView = SelectionAwareTableView()
    private let scrollView = NSScrollView()
    private let openButton = NSButton(title: "Open", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private var items: [BrowsingItem] = []
    private var filteredItems: [BrowsingItem] = []
    private let mode: Mode
    private let openHandler: (URL) -> Void

    init(mode: Mode, openHandler: @escaping (URL) -> Void) {
        self.mode = mode
        self.openHandler = openHandler
        let title = mode == .history ? "History" : "Bookmarks"
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupUI()
        reloadData()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndReload() {
        reloadData()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        titleLabel.stringValue = mode == .history ? "Browsing History" : "Bookmarks"

        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        summaryLabel.textColor = .secondaryLabelColor

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.placeholderString = mode == .history ? "Search History" : "Search Bookmarks"
        searchField.controlSize = .large

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        tableView.headerView = nil
        tableView.rowHeight = 70
        tableView.intercellSpacing = NSSize(width: 0, height: 8)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedItem)
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = true
        tableView.menu = makeContextMenu()

        let itemColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        itemColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(itemColumn)

        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.alignment = .center
        emptyStateLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.maximumNumberOfLines = 2
        emptyStateLabel.isHidden = true
        emptyStateLabel.stringValue = mode == .history
            ? "No browsing history yet"
            : "No bookmarks yet"

        let headerStack = NSStackView(views: [titleLabel, summaryLabel])
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 4

        scrollView.documentView = tableView
        contentView.addSubview(headerStack)
        contentView.addSubview(searchField)
        contentView.addSubview(scrollView)
        contentView.addSubview(emptyStateLabel)

        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.bezelStyle = .rounded
        openButton.target = self
        openButton.action = #selector(openSelectedItem)
        contentView.addSubview(openButton)

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelectedItem)
        contentView.addSubview(deleteButton)

        let clearButton = NSButton(title: mode == .history ? "Clear History" : "Clear Bookmarks", target: self, action: #selector(clearAllItems))
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(clearButton)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            headerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),

            searchField.centerYAnchor.constraint(equalTo: headerStack.centerYAnchor),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            searchField.widthAnchor.constraint(equalToConstant: 280),

            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            scrollView.bottomAnchor.constraint(equalTo: deleteButton.topAnchor, constant: -12),

            emptyStateLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyStateLabel.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, multiplier: 0.7),

            clearButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            clearButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),

            deleteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            deleteButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),

            openButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            openButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])

        updateActionButtons()
    }

    private func reloadData() {
        switch mode {
        case .history:
            items = BrowsingHistoryStore.shared.all()
        case .bookmarks:
            items = BookmarkStore.shared.all()
        }
        applyFilter()
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter { item in
                item.title.lowercased().contains(query) || item.urlString.lowercased().contains(query)
            }
        }
        updateSummary()
        emptyStateLabel.isHidden = !filteredItems.isEmpty
        tableView.reloadData()
        updateActionButtons()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filteredItems.count else { return nil }
        let item = filteredItems[row]
        let identifier = NSUserInterfaceItemIdentifier("BrowsingItemCardView")
        let cardView = (tableView.makeView(withIdentifier: identifier, owner: self) as? BrowsingItemCardView)
            ?? BrowsingItemCardView(frame: .zero)
        cardView.identifier = identifier
        cardView.configure(item: item, mode: mode)
        return cardView
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = BrowsingItemRowView()
        rowView.setSelected(tableView.selectedRowIndexes.contains(row))
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        _ = notification
        for row in 0..<tableView.numberOfRows {
            if let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) as? BrowsingItemRowView {
                rowView.setSelected(tableView.selectedRowIndexes.contains(row))
            }
        }
        updateActionButtons()
    }

    @objc private func openSelectedItem() {
        let selected = selectedItems()
        guard !selected.isEmpty else { return }
        for item in selected {
            if let url = item.url {
                openHandler(url)
            }
        }
    }

    @objc private func deleteSelectedItem() {
        let selected = selectedItems()
        guard !selected.isEmpty else { return }
        let count = selected.count
        let title = mode == .history
            ? (count == 1 ? "Delete selected history entry?" : "Delete \(count) history entries?")
            : (count == 1 ? "Delete selected bookmark?" : "Delete \(count) bookmarks?")
        let message = mode == .history
            ? "This removes the selected entries from Vidarr's browsing history."
            : "This removes the selected entries from Vidarr's bookmarks."
        presentConfirmation(title: title, message: message) { [weak self] in
            for urlString in selected.map(\.urlString) {
                switch self?.mode {
                case .history:
                    BrowsingHistoryStore.shared.remove(urlString: urlString)
                case .bookmarks:
                    BookmarkStore.shared.remove(urlString: urlString)
                case .none:
                    break
                }
            }
            self?.reloadData()
        }
    }

    private func selectedItems() -> [BrowsingItem] {
        let rows = tableView.selectedRowIndexes
        return rows.compactMap { row in
            guard row >= 0, row < filteredItems.count else { return nil }
            return filteredItems[row]
        }
    }

    private func updateActionButtons() {
        let count = selectedItems().count
        let hasSelection = count > 0
        openButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
        openButton.title = count > 1 ? "Open Selected" : "Open"
        deleteButton.title = count > 1 ? "Delete Selected" : "Delete"
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: mode == .history ? "History" : "Bookmarks")
        let openTitle = mode == .history ? "Open Selected in New Tabs" : "Open Selected in New Tabs"
        menu.addItem(NSMenuItem(title: openTitle, action: #selector(openSelectedItem), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Delete Selected", action: #selector(deleteSelectedItem), keyEquivalent: ""))
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func clearAllItems() {
        let title = mode == .history ? "Clear history?" : "Clear bookmarks?"
        let message = mode == .history
            ? "This removes all saved history entries from Vidarr."
            : "This removes all saved bookmarks from Vidarr."
        presentConfirmation(title: title, message: message) { [weak self] in
            guard let self else { return }
            switch self.mode {
            case .history:
                BrowsingHistoryStore.shared.clear()
            case .bookmarks:
                BookmarkStore.shared.clear()
            }
            self.reloadData()
        }
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        _ = sender
        applyFilter()
    }

    private func updateSummary() {
        let itemWord = mode == .history ? "entries" : "bookmarks"
        let total = "\(items.count) \(itemWord)"
        if filteredItems.count == items.count {
            summaryLabel.stringValue = total
        } else {
            summaryLabel.stringValue = "\(filteredItems.count) shown of \(total)"
        }
    }

    private func presentConfirmation(title: String, message: String, confirmed: @escaping () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            confirmed()
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }
}

private final class BrowsingItemCardView: NSTableCellView {
    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let urlLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        symbolView.contentTintColor = .secondaryLabelColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        metadataLabel.textColor = .secondaryLabelColor
        metadataLabel.lineBreakMode = .byTruncatingTail

        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        urlLabel.textColor = .tertiaryLabelColor
        urlLabel.lineBreakMode = .byTruncatingMiddle

        addSubview(symbolView)
        addSubview(titleLabel)
        addSubview(metadataLabel)
        addSubview(urlLabel)

        NSLayoutConstraint.activate([
            symbolView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 18),
            symbolView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            metadataLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            metadataLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metadataLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            urlLabel.topAnchor.constraint(equalTo: metadataLabel.bottomAnchor, constant: 2),
            urlLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            urlLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: BrowsingItem, mode: BrowsingItemsWindowController.Mode) {
        let host = item.url?.host ?? item.urlString
        titleLabel.stringValue = item.title
        metadataLabel.stringValue = "\(host)  •  \(relativeDateString(for: item.visitedAt))"
        urlLabel.stringValue = item.urlString
        symbolView.image = NSImage(
            systemSymbolName: mode == .history ? "clock.arrow.circlepath" : "star",
            accessibilityDescription: nil
        )
    }

    private func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private final class BrowsingItemRowView: NSTableRowView {
    private let selectionBackground = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        selectionBackground.material = .sidebar
        selectionBackground.blendingMode = .withinWindow
        selectionBackground.state = .active
        selectionBackground.isHidden = true
        selectionBackground.wantsLayer = true
        selectionBackground.layer?.cornerRadius = 12
        addSubview(selectionBackground, positioned: .below, relativeTo: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        selectionBackground.frame = bounds.insetBy(dx: 2, dy: 2)
    }

    override func drawSelection(in dirtyRect: NSRect) {
    }

    func setSelected(_ selected: Bool) {
        selectionBackground.isHidden = !selected
    }

    override var isEmphasized: Bool {
        get { super.isEmphasized }
        set { super.isEmphasized = newValue }
    }
}

private final class SelectionAwareTableView: NSTableView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        if row >= 0, !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }
}

final class SiteSettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let exceptionsTableView = SelectionAwareTableView()
    private let harmfulHostsTableView = SelectionAwareTableView()
    private let mediaPermissionsTableView = SelectionAwareTableView()
    private var exceptionHosts: [String] = []
    private var harmfulAllowedHosts: [String] = []
    private var mediaPermissions: [StoredMediaPermission] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Privacy & Site Controls"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupUI()
        reloadData()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndReload() {
        reloadData()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        titleLabel.stringValue = "Privacy & Site Controls"

        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.stringValue = "Manage site-specific exceptions and saved permissions."

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.setHuggingPriority(.defaultLow, for: .vertical)
        contentView.addSubview(root)
        contentView.addSubview(titleLabel)
        contentView.addSubview(summaryLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            summaryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            summaryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            summaryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            root.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 18),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])

        root.addArrangedSubview(makeSectionHeader(
            title: "Sites where ad blocking is off",
            detail: "Use this if a site breaks when content blocking is enabled."
        ))
        root.addArrangedSubview(makeTableContainer(
            tableView: exceptionsTableView,
            columns: [("host", 400), ("state", 220)],
            deleteAction: #selector(removeSelectedBlockingException),
            deleteTitle: "Turn Blocking Back On for Selected"
        ))

        root.addArrangedSubview(makeSectionHeader(
            title: "Sites allowed past safety warnings",
            detail: "These sites were opened even after Vidarr showed a warning."
        ))
        root.addArrangedSubview(makeTableContainer(
            tableView: harmfulHostsTableView,
            columns: [("host", 400), ("state", 220)],
            deleteAction: #selector(removeSelectedHarmfulHostException),
            deleteTitle: "Restore Warning for Selected"
        ))

        root.addArrangedSubview(makeSectionHeader(
            title: "Saved camera and microphone permissions",
            detail: "Remove an entry if you want a site to ask again."
        ))
        root.addArrangedSubview(makeTableContainer(
            tableView: mediaPermissionsTableView,
            columns: [("host", 250), ("permission", 220), ("decision", 120)],
            deleteAction: #selector(removeSelectedMediaPermission),
            deleteTitle: "Ask Again for Selected"
        ))
    }

    private func makeSectionHeader(title: String, detail: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(detailLabel)
        return stack
    }

    private func makeTableContainer(
        tableView: NSTableView,
        columns: [(String, CGFloat)],
        deleteAction: Selector,
        deleteTitle: String
    ) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        tableView.headerView = nil
        tableView.rowHeight = 34
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsMultipleSelection = true
        tableView.menu = makeContextMenu(for: tableView)

        for (identifier, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.width = width
            tableView.addTableColumn(column)
        }

        scrollView.documentView = tableView
        container.addSubview(scrollView)

        let deleteButton = NSButton(title: deleteTitle, target: self, action: deleteAction)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 640),
            container.heightAnchor.constraint(equalToConstant: 170),

            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: deleteButton.topAnchor, constant: -8),

            deleteButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            deleteButton.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func reloadData() {
        exceptionHosts = BrowserPreferences.shared.contentBlockingDisabledHosts.sorted()
        harmfulAllowedHosts = BrowserPreferences.shared.harmfulSiteAllowedHosts.sorted()
        mediaPermissions = MediaPermissionStore.shared.all()
        exceptionsTableView.reloadData()
        harmfulHostsTableView.reloadData()
        mediaPermissionsTableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === exceptionsTableView {
            return exceptionHosts.count
        }
        if tableView === harmfulHostsTableView {
            return harmfulAllowedHosts.count
        }
        return mediaPermissions.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingMiddle
        let identifier = tableColumn?.identifier.rawValue ?? ""

        if tableView === exceptionsTableView {
            guard row >= 0, row < exceptionHosts.count else { return label }
            let host = exceptionHosts[row]
            switch identifier {
            case "host":
                label.stringValue = host
            case "state":
                label.stringValue = "Ad blocking is currently off"
                label.textColor = .secondaryLabelColor
            default:
                break
            }
            return label
        }

        if tableView === harmfulHostsTableView {
            guard row >= 0, row < harmfulAllowedHosts.count else { return label }
            let host = harmfulAllowedHosts[row]
            switch identifier {
            case "host":
                label.stringValue = host
            case "state":
                label.stringValue = "Safety warning is currently skipped"
                label.textColor = .secondaryLabelColor
            default:
                break
            }
            return label
        }

        guard row >= 0, row < mediaPermissions.count else { return label }
        let permission = mediaPermissions[row]
        switch identifier {
        case "host":
            label.stringValue = permission.host
        case "permission":
            label.stringValue = displayName(for: permission.kind)
            label.textColor = .secondaryLabelColor
        case "decision":
            label.stringValue = permission.decision == .allow ? "Allowed" : "Denied"
            label.textColor = permission.decision == .allow
                ? NSColor.systemGreen
                : NSColor.systemOrange
        default:
            break
        }
        return label
    }

    @objc private func removeSelectedBlockingException() {
        let hosts = selectedHosts(in: exceptionsTableView, from: exceptionHosts)
        guard !hosts.isEmpty else { return }
        for host in hosts {
            BrowserPreferences.shared.setContentBlockingDisabled(false, for: host)
        }
        reloadData()
    }

    @objc private func removeSelectedMediaPermission() {
        let selectedPermissions = selectedMediaPermissions()
        guard !selectedPermissions.isEmpty else { return }
        for permission in selectedPermissions {
            MediaPermissionStore.shared.remove(host: permission.host, kind: permission.kind)
        }
        reloadData()
    }

    @objc private func removeSelectedHarmfulHostException() {
        let hosts = selectedHosts(in: harmfulHostsTableView, from: harmfulAllowedHosts)
        guard !hosts.isEmpty else { return }
        for host in hosts {
            BrowserPreferences.shared.setHarmfulSiteAllowed(false, for: host)
        }
        reloadData()
    }

    private func selectedHosts(in tableView: NSTableView, from source: [String]) -> [String] {
        tableView.selectedRowIndexes.compactMap { row in
            guard row >= 0, row < source.count else { return nil }
            return source[row]
        }
    }

    private func selectedMediaPermissions() -> [StoredMediaPermission] {
        mediaPermissionsTableView.selectedRowIndexes.compactMap { row in
            guard row >= 0, row < mediaPermissions.count else { return nil }
            return mediaPermissions[row]
        }
    }

    private func makeContextMenu(for tableView: NSTableView) -> NSMenu {
        let menu = NSMenu(title: "Actions")
        if tableView === exceptionsTableView {
            menu.addItem(NSMenuItem(title: "Turn Blocking Back On for Selected", action: #selector(removeSelectedBlockingException), keyEquivalent: ""))
        } else if tableView === harmfulHostsTableView {
            menu.addItem(NSMenuItem(title: "Restore Warning for Selected", action: #selector(removeSelectedHarmfulHostException), keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Ask Again for Selected", action: #selector(removeSelectedMediaPermission), keyEquivalent: ""))
        }
        menu.items.forEach { $0.target = self }
        return menu
    }

    private func displayName(for kind: MediaPermissionKind) -> String {
        switch kind {
        case .camera:
            return "Camera"
        case .microphone:
            return "Microphone"
        case .cameraAndMicrophone:
            return "Camera + Microphone"
        }
    }
}
