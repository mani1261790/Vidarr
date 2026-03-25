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
        return try? JSONDecoder().decode(BrowserSessionSnapshot.self, from: data)
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
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var items: [DownloadItem] = []

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
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        tableView.headerView = nil
        tableView.rowHeight = 30
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedDownload)

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "File"
        nameColumn.width = 310
        tableView.addTableColumn(nameColumn)

        let sourceColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        sourceColumn.title = "Source"
        sourceColumn.width = 260
        tableView.addTableColumn(sourceColumn)

        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = "Date"
        dateColumn.width = 120
        tableView.addTableColumn(dateColumn)

        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    private func reloadData() {
        items = DownloadStore.shared.all()
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < items.count else { return nil }
        let item = items[row]
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
        let view = NSTextField(labelWithString: "")
        view.identifier = identifier
        view.lineBreakMode = .byTruncatingMiddle

        switch identifier.rawValue {
        case "name":
            view.stringValue = item.destinationURL.lastPathComponent
        case "source":
            view.stringValue = item.sourceURL?.host ?? item.sourceURLString
            view.textColor = NSColor.secondaryLabelColor
        case "date":
            view.stringValue = DateFormatter.localizedString(from: item.createdAt, dateStyle: .short, timeStyle: .short)
            view.textColor = NSColor.secondaryLabelColor
        default:
            view.stringValue = ""
        }

        return view
    }

    @objc private func openSelectedDownload() {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        NSWorkspace.shared.open(items[row].destinationURL)
    }
}

final class BrowsingItemsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    enum Mode {
        case history
        case bookmarks
    }

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var items: [BrowsingItem] = []
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
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        tableView.headerView = nil
        tableView.rowHeight = 32
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedItem)

        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.width = 310
        tableView.addTableColumn(titleColumn)

        let urlColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url"))
        urlColumn.width = 330
        tableView.addTableColumn(urlColumn)

        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.width = 120
        tableView.addTableColumn(dateColumn)

        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        let deleteButton = NSButton(title: "Delete", target: self, action: #selector(deleteSelectedItem))
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: deleteButton.topAnchor, constant: -10),
            deleteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            deleteButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    private func reloadData() {
        switch mode {
        case .history:
            items = BrowsingHistoryStore.shared.all()
        case .bookmarks:
            items = BookmarkStore.shared.all()
        }
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < items.count else { return nil }
        let item = items[row]
        let identifier = tableColumn?.identifier.rawValue ?? "cell"
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingMiddle

        switch identifier {
        case "title":
            label.stringValue = item.title
        case "url":
            label.stringValue = item.urlString
            label.textColor = .secondaryLabelColor
        case "date":
            label.stringValue = DateFormatter.localizedString(from: item.visitedAt, dateStyle: .short, timeStyle: .short)
            label.textColor = .secondaryLabelColor
        default:
            break
        }

        return label
    }

    @objc private func openSelectedItem() {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count, let url = items[row].url else { return }
        openHandler(url)
    }

    @objc private func deleteSelectedItem() {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        let urlString = items[row].urlString
        switch mode {
        case .history:
            BrowsingHistoryStore.shared.remove(urlString: urlString)
        case .bookmarks:
            BookmarkStore.shared.remove(urlString: urlString)
        }
        reloadData()
    }
}

final class SiteSettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Section {
        case blockingExceptions
        case mediaPermissions
    }

    private let exceptionsTableView = NSTableView()
    private let mediaPermissionsTableView = NSTableView()
    private var exceptionHosts: [String] = []
    private var mediaPermissions: [StoredMediaPermission] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Site Settings"
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

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])

        root.addArrangedSubview(makeSectionTitle("Content Blocking Exceptions"))
        root.addArrangedSubview(makeTableContainer(
            tableView: exceptionsTableView,
            columns: [("host", 400), ("state", 220)],
            deleteAction: #selector(removeSelectedBlockingException),
            deleteTitle: "Remove Exception"
        ))

        root.addArrangedSubview(makeSectionTitle("Saved Media Permissions"))
        root.addArrangedSubview(makeTableContainer(
            tableView: mediaPermissionsTableView,
            columns: [("host", 250), ("permission", 220), ("decision", 120)],
            deleteAction: #selector(removeSelectedMediaPermission),
            deleteTitle: "Forget Permission"
        ))
    }

    private func makeSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        return label
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
        tableView.rowHeight = 30
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.delegate = self
        tableView.dataSource = self

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
        mediaPermissions = MediaPermissionStore.shared.all()
        exceptionsTableView.reloadData()
        mediaPermissionsTableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === exceptionsTableView {
            return exceptionHosts.count
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
                label.stringValue = "Blocking disabled for this host"
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
        let row = exceptionsTableView.selectedRow
        guard row >= 0, row < exceptionHosts.count else { return }
        BrowserPreferences.shared.setContentBlockingDisabled(false, for: exceptionHosts[row])
        reloadData()
    }

    @objc private func removeSelectedMediaPermission() {
        let row = mediaPermissionsTableView.selectedRow
        guard row >= 0, row < mediaPermissions.count else { return }
        let permission = mediaPermissions[row]
        MediaPermissionStore.shared.remove(host: permission.host, kind: permission.kind)
        reloadData()
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
