import AppKit

struct CommandPaletteItem {
    let title: String
    let detail: String
    let symbol: String
    let searchText: String
    let action: () -> Void
}

final class CommandPaletteWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let itemProvider: () -> [CommandPaletteItem]
    private var allItems: [CommandPaletteItem] = []
    private var filteredItems: [CommandPaletteItem] = []

    init(itemProvider: @escaping () -> [CommandPaletteItem]) {
        self.itemProvider = itemProvider
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "コマンドパレット"
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: 500, height: 320)
        super.init(window: panel)
        configureUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(relativeTo parent: NSWindow?) {
        allItems = itemProvider()
        searchField.stringValue = ""
        applyFilter()
        if let parent, let window {
            window.setFrameOrigin(NSPoint(x: parent.frame.midX - window.frame.width / 2, y: parent.frame.midY - window.frame.height / 2))
        } else {
            window?.center()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)
    }

    private func configureUI() {
        guard let content = window?.contentView else { return }
        searchField.placeholderString = "タブ、履歴、ブックマーク、操作を検索"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 48
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(runSelectedItem)
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(searchField)
        content.addSubview(scrollView)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    func controlTextDidChange(_ obj: Notification) {
        _ = obj
        applyFilter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        _ = control
        _ = textView
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        runSelectedItem()
        return true
    }

    private func applyFilter() {
        filteredItems = Self.filtered(allItems, query: searchField.stringValue)
        tableView.reloadData()
        if !filteredItems.isEmpty { tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
    }

    static func filtered(_ items: [CommandPaletteItem], query: String) -> [CommandPaletteItem] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
        return terms.isEmpty ? items : items.filter { item in
            let haystack = "\(item.title) \(item.detail) \(item.searchText)".lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    @objc private func runSelectedItem() {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard row >= 0, row < filteredItems.count else { return }
        let action = filteredItems[row].action
        close()
        action()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filteredItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        _ = tableColumn
        let item = filteredItems[row]
        let identifier = NSUserInterfaceItemIdentifier("CommandPaletteCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? NSTableCellView()
        cell.identifier = identifier
        cell.subviews.forEach { $0.removeFromSuperview() }

        let icon = NSImageView(image: NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil) ?? NSImage())
        let title = NSTextField(labelWithString: item.title)
        let detail = NSTextField(labelWithString: item.detail)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.setAccessibilityIdentifier("commandPalette.item.\(item.title)")
        title.setAccessibilityLabel(item.title)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        cell.setAccessibilityLabel(item.title)
        cell.setAccessibilityIdentifier("commandPalette.item.\(item.title)")
        cell.textField = title
        cell.imageView = icon
        [icon, title, detail].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview($0) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1)
        ])
        return cell
    }
}
