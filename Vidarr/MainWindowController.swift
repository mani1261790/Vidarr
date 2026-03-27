import Cocoa
import AVFoundation
import UniformTypeIdentifiers
import VidarrCore
import WebKit

private final class PDFExportContext {
    unowned let controller: MainWindowController
    let fallbackData: Data?
    let destinationURL: URL

    init(controller: MainWindowController, fallbackData: Data?, destinationURL: URL) {
        self.controller = controller
        self.fallbackData = fallbackData
        self.destinationURL = destinationURL
    }
}

final class MainWindowController: NSWindowController {
    private enum UI {
        static let toolbarHeight: CGFloat = 54
        static let fullScreenRevealHotzoneHeight: CGFloat = 6
        static let fullScreenHideDelay: TimeInterval = 0.55
        static let tabChipSize = NSSize(width: 96, height: 48)
        static let tabSwitchGap: CGFloat = 16
        static let newTabTransitionExtraTravel: CGFloat = 28
        static let newTabTransitionGapWidth: CGFloat = 18
        static let tabSwitchInteractiveMaxProgress: CGFloat = 0.82
        static let navButtonRowTop: CGFloat = 27
    }

    private let rootContainer = NonDraggableView()
    private let toolbarContainer = LiquidGlassToolbarView()
    private let webContainer = NonDraggableView()

    private let tabStripContainer = NonDraggableView()
    private let tabStripScrollView = NonDraggableScrollView()
    private let tabInteractionView = TabInteractionView()
    private let tabStripDocumentView = NonInteractiveView()
    private let tabStripStackView = NonInteractiveStackView()
    private let navigationButtonRow = NSStackView()
    private let backButton = NSButton(title: "", target: nil, action: nil)
    private let forwardButton = NSButton(title: "", target: nil, action: nil)
    private let reloadButton = NSButton(title: "", target: nil, action: nil)
    private let bookmarkButton = NSButton(title: "", target: nil, action: nil)
    private let shareButton = NSButton(title: "", target: nil, action: nil)
    private let groupSelectorButton = NSButton(title: "", target: nil, action: nil)
    private let newTabButton = NSButton(title: "+", target: nil, action: nil)
    private let rightPanelView = NonDraggableView()
    private let addressBarDisplayLabel = ClickableLabelField()
    private let addressBarEditorField = NSTextField()
    private let tabSearchField = NSSearchField()

    private var leftButtonRowLeadingConstraint: NSLayoutConstraint?
    private var leftButtonRowTopConstraint: NSLayoutConstraint?
    private var tabStripWidthConstraint: NSLayoutConstraint?
    private var rightPanelWidthConstraint: NSLayoutConstraint?
    private var toolbarTopConstraint: NSLayoutConstraint?

    private let tabManager: TabManager
    private let session: BrowserSession
    private let actions: ActionCenter

    private var overlayView: GestureOverlayView?
    private var isAddressEditing = false
    private var tabSearchQuery = ""
    private var currentAddressURLString = ""
    private var interactiveTabSwitchState: InteractiveTabSwitchState?
    private var visualTransitionCurrentIndex: Int?
    private weak var visualTransitionCurrentWebView: WKWebView?
    private var tabTransitionGeneration: Int = 0
    private var lastCommittedTabTransitionAt: CFTimeInterval = 0
    private var dragFromTabIndex: Int?
    private var dragToTabIndex: Int?
    private var dragPreviewView: NSImageView?
    private weak var dragSourceChipView: TabChipView?
    private var dragPreviewOffsetX: CGFloat = 0
    private var preferenceObserver: NSObjectProtocol?
    private var bookmarkObserver: NSObjectProtocol?
    private var lastEphemeralMode = BrowserPreferences.shared.ephemeralModeEnabled
    private var lastDoNotTrack = BrowserPreferences.shared.sendDoNotTrack
    private var lastContentBlockingEnabled = BrowserPreferences.shared.contentBlockingEnabled
    private var lastContentBlockingExceptionSignature = BrowserPreferences.shared.contentBlockingExceptionSignature
    private var lastPopupBlockingEnabled = BrowserPreferences.shared.popupBlockingEnabled
    private var lastPreferredContentLanguage = BrowserPreferences.shared.preferredContentLanguage
    private var lastHarmfulAllowedHosts = BrowserPreferences.shared.harmfulSiteAllowedHosts
    private var temporarilyAllowedHosts: Set<String> = []
    private var configuredLongPressControllers: Set<ObjectIdentifier> = []
    private var longPressHandlerBoxes: [ObjectIdentifier: WeakScriptMessageHandler] = [:]
    private var downloadSourceURLs: [ObjectIdentifier: URL] = [:]
    private var downloadDestinationURLs: [ObjectIdentifier: URL] = [:]
    private var downloadSecurityScopedAccess: [ObjectIdentifier: URL] = [:]
    private var retainedDocumentSecurityScopes: [String: URL] = [:]
    private var fullScreenMouseMonitor: Any?
    private var fullScreenHideTimer: Timer?
    private var isFullScreenToolbarHidden = false
    private let trackingQueryKeys: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "gclid", "dclid", "fbclid", "msclkid", "yclid", "mc_cid", "mc_eid", "igshid", "rb_clickid"
    ]
    private static let longPressLinkMessageName = "vidarrLongPressLink"
    private static let selectionSearchMessageName = "vidarrSelectionSearch"

    private static let toolbarPrimaryForegroundColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.96)
        }
        return NSColor.labelColor.withAlphaComponent(0.96)
    }

    private static let toolbarSecondaryForegroundColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.88)
        }
        return NSColor.labelColor.withAlphaComponent(0.82)
    }

    private static func makeTabGroupGridImage() -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.labelColor.setFill()

        let cell: CGFloat = 2.2
        let gap: CGFloat = 2.45
        let total = cell * 3 + gap * 2
        let startX = (size.width - total) * 0.5
        let startY = (size.height - total) * 0.5

        for row in 0..<3 {
            for column in 0..<3 {
                let x = startX + CGFloat(column) * (cell + gap)
                let y = startY + CGFloat(2 - row) * (cell + gap)
                let rect = NSRect(x: x, y: y, width: cell, height: cell)
                NSBezierPath(roundedRect: rect, xRadius: 0.55, yRadius: 0.55).fill()
            }
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private struct InteractiveTabSwitchState {
        let fromWebView: WKWebView
        let toWebView: WKWebView
        let targetIndex: Int
        let direction: ActionCenter.GestureTabSwitchDirection
    }

    init() {
        tabManager = TabManager()
        session = BrowserSession(tabManager: tabManager)
        actions = ActionCenter(tabManager: tabManager, session: session)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Vidarr"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.contentResizeIncrements = NSSize(width: 1, height: 1)
        window.minSize = NSSize(width: 760, height: 520)
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            window.miniwindowImage = appIcon
        }
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self

        configureWindow()
        configureBindings()
        configurePreferenceObserver()
        configureBookmarkObserver()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let preferenceObserver {
            NotificationCenter.default.removeObserver(preferenceObserver)
        }
        if let bookmarkObserver {
            NotificationCenter.default.removeObserver(bookmarkObserver)
        }
        fullScreenHideTimer?.invalidate()
        if let fullScreenMouseMonitor {
            NSEvent.removeMonitor(fullScreenMouseMonitor)
        }
        retainedDocumentSecurityScopes.values.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        ensureInitialTabVisible()
        DispatchQueue.main.async { [weak self] in
            self?.syncToolbarLayout()
        }
    }

    private func configureWindow() {
        guard let contentView = window?.contentView else { return }

        rootContainer.translatesAutoresizingMaskIntoConstraints = false
        toolbarContainer.translatesAutoresizingMaskIntoConstraints = false
        webContainer.translatesAutoresizingMaskIntoConstraints = false
        webContainer.wantsLayer = true
        webContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        webContainer.layer?.masksToBounds = true

        contentView.addSubview(rootContainer)
        rootContainer.addSubview(toolbarContainer)
        rootContainer.addSubview(webContainer)

        setupToolbarUI()

        let toolbarTopConstraint = toolbarContainer.topAnchor.constraint(equalTo: rootContainer.topAnchor)
        self.toolbarTopConstraint = toolbarTopConstraint

        NSLayoutConstraint.activate([
            rootContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            toolbarTopConstraint,
            toolbarContainer.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            toolbarContainer.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            toolbarContainer.heightAnchor.constraint(equalToConstant: UI.toolbarHeight),

            webContainer.topAnchor.constraint(equalTo: toolbarContainer.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            webContainer.bottomAnchor.constraint(equalTo: rootContainer.bottomAnchor)
        ])
    }

    private func setupToolbarUI() {
        tabStripContainer.translatesAutoresizingMaskIntoConstraints = false
        tabStripContainer.wantsLayer = false

        tabStripScrollView.translatesAutoresizingMaskIntoConstraints = false
        tabStripScrollView.drawsBackground = false
        tabStripScrollView.hasVerticalScroller = false
        tabStripScrollView.hasHorizontalScroller = false
        tabStripScrollView.autohidesScrollers = true
        tabStripScrollView.borderType = .noBorder
        tabStripScrollView.scrollerStyle = .overlay
        tabStripScrollView.verticalScrollElasticity = .none
        tabStripScrollView.horizontalScrollElasticity = .automatic
        tabStripScrollView.contentView = HorizontalOnlyClipView()
        tabStripScrollView.contentView.drawsBackground = false
        tabStripContainer.addSubview(tabStripScrollView)
        tabInteractionView.translatesAutoresizingMaskIntoConstraints = false
        tabStripContainer.addSubview(tabInteractionView)

        tabStripDocumentView.translatesAutoresizingMaskIntoConstraints = true
        tabStripDocumentView.wantsLayer = false
        tabStripScrollView.documentView = tabStripDocumentView

        tabStripStackView.translatesAutoresizingMaskIntoConstraints = true
        tabStripStackView.orientation = .horizontal
        tabStripStackView.alignment = .centerY
        tabStripStackView.spacing = 6
        tabStripDocumentView.addSubview(tabStripStackView)

        navigationButtonRow.translatesAutoresizingMaskIntoConstraints = false
        navigationButtonRow.orientation = .horizontal
        navigationButtonRow.alignment = .centerY
        navigationButtonRow.distribution = .fill
        navigationButtonRow.spacing = 4

        configureToolbarSymbolButton(
            backButton,
            symbolName: "chevron.left",
            pointSize: 13,
            weight: .semibold,
            action: #selector(didTapBackButton)
        )
        configureToolbarSymbolButton(
            forwardButton,
            symbolName: "chevron.right",
            pointSize: 13,
            weight: .semibold,
            action: #selector(didTapForwardButton)
        )
        configureToolbarSymbolButton(
            reloadButton,
            symbolName: "arrow.clockwise",
            pointSize: 13,
            weight: .semibold,
            action: #selector(didTapReloadButton)
        )
        configureToolbarSymbolButton(
            bookmarkButton,
            symbolName: "star",
            pointSize: 13,
            weight: .semibold,
            action: #selector(didTapBookmarkButton)
        )
        configureToolbarSymbolButton(
            shareButton,
            symbolName: "square.and.arrow.up",
            pointSize: 13,
            weight: .semibold,
            action: #selector(didTapShareButton)
        )

        [backButton, forwardButton, reloadButton, bookmarkButton, shareButton].forEach { button in
            navigationButtonRow.addArrangedSubview(button)
        }

        groupSelectorButton.translatesAutoresizingMaskIntoConstraints = false
        groupSelectorButton.target = self
        groupSelectorButton.action = #selector(didTapGroupSelector)
        groupSelectorButton.isBordered = false
        groupSelectorButton.image = Self.makeTabGroupGridImage()
        groupSelectorButton.contentTintColor = Self.toolbarSecondaryForegroundColor
        groupSelectorButton.wantsLayer = false

        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton.target = self
        newTabButton.action = #selector(didTapNewTab)
        newTabButton.isBordered = false
        newTabButton.title = ""
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        newTabButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        newTabButton.contentTintColor = Self.toolbarPrimaryForegroundColor
        newTabButton.wantsLayer = false

        rightPanelView.translatesAutoresizingMaskIntoConstraints = false

        addressBarDisplayLabel.translatesAutoresizingMaskIntoConstraints = false
        addressBarDisplayLabel.font = NSFont.systemFont(ofSize: 13.0)
        addressBarDisplayLabel.isEditable = false
        addressBarDisplayLabel.isSelectable = false
        addressBarDisplayLabel.isBezeled = false
        addressBarDisplayLabel.isBordered = false
        addressBarDisplayLabel.drawsBackground = false
        addressBarDisplayLabel.alignment = .right
        addressBarDisplayLabel.textColor = Self.toolbarPrimaryForegroundColor
        addressBarDisplayLabel.lineBreakMode = .byTruncatingMiddle
        addressBarDisplayLabel.onActivate = { [weak self] in
            self?.beginAddressEditing()
        }

        addressBarEditorField.translatesAutoresizingMaskIntoConstraints = false
        addressBarEditorField.delegate = self
        addressBarEditorField.font = NSFont.systemFont(ofSize: 13.0)
        addressBarEditorField.focusRingType = .none
        addressBarEditorField.alignment = .right
        addressBarEditorField.isBezeled = false
        addressBarEditorField.isBordered = false
        addressBarEditorField.drawsBackground = false
        addressBarEditorField.cell?.lineBreakMode = .byClipping
        addressBarEditorField.isHidden = true

        tabSearchField.translatesAutoresizingMaskIntoConstraints = false
        tabSearchField.font = NSFont.systemFont(ofSize: 12.0)
        tabSearchField.placeholderString = "タブを検索"
        tabSearchField.sendsSearchStringImmediately = true
        tabSearchField.sendsWholeSearchString = false
        tabSearchField.target = self
        tabSearchField.action = #selector(tabSearchDidChange(_:))
        tabSearchField.delegate = self

        let toolbarContent = toolbarContainer.contentLayoutView
        toolbarContent.addSubview(navigationButtonRow)
        toolbarContent.addSubview(groupSelectorButton)
        toolbarContent.addSubview(tabStripContainer)
        toolbarContent.addSubview(newTabButton)
        toolbarContent.addSubview(rightPanelView)
        rightPanelView.addSubview(addressBarDisplayLabel)
        rightPanelView.addSubview(addressBarEditorField)
        rightPanelView.addSubview(tabSearchField)

        let leftLeading = navigationButtonRow.leadingAnchor.constraint(equalTo: toolbarContent.leadingAnchor, constant: 84)
        let leftTop = navigationButtonRow.topAnchor.constraint(equalTo: toolbarContent.topAnchor, constant: 18)
        leftButtonRowLeadingConstraint = leftLeading
        leftButtonRowTopConstraint = leftTop
        let tabWidth = tabStripContainer.widthAnchor.constraint(equalToConstant: 520)
        tabStripWidthConstraint = tabWidth
        let rightPanelWidth = rightPanelView.widthAnchor.constraint(equalToConstant: 250)
        rightPanelWidthConstraint = rightPanelWidth

        NSLayoutConstraint.activate([
            leftLeading,
            leftTop,
            navigationButtonRow.heightAnchor.constraint(equalToConstant: 22),

            groupSelectorButton.centerYAnchor.constraint(equalTo: tabStripContainer.centerYAnchor),
            groupSelectorButton.trailingAnchor.constraint(equalTo: tabStripContainer.leadingAnchor, constant: -6),
            groupSelectorButton.widthAnchor.constraint(equalToConstant: 28),
            groupSelectorButton.heightAnchor.constraint(equalToConstant: 24),

            tabWidth,
            tabStripContainer.centerXAnchor.constraint(equalTo: toolbarContent.centerXAnchor),
            tabStripContainer.topAnchor.constraint(equalTo: toolbarContent.topAnchor, constant: 1),
            tabStripContainer.bottomAnchor.constraint(equalTo: toolbarContent.bottomAnchor, constant: -1),
            groupSelectorButton.leadingAnchor.constraint(greaterThanOrEqualTo: navigationButtonRow.trailingAnchor, constant: 10),
            tabStripContainer.leadingAnchor.constraint(greaterThanOrEqualTo: groupSelectorButton.trailingAnchor, constant: 6),

            tabStripScrollView.topAnchor.constraint(equalTo: tabStripContainer.topAnchor),
            tabStripScrollView.leadingAnchor.constraint(equalTo: tabStripContainer.leadingAnchor),
            tabStripScrollView.trailingAnchor.constraint(equalTo: tabStripContainer.trailingAnchor),
            tabStripScrollView.bottomAnchor.constraint(equalTo: tabStripContainer.bottomAnchor),
            tabInteractionView.topAnchor.constraint(equalTo: tabStripContainer.topAnchor),
            tabInteractionView.leadingAnchor.constraint(equalTo: tabStripContainer.leadingAnchor),
            tabInteractionView.trailingAnchor.constraint(equalTo: tabStripContainer.trailingAnchor),
            tabInteractionView.bottomAnchor.constraint(equalTo: tabStripContainer.bottomAnchor),

            newTabButton.centerYAnchor.constraint(equalTo: tabStripContainer.centerYAnchor),
            newTabButton.leadingAnchor.constraint(equalTo: tabStripContainer.trailingAnchor, constant: 6),
            newTabButton.trailingAnchor.constraint(lessThanOrEqualTo: rightPanelView.leadingAnchor, constant: -8),
            newTabButton.widthAnchor.constraint(equalToConstant: 24),
            newTabButton.heightAnchor.constraint(equalToConstant: 24),

            rightPanelView.trailingAnchor.constraint(equalTo: toolbarContent.trailingAnchor, constant: -10),
            rightPanelView.topAnchor.constraint(equalTo: toolbarContent.topAnchor, constant: 4),
            rightPanelView.bottomAnchor.constraint(equalTo: toolbarContent.bottomAnchor, constant: -4),
            rightPanelWidth,

            addressBarDisplayLabel.topAnchor.constraint(equalTo: rightPanelView.topAnchor, constant: 1),
            addressBarDisplayLabel.leadingAnchor.constraint(equalTo: rightPanelView.leadingAnchor, constant: 6),
            addressBarDisplayLabel.trailingAnchor.constraint(equalTo: rightPanelView.trailingAnchor, constant: -6),
            addressBarDisplayLabel.heightAnchor.constraint(equalToConstant: 18),

            addressBarEditorField.topAnchor.constraint(equalTo: addressBarDisplayLabel.topAnchor),
            addressBarEditorField.leadingAnchor.constraint(equalTo: addressBarDisplayLabel.leadingAnchor),
            addressBarEditorField.trailingAnchor.constraint(equalTo: addressBarDisplayLabel.trailingAnchor),
            addressBarEditorField.heightAnchor.constraint(equalTo: addressBarDisplayLabel.heightAnchor),

            tabSearchField.leadingAnchor.constraint(equalTo: rightPanelView.leadingAnchor, constant: 4),
            tabSearchField.trailingAnchor.constraint(equalTo: rightPanelView.trailingAnchor, constant: -4),
            tabSearchField.topAnchor.constraint(equalTo: addressBarDisplayLabel.bottomAnchor, constant: 4),
            tabSearchField.heightAnchor.constraint(equalToConstant: 20),
            tabSearchField.bottomAnchor.constraint(lessThanOrEqualTo: rightPanelView.bottomAnchor, constant: -2)
        ])

        setupTabStripInteractions()
        applyAddressDisplayMode(display: "")
        syncGroupSelectorSelection()
        refreshNavigationButtons()
    }

    private func configureBindings() {
        tabManager.delegate = self
        actions.focusAddressField = { [weak self] in
            self?.beginAddressEditing()
        }
        actions.confirmCloseProtectedTab = { [weak self] in
            self?.confirmCloseProtectedTab() ?? false
        }
        actions.performGestureTabSwitch = { [weak self] direction in
            self?.performGestureTabSwitch(direction: direction)
        }
        actions.beginInteractiveGestureTabSwitch = { [weak self] direction in
            self?.beginInteractiveTabSwitch(direction: direction) ?? false
        }
        actions.updateInteractiveGestureTabSwitch = { [weak self] totalX in
            self?.updateInteractiveTabSwitch(totalX: totalX)
        }
        actions.finishInteractiveGestureTabSwitch = { [weak self] totalX in
            self?.finishInteractiveTabSwitch(totalX: totalX)
        }
    }

    private func configurePreferenceObserver() {
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: BrowserPreferences.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyPreferenceChangesIfNeeded()
        }
    }

    private func configureBookmarkObserver() {
        bookmarkObserver = NotificationCenter.default.addObserver(
            forName: BookmarkStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncBookmarkedStateFromStore()
        }
    }

    private func applyPreferenceChangesIfNeeded() {
        let prefs = BrowserPreferences.shared
        let removedPersistedHarmfulHosts = lastHarmfulAllowedHosts.subtracting(prefs.harmfulSiteAllowedHosts)
        let shouldReconfigureTabs = (prefs.ephemeralModeEnabled != lastEphemeralMode)
            || (prefs.sendDoNotTrack != lastDoNotTrack)
            || (prefs.contentBlockingEnabled != lastContentBlockingEnabled)
            || (prefs.contentBlockingExceptionSignature != lastContentBlockingExceptionSignature)
            || (prefs.popupBlockingEnabled != lastPopupBlockingEnabled)
            || (prefs.preferredContentLanguage != lastPreferredContentLanguage)

        lastEphemeralMode = prefs.ephemeralModeEnabled
        lastDoNotTrack = prefs.sendDoNotTrack
        lastContentBlockingEnabled = prefs.contentBlockingEnabled
        lastContentBlockingExceptionSignature = prefs.contentBlockingExceptionSignature
        lastPopupBlockingEnabled = prefs.popupBlockingEnabled
        lastPreferredContentLanguage = prefs.preferredContentLanguage
        lastHarmfulAllowedHosts = prefs.harmfulSiteAllowedHosts
        temporarilyAllowedHosts.subtract(removedPersistedHarmfulHosts)

        guard shouldReconfigureTabs else { return }
        tabManager.reconfigureAllTabsForCurrentPreferences()
    }

    private func syncBookmarkedStateFromStore() {
        let bookmarkedURLStrings = Set(BookmarkStore.shared.all().map(\.urlString))
        tabManager.syncBookmarkedStates(bookmarkedURLStrings: bookmarkedURLStrings)
    }

    private func ensureInitialTabVisible() {
        if let current = tabManager.currentWebView {
            if current.superview == nil {
                attachWebView(current)
            }
            if current.url == nil {
                current.load(URLRequest(url: BrowserSession.defaultHomeURL))
            }
            return
        }

        actions.newTab()
    }

    private func configureToolbarSymbolButton(
        _ button: NSButton,
        symbolName: String,
        pointSize: CGFloat,
        weight: NSFont.Weight,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = action
        button.isBordered = false
        button.title = ""
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        button.contentTintColor = Self.toolbarSecondaryForegroundColor
        button.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    @objc private func didTapNewTab() {
        animateNewTabOpenFromToolbar()
    }

    @objc private func didTapBackButton() {
        actions.goBack()
        refreshNavigationButtons()
    }

    @objc private func didTapForwardButton() {
        actions.goForward()
        refreshNavigationButtons()
    }

    @objc private func didTapReloadButton() {
        actions.reload()
    }

    @objc private func didTapBookmarkButton() {
        menuToggleBookmark()
        refreshNavigationButtons()
    }

    @objc private func didTapShareButton() {
        guard let url = tabManager.currentWebView?.url else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: shareButton.bounds, of: shareButton, preferredEdge: .maxY)
    }

    @objc private func didTapGroupSelector() {
        let menu = NSMenu()
        for group in BrowserTabGroup.allCases {
            let item = NSMenuItem(title: group.displayName, action: #selector(didSelectGroupMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = group.rawValue
            item.state = (group == tabManager.currentGroup) ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: groupSelectorButton.bounds.height + 4), in: groupSelectorButton)
    }

    @objc private func didSelectGroupMenuItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let group = BrowserTabGroup(rawValue: raw) else { return }
        tabManager.switchGroup(group)
    }

    // MARK: - Menu Actions
    func menuNewTab() {
        animateNewTabOpenFromToolbar()
    }

    func menuCloseTab() {
        actions.tabClose()
    }

    func menuReopenClosedTab() {
        actions.tabReopenClosed()
    }

    func menuGoBack() {
        actions.goBack()
    }

    func menuGoForward() {
        actions.goForward()
    }

    func menuReload() {
        actions.reload()
    }

    func menuReloadAllTabs() {
        actions.reloadAll()
    }

    func menuFocusAddressBar() {
        beginAddressEditing()
    }

    func menuFocusTabSearch() {
        window?.makeFirstResponder(tabSearchField)
    }

    func menuSelectNextTab() {
        actions.tabNext()
    }

    func menuSelectPreviousTab() {
        actions.tabPrev()
    }

    func menuZoomIn() {
        tabManager.setCurrentPageZoom(tabManager.currentPageZoom + 0.1)
    }

    func menuZoomOut() {
        tabManager.setCurrentPageZoom(tabManager.currentPageZoom - 0.1)
    }

    func menuResetZoom() {
        tabManager.setCurrentPageZoom(1.0)
    }

    func menuPrintPage() {
        guard let webView = tabManager.currentWebView else { return }
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let modalWindow = window ?? NSApp.keyWindow {
            operation.runModal(for: modalWindow, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    func menuExportPDF() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let webView = self.tabManager.currentWebView else { return }

            let rawTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pageTitle = rawTitle.isEmpty ? "Page" : rawTitle

            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            savePanel.nameFieldStringValue = pageTitle + ".pdf"
            savePanel.allowedContentTypes = [.pdf]

            if let modalWindow = self.window ?? NSApp.keyWindow {
                savePanel.beginSheetModal(for: modalWindow) { [weak self] response in
                    guard response == .OK, let destinationURL = savePanel.url else { return }
                    self?.exportWebViewToPDF(webView, destinationURL: destinationURL)
                }
            } else if savePanel.runModal() == .OK, let destinationURL = savePanel.url {
                self.exportWebViewToPDF(webView, destinationURL: destinationURL)
            }
        }
    }

    private func exportWebViewToPDF(_ webView: WKWebView, destinationURL: URL) {
        DispatchQueue.main.async { [weak self, weak webView] in
            guard let self, let webView else { return }
            webView.layoutSubtreeIfNeeded()

            let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
            printInfo.jobDisposition = .save
            printInfo.horizontalPagination = .automatic
            printInfo.verticalPagination = .automatic
            printInfo.isHorizontallyCentered = true
            printInfo.topMargin = 16
            printInfo.bottomMargin = 16
            printInfo.leftMargin = 16
            printInfo.rightMargin = 16
            printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destinationURL

            let operation = webView.printOperation(with: printInfo)
            operation.showsPrintPanel = false
            operation.showsProgressPanel = true

            let didRunSelector = #selector(Self.exportPDFDidRun(_:success:contextInfo:))
            let context = Unmanaged.passRetained(PDFExportContext(controller: self, fallbackData: self.fallbackPDFData(for: webView), destinationURL: destinationURL)).toOpaque()

            guard let modalWindow = self.window ?? NSApp.keyWindow else {
                self.finishPDFExport(success: false, contextInfo: context)
                return
            }
            operation.runModal(for: modalWindow, delegate: self, didRun: didRunSelector, contextInfo: context)
        }
    }

    @objc private func exportPDFDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        finishPDFExport(success: success, contextInfo: contextInfo)
    }

    private func finishPDFExport(success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        guard let contextInfo else { return }
        let context = Unmanaged<PDFExportContext>.fromOpaque(contextInfo).takeRetainedValue()
        if success {
            openLocalDocument(context.destinationURL, preferNewTab: true)
            return
        }

        if let fallbackData = context.fallbackData {
            do {
                try fallbackData.write(to: context.destinationURL, options: .atomic)
                openLocalDocument(context.destinationURL, preferNewTab: true)
                return
            } catch {
                context.controller.presentDocumentAlert(
                    title: "PDF保存に失敗しました",
                    message: error.localizedDescription,
                    style: .warning
                )
                return
            }
        }

        context.controller.presentDocumentAlert(
            title: "PDF保存に失敗しました",
            message: "このページのPDFを書き出せませんでした。",
            style: .warning
        )
    }

    private func fallbackPDFData(for webView: WKWebView) -> Data? {
        let targetRect = webView.bounds.isEmpty ? NSRect(x: 0, y: 0, width: 1280, height: 800) : webView.bounds
        return webView.dataWithPDF(inside: targetRect)
    }

    private func presentDocumentAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if let modalWindow = window ?? NSApp.keyWindow {
            alert.beginSheetModal(for: modalWindow)
        } else {
            alert.runModal()
        }
    }

    func menuToggleWebInspector() {
        guard let webView = tabManager.currentWebView else { return }
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        let pageTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = webView.url?.host ?? "this Mac"

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Open Page Inspector in Safari"
        alert.informativeText = """
        Vidarr のページは inspectable に設定されています。

        1. Safari を開く
        2. Safari > Settings > Advanced で Web Developer 機能を有効化
        3. Safari > Develop > \(Host.current().localizedName ?? "Mac") > Vidarr
        4. \(pageTitle?.isEmpty == false ? pageTitle! : host) を選択
        """
        alert.addButton(withTitle: "Open Safari")
        alert.addButton(withTitle: "OK")

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Safari.app"))
            }
        }

        if let modalWindow = window ?? NSApp.keyWindow {
            alert.beginSheetModal(for: modalWindow, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    func menuPreparePasswordAutoFill() {
        guard let webView = tabManager.currentWebView else { return }

        if BrowserPreferences.shared.ephemeralModeEnabled {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "一時モードではログイン保持が弱くなります"
            alert.informativeText = "Appleの標準オートフィルは使えますが、再起動後の保持を重視するならフットプリント最小化をOFFにしてください。"
            alert.addButton(withTitle: "OK")
            if let window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }

        let script = """
        (() => {
          const isVisible = (el) => {
            const style = getComputedStyle(el);
            const rect = el.getBoundingClientRect();
            return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0 && !el.disabled && !el.readOnly;
          };

          const password = Array.from(document.querySelectorAll('input[type="password"]')).find(isVisible);
          if (!password) { return false; }

          const fields = password.form ? Array.from(password.form.querySelectorAll("input")) : Array.from(document.querySelectorAll("input"));
          const user = fields.find((el) => {
            if (!isVisible(el) || el === password) { return false; }
            const t = (el.type || "").toLowerCase();
            const ac = (el.autocomplete || "").toLowerCase();
            return t === "text" || t === "email" || ac.includes("username") || ac.includes("email");
          });

          if (user) { user.focus(); }
          password.focus();
          return true;
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else { return }
            guard let found = result as? Bool, found else {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "ログインフォームが見つかりません"
                alert.informativeText = "ログイン欄をクリックしてから、もう一度 AutoFill Password を実行してください。"
                alert.addButton(withTitle: "OK")
                if let window = self.window {
                    alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
                return
            }
        }
    }

    func menuToggleBookmark() {
        guard let webView = tabManager.currentWebView,
              let url = webView.url else {
            return
        }
        let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if BookmarkStore.shared.contains(url: url) {
            BookmarkStore.shared.remove(url: url)
        } else {
            BookmarkStore.shared.addOrUpdate(url: url, title: title)
        }
    }

    func menuToggleContentBlockingForCurrentSite() {
        guard let host = tabManager.currentWebView?.url?.host?.lowercased(), !host.isEmpty else {
            presentTransientAlert(title: "このサイトでは変更できません", message: "現在のページに有効なホスト名がありません。", style: .warning)
            return
        }

        let prefs = BrowserPreferences.shared
        let isDisabled = prefs.isContentBlockingDisabled(for: host)
        prefs.setContentBlockingDisabled(!isDisabled, for: host)

        let title = isDisabled ? "広告ブロックを有効化" : "広告ブロックを無効化"
        let message = isDisabled
            ? "\(host) で広告/追跡ブロックを再度有効化しました。"
            : "\(host) を広告/追跡ブロックの例外に追加しました。"
        presentTransientAlert(title: title, message: message, style: .informational)
    }

    func currentDevelopMenuState() -> (host: String?, adBlockingEnabledForSite: Bool, globalContentBlockingEnabled: Bool) {
        let host = tabManager.currentWebView?.url?.host?.lowercased()
        let prefs = BrowserPreferences.shared
        let adBlockingEnabledForSite: Bool
        if let host, !host.isEmpty {
            adBlockingEnabledForSite = prefs.contentBlockingEnabled && !prefs.isContentBlockingDisabled(for: host)
        } else {
            adBlockingEnabledForSite = prefs.contentBlockingEnabled
        }
        return (host, adBlockingEnabledForSite, prefs.contentBlockingEnabled)
    }

    func menuOpenExternalListURL(_ url: URL) {
        guard isSafeStoredURL(url) else {
            presentTransientAlert(title: "開けないURLです", message: url.absoluteString, style: .warning)
            return
        }
        tabManager.newTab(url: url)
    }

    func menuOpenLocalFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf, .html, .plainText]

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.openLocalDocument(url, preferNewTab: true)
        }

        if let modalWindow = window ?? NSApp.keyWindow {
            panel.beginSheetModal(for: modalWindow, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func openLocalDocument(_ url: URL, preferNewTab: Bool) {
        guard isSafeStoredURL(url) else { return }
        guard Self.isBrowserOpenableLocalDocument(url) else {
            NSWorkspace.shared.open(url)
            return
        }
        retainSecurityScope(for: url)
        if preferNewTab || tabManager.currentWebView == nil {
            tabManager.newTab(url: url)
        } else {
            session.load(url: url)
        }
    }

    private func retainSecurityScope(for url: URL) {
        guard url.isFileURL else { return }
        if retainedDocumentSecurityScopes[url.path] != nil { return }

        if url.startAccessingSecurityScopedResource() {
            retainedDocumentSecurityScopes[url.path] = url
            return
        }

        if let preferredDirectory = BrowserPreferences.shared.preferredDownloadDirectoryURL(),
           url.path.hasPrefix(preferredDirectory.path),
           preferredDirectory.startAccessingSecurityScopedResource() {
            retainedDocumentSecurityScopes[preferredDirectory.path] = preferredDirectory
        }
    }

    nonisolated fileprivate static func isBrowserOpenableLocalDocument(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext) {
            return type.conforms(to: .pdf) || type.conforms(to: .html) || type.conforms(to: .plainText)
        }
        return ["pdf", "html", "htm", "txt"].contains(ext)
    }

    func restoreSavedSessionIfAvailable() {
        guard let snapshot = BrowserSessionStore.shared.load() else { return }
        tabManager.restoreSession(from: snapshot)
    }

    func saveSessionSnapshot() {
        BrowserSessionStore.shared.save(tabManager.sessionSnapshot())
    }

    @objc private func tabSearchDidChange(_ sender: NSSearchField) {
        tabSearchQuery = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rebuildTabStrip()
    }

    private func beginAddressEditing() {
        if isAddressEditing {
            focusAddressEditor(selectAll: true)
            return
        }
        isAddressEditing = true

        applyAddressEditingMode()
        addressBarEditorField.stringValue = currentAddressURLString

        focusAddressEditor(selectAll: true)
    }

    private func endAddressEditingWithoutSubmit() {
        guard isAddressEditing else { return }
        isAddressEditing = false
        let display = tabManager.currentWebView?.url?.absoluteString ?? ""
        applyAddressDisplayMode(display: display)
        window?.makeFirstResponder(nil)
    }

    private func submitAddressFieldIfNeeded() {
        let input = addressBarEditorField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.isEmpty {
            actions.openLocationInput(input)
        }
        isAddressEditing = false
        applyAddressDisplayMode(display: input)
        window?.makeFirstResponder(nil)
    }

    private func applyAddressDisplayMode(display: String) {
        currentAddressURLString = display
        addressBarDisplayLabel.stringValue = display
        addressBarDisplayLabel.toolTip = display
        addressBarEditorField.stringValue = display
        applyAddressReadOnlyMode()
    }

    private func applyAddressReadOnlyMode() {
        addressBarEditorField.isHidden = true
        addressBarDisplayLabel.isHidden = false
    }

    private func applyAddressEditingMode() {
        addressBarDisplayLabel.isHidden = true
        addressBarEditorField.isHidden = false
    }

    private func focusAddressEditor(selectAll: Bool) {
        guard let window else { return }
        window.makeFirstResponder(addressBarEditorField)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.addressBarEditorField)
            let length = self.addressBarEditorField.stringValue.count
            if let editor = self.addressBarEditorField.currentEditor() {
                editor.selectedRange = selectAll
                    ? NSRange(location: 0, length: length)
                    : NSRange(location: length, length: 0)
            } else if selectAll {
                self.addressBarEditorField.selectText(nil)
            }
        }
    }

    private func installLongPressOpenInBackgroundIfNeeded(for webView: WKWebView) {
        let contentController = webView.configuration.userContentController
        let controllerID = ObjectIdentifier(contentController)
        guard !configuredLongPressControllers.contains(controllerID) else { return }
        configuredLongPressControllers.insert(controllerID)

        let handlerBox = WeakScriptMessageHandler(target: self)
        longPressHandlerBoxes[controllerID] = handlerBox
        contentController.removeScriptMessageHandler(forName: Self.longPressLinkMessageName)
        contentController.removeScriptMessageHandler(forName: Self.selectionSearchMessageName)
        contentController.add(handlerBox, name: Self.longPressLinkMessageName)
        contentController.add(handlerBox, name: Self.selectionSearchMessageName)

        let source = """
        (() => {
            if (window.__vidarrLongPressInstalled) { return; }
            window.__vidarrLongPressInstalled = true;

            const HOLD_MS = 380;
            const MOVE_TOLERANCE = 14;
            const SELECTION_MIN_LENGTH = 1;
            var timer = null;
            var activeAnchor = null;
            var startX = 0;
            var startY = 0;
            var selectionButton = null;

            function ensureSelectionButton() {
                if (selectionButton) { return selectionButton; }
                const button = document.createElement('button');
                button.type = 'button';
                button.setAttribute('aria-label', 'Search selection');
                button.innerHTML = '<svg width="15" height="15" viewBox="0 0 16 16" fill="none" aria-hidden="true"><circle cx="6.75" cy="6.75" r="4.75" stroke="rgba(255,255,255,0.95)" stroke-width="1.5"/><path d="M10.5 10.5L14 14" stroke="rgba(255,255,255,0.95)" stroke-width="1.5" stroke-linecap="round"/></svg>';
                button.style.position = 'fixed';
                button.style.display = 'none';
                button.style.alignItems = 'center';
                button.style.justifyContent = 'center';
                button.style.width = '34px';
                button.style.height = '34px';
                button.style.border = '1px solid rgba(255,255,255,0.3)';
                button.style.borderRadius = '10px';
                button.style.background = 'rgba(26,28,32,0.82)';
                button.style.backdropFilter = 'blur(10px)';
                button.style.boxShadow = '0 8px 20px rgba(0,0,0,0.28)';
                button.style.padding = '0';
                button.style.margin = '0';
                button.style.cursor = 'pointer';
                button.style.zIndex = '2147483647';
                button.style.opacity = '0';
                button.style.transition = 'opacity 120ms ease';

                button.addEventListener('mousedown', (event) => {
                    event.preventDefault();
                    event.stopPropagation();
                }, true);

                button.addEventListener('click', (event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    const text = (window.getSelection ? window.getSelection().toString() : '').trim();
                    hideSelectionButton();
                    if (!text) { return; }
                    window.webkit.messageHandlers.\(Self.selectionSearchMessageName).postMessage({
                        query: text
                    });
                }, true);

                document.documentElement.appendChild(button);
                selectionButton = button;
                return button;
            }

            function hideSelectionButton() {
                if (!selectionButton) { return; }
                selectionButton.style.opacity = '0';
                selectionButton.style.display = 'none';
            }

            function showSelectionButtonAt(x, y) {
                const button = ensureSelectionButton();
                button.style.left = `${x}px`;
                button.style.top = `${y}px`;
                button.style.display = 'flex';
                requestAnimationFrame(() => {
                    button.style.opacity = '1';
                });
            }

            function updateSelectionButton() {
                const selection = window.getSelection ? window.getSelection() : null;
                if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
                    hideSelectionButton();
                    return;
                }

                const selectedText = selection.toString().trim();
                if (selectedText.length < SELECTION_MIN_LENGTH) {
                    hideSelectionButton();
                    return;
                }

                const range = selection.getRangeAt(0);
                const rect = range.getBoundingClientRect();
                if (!rect || (rect.width === 0 && rect.height === 0)) {
                    hideSelectionButton();
                    return;
                }

                const buttonSize = 34;
                const margin = 8;
                const maxX = Math.max(margin, window.innerWidth - buttonSize - margin);
                const x = Math.min(maxX, Math.max(margin, rect.right - buttonSize));
                const preferredY = rect.top - buttonSize - margin;
                const fallbackY = rect.bottom + margin;
                const y = preferredY > margin
                    ? preferredY
                    : Math.min(window.innerHeight - buttonSize - margin, Math.max(margin, fallbackY));

                showSelectionButtonAt(x, y);
            }

            function clearTimer() {
                if (timer !== null) {
                    clearTimeout(timer);
                    timer = null;
                }
            }

            function anchorFromEvent(event) {
                const path = event.composedPath ? event.composedPath() : [];
                for (const node of path) {
                    if (node && node.tagName && node.tagName.toLowerCase() === 'a' && node.href) {
                        return node;
                    }
                }
                if (event.target && event.target.closest) {
                    const found = event.target.closest('a[href]');
                    if (found && found.href) { return found; }
                }
                return null;
            }

            function resetState() {
                clearTimer();
                activeAnchor = null;
                startX = 0;
                startY = 0;
            }

            document.addEventListener('mousedown', (event) => {
                if (event.button !== 0) { return; }
                const anchor = anchorFromEvent(event);
                if (!anchor) {
                    resetState();
                    return;
                }
                activeAnchor = anchor;
                startX = event.clientX;
                startY = event.clientY;
                clearTimer();
                timer = setTimeout(() => {
                    if (!activeAnchor || !activeAnchor.href) { return; }
                    window.__vidarrSuppressLongPressClick = true;
                    window.webkit.messageHandlers.\(Self.longPressLinkMessageName).postMessage({
                        href: activeAnchor.href
                    });
                }, HOLD_MS);
            }, true);

            document.addEventListener('mousemove', (event) => {
                if (!activeAnchor) { return; }
                const dx = event.clientX - startX;
                const dy = event.clientY - startY;
                if (Math.hypot(dx, dy) > MOVE_TOLERANCE) {
                    resetState();
                }
            }, true);

            document.addEventListener('mouseup', () => {
                resetState();
                setTimeout(updateSelectionButton, 0);
            }, true);

            document.addEventListener('dragstart', () => {
                resetState();
                hideSelectionButton();
            }, true);

            document.addEventListener('click', (event) => {
                if (!window.__vidarrSuppressLongPressClick) { return; }
                window.__vidarrSuppressLongPressClick = false;
                event.preventDefault();
                event.stopPropagation();
            }, true);

            window.addEventListener('blur', () => {
                resetState();
                window.__vidarrSuppressLongPressClick = false;
                hideSelectionButton();
            }, true);

            document.addEventListener('selectionchange', () => {
                if (window.__vidarrSuppressLongPressClick) { return; }
                setTimeout(updateSelectionButton, 0);
            }, true);

            document.addEventListener('scroll', () => {
                hideSelectionButton();
            }, true);

            document.addEventListener('mousedown', (event) => {
                if (!selectionButton) { return; }
                if (event.target === selectionButton || selectionButton.contains(event.target)) {
                    return;
                }
                hideSelectionButton();
            }, true);
        })();
        """
        let script = WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(script)
    }

    private func attachWebView(_ webView: WKWebView) {
        webContainer.subviews.forEach { $0.removeFromSuperview() }
        overlayView = nil

        installLongPressOpenInBackgroundIfNeeded(for: webView)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        clearLayoutConstraints(for: webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webContainer.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: webContainer.topAnchor),
            webView.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor)
        ])

        let overlay = GestureOverlayView(frame: .zero)
        overlay.actionCenter = actions
        overlay.translatesAutoresizingMaskIntoConstraints = false
        webContainer.addSubview(overlay)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: webContainer.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor)
        ])

        overlayView = overlay
        applyAddressDisplayMode(display: webView.url?.absoluteString ?? "")
        rebuildTabStrip()
        refreshNavigationButtons()
    }

    private func performGestureTabSwitch(direction: ActionCenter.GestureTabSwitchDirection) {
        guard interactiveTabSwitchState == nil else { return }
        guard beginInteractiveTabSwitch(direction: direction), let state = interactiveTabSwitchState else {
            if shouldOpenNewTabAtRightEdge(for: direction) {
                animateNewTabOpenFromRightEdge()
            }
            return
        }
        completeProgrammaticTabSwitch(state)
    }

    private func shouldOpenNewTabAtRightEdge(for direction: ActionCenter.GestureTabSwitchDirection) -> Bool {
        guard direction == .left else { return false }
        let count = tabManager.tabCount
        guard count > 0 else { return false }
        return resolvedVisualCurrentIndex() == (count - 1)
    }

    private func animateNewTabOpenFromToolbar() {
        guard interactiveTabSwitchState == nil else { return }
        guard let fromWebView = tabManager.currentWebView else {
            actions.newTab()
            return
        }

        let group = tabManager.currentGroup
        let newWebView = BrowserSession.makeConfiguredWebView(for: group)
        _ = tabManager.addTab(
            webView: newWebView,
            initialURL: BrowserSession.defaultHomeURL,
            shouldLoadInitialURL: true,
            group: group,
            activate: false
        )
        let targetIndex = tabManager.tabCount - 1
        guard targetIndex >= 0 else {
            actions.newTab()
            return
        }

        prepareInteractiveTabSwitchViews(from: fromWebView, to: newWebView, direction: .left)
        let state = InteractiveTabSwitchState(
            fromWebView: fromWebView,
            toWebView: newWebView,
            targetIndex: targetIndex,
            direction: .left
        )
        interactiveTabSwitchState = state

        let spawnAnchor: CGPoint
        if let convertedFrame = newTabButton.superview?.convert(newTabButton.frame, to: tabStripContainer) {
            spawnAnchor = CGPoint(x: convertedFrame.midX, y: convertedFrame.midY)
        } else {
            spawnAnchor = rightEdgeTabSpawnAnchorPoint()
        }
        animateTabCreationInStrip(from: spawnAnchor, targetIndex: targetIndex)
        completeNewTabTransition(state, emphasizeBirth: true)
    }

    private func animateNewTabOpenFromRightEdge() {
        guard interactiveTabSwitchState == nil else { return }
        guard let fromWebView = tabManager.currentWebView else {
            actions.newTab()
            return
        }

        let stripSpawnAnchor = rightEdgeTabSpawnAnchorPoint()
        let group = tabManager.currentGroup
        let newWebView = BrowserSession.makeConfiguredWebView(for: group)
        _ = tabManager.addTab(
            webView: newWebView,
            initialURL: BrowserSession.defaultHomeURL,
            shouldLoadInitialURL: true,
            group: group,
            activate: false
        )
        let targetIndex = tabManager.tabCount - 1
        guard targetIndex >= 0 else {
            actions.newTab()
            return
        }

        prepareInteractiveTabSwitchViews(from: fromWebView, to: newWebView, direction: .left)
        let state = InteractiveTabSwitchState(
            fromWebView: fromWebView,
            toWebView: newWebView,
            targetIndex: targetIndex,
            direction: .left
        )
        interactiveTabSwitchState = state
        animateTabCreationInStrip(from: stripSpawnAnchor, targetIndex: targetIndex)
        completeNewTabTransition(state, emphasizeBirth: false)
    }

    private func rightEdgeTabSpawnAnchorPoint() -> CGPoint {
        layoutTabStripAndRevealActive()
        let bounds = tabStripContainer.bounds
        let y = bounds.midY

        let chips = tabStripStackView.arrangedSubviews.compactMap { $0 as? TabChipView }
        guard let lastChip = chips.last else {
            return CGPoint(x: max(16, bounds.maxX - 18), y: y)
        }

        let rect = lastChip.convert(lastChip.bounds, to: tabStripContainer)
        let x = min(bounds.maxX - 16, rect.maxX + 10)
        return CGPoint(x: max(16, x), y: y)
    }

    private func animateTabCreationInStrip(from source: CGPoint, targetIndex: Int) {
        layoutTabStripAndRevealActive()
        guard let targetChip = tabChipView(for: targetIndex) else { return }

        let targetRect = targetChip.convert(targetChip.bounds, to: tabStripContainer)
        guard targetRect.width > 8, targetRect.height > 8 else { return }

        let startSize: CGFloat = 18
        let startRect = CGRect(
            x: source.x - (startSize * 0.5),
            y: source.y - (startSize * 0.5),
            width: startSize,
            height: startSize
        )

        let birthView = TabBirthAnimationView(frame: startRect)
        birthView.alphaValue = 0
        tabStripContainer.addSubview(birthView)

        let popRect = startRect.insetBy(dx: -2.5, dy: -2.5)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.11
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            birthView.animator().alphaValue = 1.0
            birthView.animator().frame = popRect
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                birthView.animator().frame = targetRect
                birthView.animator().alphaValue = 0.24
                birthView.plusImageView.animator().alphaValue = 0
            } completionHandler: { [weak self, weak targetChip] in
                birthView.removeFromSuperview()
                guard let self, let targetChip else { return }
                targetChip.wantsLayer = true
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.10
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    targetChip.animator().alphaValue = 0.92
                    targetChip.animator().layer?.transform = CATransform3DMakeScale(1.03, 1.03, 1)
                } completionHandler: {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.14
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        targetChip.animator().alphaValue = 1.0
                        targetChip.animator().layer?.transform = CATransform3DIdentity
                    }
                    self.layoutTabStripAndRevealActive()
                }
            }
        }
    }

    private func completeNewTabTransition(_ state: InteractiveTabSwitchState, emphasizeBirth: Bool) {
        interactiveTabSwitchState = nil
        animateStyledTabCommitTransition(
            state,
            emphasizeBirth: emphasizeBirth,
            startFromCurrentFrames: false
        )
    }

    private func beginInteractiveTabSwitch(direction: ActionCenter.GestureTabSwitchDirection) -> Bool {
        guard interactiveTabSwitchState == nil else { return true }

        let count = tabManager.tabCount
        guard count > 1 else { return false }

        let currentIndex = resolvedVisualCurrentIndex()
        guard currentIndex >= 0, currentIndex < count else { return false }
        guard let fromWebView = resolvedVisualCurrentWebView() else { return false }

        let targetIndex: Int
        switch direction {
        case .left:
            guard currentIndex + 1 < count else { return false }
            targetIndex = currentIndex + 1
        case .right:
            guard currentIndex - 1 >= 0 else { return false }
            targetIndex = currentIndex - 1
        }
        guard let toWebView = tabManager.webView(at: targetIndex) else { return false }

        prepareInteractiveTabSwitchViews(from: fromWebView, to: toWebView, direction: direction)
        interactiveTabSwitchState = InteractiveTabSwitchState(
            fromWebView: fromWebView,
            toWebView: toWebView,
            targetIndex: targetIndex,
            direction: direction
        )
        return true
    }

    private func prepareInteractiveTabSwitchViews(
        from fromWebView: WKWebView,
        to toWebView: WKWebView,
        direction: ActionCenter.GestureTabSwitchDirection
    ) {
        fromWebView.navigationDelegate = self
        fromWebView.uiDelegate = self
        toWebView.navigationDelegate = self
        toWebView.uiDelegate = self

        clearLayoutConstraints(for: fromWebView)
        clearLayoutConstraints(for: toWebView)
        fromWebView.translatesAutoresizingMaskIntoConstraints = true
        toWebView.translatesAutoresizingMaskIntoConstraints = true

        let bounds = webContainer.bounds
        fromWebView.frame = bounds
        let startX = direction == .left
            ? bounds.width + UI.tabSwitchGap
            : -(bounds.width + UI.tabSwitchGap)
        toWebView.frame = bounds.offsetBy(dx: pixelAligned(startX), dy: 0)

        if toWebView.superview !== webContainer {
            if let overlay = overlayView {
                webContainer.addSubview(toWebView, positioned: .below, relativeTo: overlay)
            } else {
                webContainer.addSubview(toWebView, positioned: .below, relativeTo: fromWebView)
            }
        }

        if fromWebView.superview !== webContainer {
            if let overlay = overlayView {
                webContainer.addSubview(fromWebView, positioned: .below, relativeTo: overlay)
            } else {
                webContainer.addSubview(fromWebView)
            }
        }

        webContainer.layoutSubtreeIfNeeded()
    }

    private func completeProgrammaticTabSwitch(_ state: InteractiveTabSwitchState) {
        interactiveTabSwitchState = nil
        animateStyledTabCommitTransition(
            state,
            emphasizeBirth: false,
            startFromCurrentFrames: false
        )
    }

    private func clearLayoutConstraints(for webView: WKWebView) {
        let related = webContainer.constraints.filter { constraint in
            (constraint.firstItem as AnyObject?) === webView
                || (constraint.secondItem as AnyObject?) === webView
        }
        if !related.isEmpty {
            webContainer.removeConstraints(related)
        }
    }

    private func updateInteractiveTabSwitch(totalX: CGFloat) {
        guard let state = interactiveTabSwitchState else { return }
        let bounds = webContainer.bounds
        let width = bounds.width
        guard width > 1 else { return }
        let fullTravel = width + UI.tabSwitchGap
        let interactiveLimit = fullTravel * UI.tabSwitchInteractiveMaxProgress

        let offset: CGFloat
        switch state.direction {
        case .left:
            offset = max(-interactiveLimit, min(0, totalX))
            let fromX = pixelAligned(offset)
            let toX = pixelAligned(fullTravel + offset)
            state.fromWebView.frame = bounds.offsetBy(dx: fromX, dy: 0)
            state.toWebView.frame = bounds.offsetBy(dx: toX, dy: 0)
        case .right:
            offset = min(interactiveLimit, max(0, totalX))
            let fromX = pixelAligned(offset)
            let toX = pixelAligned(-fullTravel + offset)
            state.fromWebView.frame = bounds.offsetBy(dx: fromX, dy: 0)
            state.toWebView.frame = bounds.offsetBy(dx: toX, dy: 0)
        }
    }

    private func finishInteractiveTabSwitch(totalX: CGFloat) {
        guard let state = interactiveTabSwitchState else { return }
        interactiveTabSwitchState = nil

        let width = webContainer.bounds.width
        guard width > 1 else {
            tabManager.selectTab(index: state.targetIndex)
            return
        }

        let commitThreshold = max(84, width * 0.18)
        let shouldCommit: Bool
        switch state.direction {
        case .left:
            shouldCommit = totalX <= -commitThreshold
        case .right:
            shouldCommit = totalX >= commitThreshold
        }

        let fromTargetX: CGFloat
        let toTargetX: CGFloat
        if shouldCommit {
            fromTargetX = state.direction == .left
                ? -(width + UI.tabSwitchGap)
                : (width + UI.tabSwitchGap)
            toTargetX = 0
        } else {
            fromTargetX = 0
            toTargetX = state.direction == .left
                ? (width + UI.tabSwitchGap)
                : -(width + UI.tabSwitchGap)
        }

        let currentFromX = state.fromWebView.frame.origin.x
        let remaining = abs(fromTargetX - currentFromX)
        let normalized = min(1.0, max(0.0, remaining / max(width + UI.tabSwitchGap, 1)))
        let minDuration: TimeInterval = shouldCommit ? 0.16 : 0.16
        let maxDuration: TimeInterval = shouldCommit ? 0.24 : 0.24
        let duration = minDuration + ((maxDuration - minDuration) * TimeInterval(normalized))

        if shouldCommit {
            animateStyledTabCommitTransition(
                state,
                emphasizeBirth: false,
                startFromCurrentFrames: true
            )
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                state.fromWebView.animator().frame.origin.x = pixelAligned(fromTargetX)
                state.toWebView.animator().frame.origin.x = pixelAligned(toTargetX)
            } completionHandler: { [weak self] in
                self?.clearVisualTransitionOverride()
                self?.attachWebView(state.fromWebView)
            }
        }
    }

    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard scale > 0 else { return value.rounded() }
        return (value * scale).rounded() / scale
    }

    private func makeTransitionGapView(height: CGFloat) -> NSView {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: UI.newTabTransitionGapWidth, height: height))
        view.wantsLayer = true
        view.layer?.cornerRadius = 9
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        view.layer?.shadowOpacity = 0.22
        view.layer?.shadowRadius = 12
        view.layer?.shadowOffset = CGSize(width: 0, height: 0)
        view.alphaValue = 0.9
        return view
    }

    private func animateStyledTabCommitTransition(
        _ state: InteractiveTabSwitchState,
        emphasizeBirth: Bool,
        startFromCurrentFrames: Bool
    ) {
        let width = webContainer.bounds.width
        guard width > 1 else {
            clearVisualTransitionOverride()
            tabManager.selectTab(index: state.targetIndex)
            return
        }

        let generation = beginVisualTransition(to: state.targetIndex, webView: state.toWebView)
        let now = CACurrentMediaTime()
        let isChainedTransition = (now - lastCommittedTabTransitionAt) < 0.42

        let directionSign: CGFloat = state.direction == .left ? -1 : 1
        let offscreenTravel = width + UI.tabSwitchGap
        let entryStartX = startFromCurrentFrames
            ? state.toWebView.frame.origin.x
            : -directionSign * (offscreenTravel + (emphasizeBirth ? UI.newTabTransitionExtraTravel : 0))
        let fromStartX = startFromCurrentFrames ? state.fromWebView.frame.origin.x : 0
        let fromMidX = directionSign * width * (emphasizeBirth ? (isChainedTransition ? 0.34 : 0.40) : (isChainedTransition ? 0.24 : 0.30))
        let fromFinalX = directionSign * offscreenTravel
        let fromOvershootMagnitude = max(isChainedTransition ? 4 : 8, min(isChainedTransition ? 12 : 18, width * (isChainedTransition ? 0.010 : 0.016)))
        let fromOvershootX = fromFinalX + (directionSign * fromOvershootMagnitude)
        let toMidX = -directionSign * width * (emphasizeBirth ? (isChainedTransition ? 0.10 : 0.14) : (isChainedTransition ? 0.08 : 0.11))
        let toOvershootMagnitude = max(isChainedTransition ? 4 : 8, min(isChainedTransition ? 10 : 16, width * (isChainedTransition ? 0.009 : 0.014)))
        let toOvershootX = directionSign * toOvershootMagnitude

        state.fromWebView.frame.origin.x = pixelAligned(fromStartX)
        state.toWebView.frame.origin.x = pixelAligned(entryStartX)

        let dimView = NSView(frame: webContainer.bounds)
        dimView.wantsLayer = true
        let dimAlpha: CGFloat = emphasizeBirth
            ? (isChainedTransition ? 0.14 : 0.2)
            : (isChainedTransition ? 0.10 : 0.16)
        dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(dimAlpha).cgColor
        dimView.alphaValue = 0
        webContainer.addSubview(dimView, positioned: .above, relativeTo: state.fromWebView)

        let gapView = makeTransitionGapView(height: webContainer.bounds.height)
        webContainer.addSubview(gapView, positioned: .above, relativeTo: dimView)

        func gapOriginX(fromX: CGFloat, toX: CGFloat) -> CGFloat {
            let fromLeading = min(fromX, toX)
            let fromTrailing = max(fromX, toX)
            return pixelAligned((((fromLeading + width) + fromTrailing) * 0.5) - (UI.newTabTransitionGapWidth * 0.5))
        }

        gapView.frame = CGRect(
            x: gapOriginX(fromX: fromStartX, toX: entryStartX),
            y: 0,
            width: UI.newTabTransitionGapWidth,
            height: webContainer.bounds.height
        )

        state.fromWebView.wantsLayer = true
        state.toWebView.wantsLayer = true
        state.fromWebView.layer?.removeAllAnimations()
        state.toWebView.layer?.removeAllAnimations()
        state.fromWebView.layer?.masksToBounds = true
        state.toWebView.layer?.masksToBounds = true
        state.fromWebView.layer?.cornerRadius = 18
        state.toWebView.layer?.cornerRadius = 18
        state.fromWebView.layer?.borderWidth = 0
        state.toWebView.layer?.borderWidth = 1.2
        state.toWebView.layer?.borderColor = NSColor.white.withAlphaComponent(0.26).cgColor
        state.toWebView.layer?.shadowOpacity = 0.22
        state.toWebView.layer?.shadowRadius = 18
        state.toWebView.layer?.shadowOffset = CGSize(width: 0, height: 0)
        state.toWebView.alphaValue = 0.9
        state.toWebView.layer?.transform = CATransform3DIdentity

        NSAnimationContext.runAnimationGroup { context in
            context.duration = emphasizeBirth
                ? (isChainedTransition ? 0.10 : 0.14)
                : (isChainedTransition ? 0.09 : 0.12)
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            dimView.animator().alphaValue = 1.0
            state.fromWebView.animator().frame.origin.x = pixelAligned(fromMidX)
            state.fromWebView.animator().alphaValue = isChainedTransition ? 0.82 : 0.76
            state.toWebView.animator().frame.origin.x = pixelAligned(toMidX)
            state.toWebView.animator().alphaValue = 1.0
            gapView.animator().frame.origin.x = gapOriginX(fromX: fromMidX, toX: toMidX)
        } completionHandler: { [weak self] in
            guard let self else { return }
            guard generation == self.tabTransitionGeneration else {
                self.cleanupTransitionDecoration(for: state, dimView: dimView, gapView: gapView)
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = emphasizeBirth
                    ? (isChainedTransition ? 0.12 : 0.18)
                    : (isChainedTransition ? 0.11 : 0.16)
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                state.fromWebView.animator().frame.origin.x = self.pixelAligned(fromOvershootX)
                state.fromWebView.animator().alphaValue = isChainedTransition ? 0.72 : 0.62
                state.toWebView.animator().frame.origin.x = self.pixelAligned(toOvershootX)
                state.toWebView.animator().layer?.shadowOpacity = isChainedTransition ? 0.24 : 0.32
                gapView.animator().frame.origin.x = gapOriginX(fromX: fromOvershootX, toX: toOvershootX)
            } completionHandler: {
                guard generation == self.tabTransitionGeneration else {
                    self.cleanupTransitionDecoration(for: state, dimView: dimView, gapView: gapView)
                    return
                }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = emphasizeBirth
                        ? (isChainedTransition ? 0.10 : 0.13)
                        : (isChainedTransition ? 0.09 : 0.12)
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    dimView.animator().alphaValue = 0
                    state.fromWebView.animator().frame.origin.x = self.pixelAligned(fromFinalX)
                    state.fromWebView.animator().alphaValue = 1.0
                    state.toWebView.animator().frame.origin.x = 0
                    state.toWebView.animator().layer?.shadowOpacity = 0.12
                    gapView.animator().frame.origin.x = gapOriginX(fromX: fromFinalX, toX: 0)
                    gapView.animator().alphaValue = 0.16
                } completionHandler: {
                    guard generation == self.tabTransitionGeneration else {
                        self.cleanupTransitionDecoration(for: state, dimView: dimView, gapView: gapView)
                        return
                    }
                    self.lastCommittedTabTransitionAt = CACurrentMediaTime()
                    self.clearVisualTransitionOverride()
                    self.cleanupTransitionDecoration(for: state, dimView: dimView, gapView: gapView)
                    self.tabManager.selectTab(index: state.targetIndex)
                }
            }
        }
    }

    private func resolvedVisualCurrentIndex() -> Int {
        visualTransitionCurrentIndex ?? tabManager.currentIndex
    }

    private func resolvedVisualCurrentWebView() -> WKWebView? {
        visualTransitionCurrentWebView ?? tabManager.currentWebView
    }

    @discardableResult
    private func beginVisualTransition(to index: Int, webView: WKWebView) -> Int {
        tabTransitionGeneration += 1
        visualTransitionCurrentIndex = index
        visualTransitionCurrentWebView = webView
        return tabTransitionGeneration
    }

    private func clearVisualTransitionOverride() {
        visualTransitionCurrentIndex = nil
        visualTransitionCurrentWebView = nil
    }

    private func cleanupTransitionDecoration(
        for state: InteractiveTabSwitchState,
        dimView: NSView,
        gapView: NSView
    ) {
        dimView.removeFromSuperview()
        gapView.removeFromSuperview()
        state.fromWebView.layer?.cornerRadius = 0
        state.fromWebView.layer?.borderWidth = 0
        state.fromWebView.layer?.shadowOpacity = 0
        state.toWebView.layer?.cornerRadius = 0
        state.toWebView.layer?.borderWidth = 0
        state.toWebView.layer?.shadowOpacity = 0
    }

    private func captureThumbnail(for webView: WKWebView) {
        guard webView.bounds.width > 1, webView.bounds.height > 1 else { return }

        let width = min(webView.bounds.width, 320)
        let height = min(webView.bounds.height, 160)
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: width, height: height)

        webView.takeSnapshot(with: config) { [weak self, weak webView] image, _ in
            guard let self, let webView else { return }
            self.tabManager.updateThumbnail(for: webView, image: image)
        }
    }

    private func rebuildTabStrip() {
        syncGroupSelectorSelection()
        tabStripStackView.arrangedSubviews.forEach {
            tabStripStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let visibleItems: [TabStripItem]
        if tabSearchQuery.isEmpty {
            visibleItems = tabManager.tabStripItems
        } else {
            visibleItems = tabManager.tabStripItems.filter { item in
                item.title.localizedCaseInsensitiveContains(tabSearchQuery)
            }
        }

        for item in visibleItems {
            let chip = TabChipView(
                index: item.index,
                title: item.title,
                thumbnail: item.thumbnail,
                size: UI.tabChipSize,
                isActive: item.isActive,
                isProtected: item.isProtected,
                isBookmarked: item.isBookmarked,
                activeAccentColor: accentColorForCurrentGroup()
            )
            tabStripStackView.addArrangedSubview(chip)
        }

        layoutTabStripAndRevealActive()
    }

    private func confirmCloseProtectedTab() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "保護タブを閉じますか？"
        alert.informativeText = "このタブは保護されています。閉じるには確認が必要です。"
        alert.addButton(withTitle: "閉じる")
        alert.addButton(withTitle: "キャンセル")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func syncToolbarLayout() {
        guard let window, let contentView = window.contentView else { return }

        let trafficButtons: [NSButton] = [.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }

        let minButtonX = trafficButtons.compactMap { button -> CGFloat? in
            guard let superview = button.superview else { return nil }
            let rect = contentView.convert(button.frame, from: superview)
            return rect.minX
        }.min() ?? 12
        let maxButtonX = trafficButtons.compactMap { button -> CGFloat? in
            guard let superview = button.superview else { return nil }
            let rect = contentView.convert(button.frame, from: superview)
            return rect.maxX
        }.max() ?? 74
        leftButtonRowLeadingConstraint?.constant = max(10, minButtonX - 1)
        // Keep the row consistently below window controls; avoid overlap jitter.
        leftButtonRowTopConstraint?.constant = UI.navButtonRowTop

        let rightPanelWidth = min(300, max(220, window.frame.width * 0.24))
        rightPanelWidthConstraint?.constant = rightPanelWidth

        let reservedRight = rightPanelWidth + 10 + 20 + 8 + 12
        let leftReserved = maxButtonX + 168
        let available = window.frame.width - leftReserved - reservedRight
        tabStripWidthConstraint?.constant = min(640, max(220, available))
        layoutTabStripAndRevealActive()
    }

    private func syncGroupSelectorSelection() {
        let accent = accentColorForCurrentGroup()
        groupSelectorButton.contentTintColor = accent.withAlphaComponent(0.96)
        groupSelectorButton.toolTip = tabManager.currentGroup.displayName
    }

    private func refreshNavigationButtons() {
        backButton.isEnabled = tabManager.canCurrentTabGoBack
        forwardButton.isEnabled = tabManager.canCurrentTabGoForward

        let bookmarkSymbol = tabManager.isCurrentTabBookmarked ? "star.fill" : "star"
        bookmarkButton.image = NSImage(systemSymbolName: bookmarkSymbol, accessibilityDescription: nil)
    }

    private func accentColorForCurrentGroup() -> NSColor {
        switch tabManager.currentGroup {
        case .regular:
            return NSColor.systemBlue
        case .privateMode:
            return NSColor.systemPurple
        case .work:
            return NSColor.systemGreen
        case .research:
            return NSColor.systemPink
        }
    }

    private func layoutTabStripAndRevealActive() {
        guard let clipView = tabStripScrollView.contentView as NSClipView? else { return }

        tabStripStackView.layoutSubtreeIfNeeded()

        let contentHeight = max(tabStripContainer.bounds.height, UI.tabChipSize.height)
        let chipWidth = tabStripStackView.fittingSize.width
        let viewportWidth = tabStripContainer.bounds.width
        let documentWidth = max(chipWidth, viewportWidth)
        let centeredX = chipWidth < viewportWidth ? (viewportWidth - chipWidth) * 0.5 : 0
        tabStripDocumentView.frame = CGRect(x: 0, y: 0, width: documentWidth, height: contentHeight)
        tabStripStackView.frame = CGRect(x: centeredX, y: 0, width: chipWidth, height: contentHeight)

        if chipWidth > viewportWidth,
           let activeChip = tabStripStackView.arrangedSubviews.first(where: {
            ($0 as? TabChipView)?.isActiveChip == true
        }) {
            var target = activeChip.frame.insetBy(dx: -16, dy: 0)
            target.origin.y = 0
            target.size.height = contentHeight
            clipView.scrollToVisible(target)
            tabStripScrollView.reflectScrolledClipView(clipView)
        } else {
            clipView.scroll(to: .zero)
            tabStripScrollView.reflectScrolledClipView(clipView)
        }
    }

    private func setupTabStripInteractions() {
        tabInteractionView.onClick = { [weak self] locationInWindow, clickCount in
            guard let self, let index = self.nearestTabIndex(to: locationInWindow) else { return }
            if clickCount == 1, let closeIndex = self.tabIndexForCloseBadge(at: locationInWindow) {
                if self.tabManager.currentIndex != closeIndex {
                    self.tabManager.selectTab(index: closeIndex)
                }
                self.actions.tabClose()
                return
            }
            if clickCount >= 2 {
                self.tabManager.toggleProtection(index: index)
            } else {
                self.tabManager.selectTab(index: index)
            }
        }

        tabInteractionView.onDragBegan = { [weak self] startInWindow in
            guard let self else { return }
            self.dragFromTabIndex = self.nearestTabIndex(to: startInWindow)
            self.dragToTabIndex = self.dragFromTabIndex
            if let source = self.dragFromTabIndex {
                self.tabManager.selectTab(index: source)
                self.beginTabDragPreview(fromIndex: source, startLocationInWindow: startInWindow)
            }
        }

        tabInteractionView.onDragMoved = { [weak self] currentInWindow in
            guard let self, let source = self.dragFromTabIndex else { return }
            self.handleTabDragMoved(fromIndex: source, locationInWindow: currentInWindow)
        }

        tabInteractionView.onDragEnded = { [weak self] endInWindow in
            guard let self, let source = self.dragFromTabIndex else { return }
            self.handleTabDragEnded(fromIndex: source, locationInWindow: endInWindow)
        }

        tabInteractionView.onFileDropURLs = { [weak self] urls in
            guard let self else { return }
            urls.forEach { self.openLocalDocument($0, preferNewTab: true) }
        }
    }

    private func handleTabDragMoved(fromIndex: Int, locationInWindow: NSPoint) {
        guard tabSearchQuery.isEmpty else { return }
        dragFromTabIndex = fromIndex
        let destination = nearestTabIndex(to: locationInWindow) ?? fromIndex
        dragToTabIndex = destination
        updateTabDragPreview(locationInWindow: locationInWindow)
        updateTabReorderGapAnimation(sourceIndex: fromIndex, destinationIndex: destination)
    }

    private func handleTabDragEnded(fromIndex: Int, locationInWindow: NSPoint) {
        defer {
            clearTabReorderGapAnimation()
            endTabDragPreview()
        }
        guard tabSearchQuery.isEmpty else {
            dragFromTabIndex = nil
            dragToTabIndex = nil
            return
        }

        let source = dragFromTabIndex ?? fromIndex
        let destination = dragToTabIndex ?? nearestTabIndex(to: locationInWindow) ?? source
        dragFromTabIndex = nil
        dragToTabIndex = nil

        guard source != destination else { return }
        tabManager.moveTab(from: source, to: destination)
    }

    private func beginTabDragPreview(fromIndex: Int, startLocationInWindow: NSPoint) {
        endTabDragPreview()
        guard let chip = tabChipView(for: fromIndex) else { return }
        guard let image = snapshotImage(for: chip) else { return }

        let chipRectInContainer = chip.convert(chip.bounds, to: tabStripContainer)
        let startInContainer = tabStripContainer.convert(startLocationInWindow, from: nil)
        dragPreviewOffsetX = startInContainer.x - chipRectInContainer.origin.x

        let preview = NSImageView(frame: chipRectInContainer)
        preview.image = image
        preview.imageScaling = .scaleAxesIndependently
        preview.wantsLayer = true
        preview.layer?.cornerRadius = chip.layer?.cornerRadius ?? 2
        preview.layer?.masksToBounds = true
        preview.alphaValue = 0.92
        tabStripContainer.addSubview(preview)
        dragPreviewView = preview
        dragSourceChipView = chip
        chip.alphaValue = 0.28
        updateTabDragPreview(locationInWindow: startLocationInWindow)
    }

    private func updateTabDragPreview(locationInWindow: NSPoint) {
        guard let preview = dragPreviewView else { return }
        let point = tabStripContainer.convert(locationInWindow, from: nil)
        var targetX = point.x - dragPreviewOffsetX
        let minX: CGFloat = 0
        let maxX = max(0, tabStripContainer.bounds.width - preview.frame.width)
        targetX = min(maxX, max(minX, targetX))
        preview.frame.origin.x = targetX
    }

    private func endTabDragPreview() {
        dragPreviewView?.removeFromSuperview()
        dragPreviewView = nil
        dragPreviewOffsetX = 0
        dragSourceChipView?.alphaValue = 1.0
        dragSourceChipView = nil
    }

    private func updateTabReorderGapAnimation(sourceIndex: Int, destinationIndex: Int) {
        let chips = tabStripStackView.arrangedSubviews.compactMap { $0 as? TabChipView }
        let shift = UI.tabChipSize.width + tabStripStackView.spacing

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.11
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)

            for chip in chips {
                guard chip.tabIndex != sourceIndex else {
                    chip.animator().layer?.transform = CATransform3DIdentity
                    continue
                }

                let dx: CGFloat
                if destinationIndex > sourceIndex {
                    if chip.tabIndex > sourceIndex && chip.tabIndex <= destinationIndex {
                        dx = -shift
                    } else {
                        dx = 0
                    }
                } else if destinationIndex < sourceIndex {
                    if chip.tabIndex >= destinationIndex && chip.tabIndex < sourceIndex {
                        dx = shift
                    } else {
                        dx = 0
                    }
                } else {
                    dx = 0
                }
                chip.animator().layer?.transform = CATransform3DMakeTranslation(dx, 0, 0)
            }
        }
    }

    private func clearTabReorderGapAnimation() {
        let chips = tabStripStackView.arrangedSubviews.compactMap { $0 as? TabChipView }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for chip in chips {
                chip.animator().layer?.transform = CATransform3DIdentity
            }
        }
    }

    private func tabChipView(for index: Int) -> TabChipView? {
        tabStripStackView.arrangedSubviews
            .compactMap { $0 as? TabChipView }
            .first { $0.tabIndex == index }
    }

    private func tabIndexForCloseBadge(at locationInWindow: NSPoint) -> Int? {
        let chips = tabStripStackView.arrangedSubviews.compactMap { $0 as? TabChipView }
        for chip in chips {
            if chip.containsCloseBadge(at: locationInWindow) {
                return chip.tabIndex
            }
        }
        return nil
    }

    private func snapshotImage(for view: NSView) -> NSImage? {
        guard view.bounds.width > 1, view.bounds.height > 1 else { return nil }
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) ?? NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width),
            pixelsHigh: Int(view.bounds.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private func nearestTabIndex(to locationInWindow: NSPoint) -> Int? {
        let pointInStack = tabStripStackView.convert(locationInWindow, from: nil)
        let chips = tabStripStackView.arrangedSubviews.compactMap { $0 as? TabChipView }
        guard !chips.isEmpty else { return nil }

        var nearest = chips[0]
        var nearestDistance = abs(pointInStack.x - nearest.frame.midX)
        for chip in chips.dropFirst() {
            let distance = abs(pointInStack.x - chip.frame.midX)
            if distance < nearestDistance {
                nearest = chip
                nearestDistance = distance
            }
        }
        return nearest.tabIndex
    }
}

extension MainWindowController: NSTextFieldDelegate, NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field == tabSearchField {
            tabSearchQuery = tabSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            rebuildTabStrip()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control == addressBarEditorField, commandSelector == #selector(insertNewline(_:)) {
            submitAddressFieldIfNeeded()
            return true
        }

        if control == addressBarEditorField, commandSelector == #selector(cancelOperation(_:)) {
            endAddressEditingWithoutSubmit()
            return true
        }

        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field == addressBarEditorField else { return }
        guard isAddressEditing else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isAddressEditing else { return }
            if let editor = self.addressBarEditorField.currentEditor(),
               self.window?.firstResponder === editor {
                return
            }
            self.endAddressEditingWithoutSubmit()
        }
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        syncToolbarLayout()
        refreshFullScreenToolbarBehavior(animated: false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        syncToolbarLayout()
        refreshFullScreenToolbarBehavior(animated: false)
    }

    func windowDidResignKey(_ notification: Notification) {
        endAddressEditingWithoutSubmit()
        invalidateFullScreenToolbarHideTimer()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        refreshFullScreenToolbarBehavior(animated: true)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        refreshFullScreenToolbarBehavior(animated: false)
    }
}

extension MainWindowController: TabManagerDelegate {
    func tabManager(_ manager: TabManager, didSelect webView: WKWebView?) {
        clearVisualTransitionOverride()
        guard let webView else {
            webContainer.subviews.forEach { $0.removeFromSuperview() }
            overlayView = nil
            interactiveTabSwitchState = nil
            applyAddressDisplayMode(display: "")
            rebuildTabStrip()
            refreshNavigationButtons()
            return
        }

        interactiveTabSwitchState = nil
        attachWebView(webView)
    }

    func tabManager(_ manager: TabManager, didUpdateTabs count: Int) {
        rebuildTabStrip()
        refreshNavigationButtons()
    }
}

extension MainWindowController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            if let url = navigationAction.request.url {
                downloadSourceURLs[ObjectIdentifier(webView)] = url
            }
            decisionHandler(.download)
            return
        }

        guard navigationAction.targetFrame?.isMainFrame ?? true else {
            decisionHandler(.allow)
            return
        }

        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if BrowserPreferences.shared.harmfulSiteWarningEnabled,
           let host = url.host?.lowercased(),
           !temporarilyAllowedHosts.contains(host),
           !BrowserPreferences.shared.isHarmfulSiteAllowed(for: host),
           let warning = HarmfulSiteGuard.warning(for: url) {
            decisionHandler(.cancel)
            presentHarmfulSiteWarning(
                warning: warning,
                url: url,
                host: host,
                webView: webView,
                originalRequest: navigationAction.request
            )
            return
        }

        guard BrowserPreferences.shared.antiTrackingEnabled else {
            decisionHandler(.allow)
            return
        }

        guard (navigationAction.request.httpMethod ?? "GET").uppercased() == "GET",
              let sanitized = sanitizedURLByRemovingTrackingParams(from: url),
              sanitized != url else {
            decisionHandler(.allow)
            return
        }

        decisionHandler(.cancel)
        webView.load(URLRequest(url: sanitized))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if !navigationResponse.canShowMIMEType {
            if let url = navigationResponse.response.url {
                downloadSourceURLs[ObjectIdentifier(webView)] = url
            }
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        if let url = navigationAction.request.url {
            downloadSourceURLs[ObjectIdentifier(download)] = url
        }
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        if let url = navigationResponse.response.url {
            downloadSourceURLs[ObjectIdentifier(download)] = url
        }
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tabManager.updateMetadata(for: webView)
        captureThumbnail(for: webView)
        if let url = webView.url {
            let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let group = tabManager.group(for: webView) ?? tabManager.currentGroup
            if group != .privateMode, isSafeStoredURL(url) {
                BrowsingHistoryStore.shared.recordVisit(url: url, title: title)
            }
            if tabManager.isCurrentTabBookmarked, tabManager.currentWebView === webView {
                BookmarkStore.shared.addOrUpdate(url: url, title: title)
            }
        }

        if tabManager.currentWebView === webView, !isAddressEditing {
            applyAddressDisplayMode(display: webView.url?.absoluteString ?? "")
            rebuildTabStrip()
        }
        refreshNavigationButtons()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        presentErrorPageIfNeeded(for: webView, error: error)
        refreshNavigationButtons()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        presentErrorPageIfNeeded(for: webView, error: error)
        refreshNavigationButtons()
    }

    private func sanitizedURLByRemovingTrackingParams(from url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty else {
            return nil
        }
        let filtered = items.filter { !trackingQueryKeys.contains($0.name.lowercased()) }
        guard filtered.count != items.count else { return nil }
        components.queryItems = filtered.isEmpty ? nil : filtered
        return components.url
    }

    private func presentHarmfulSiteWarning(
        warning: HarmfulSiteWarning,
        url: URL,
        host: String,
        webView: WKWebView,
        originalRequest: URLRequest
    ) {
        let show = {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = warning.title
            alert.informativeText = warning.message
            alert.addButton(withTitle: "戻る")
            alert.addButton(withTitle: "続行")
            alert.addButton(withTitle: "このサイトを今後許可")

            let proceed: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard let self else { return }
                guard response == .alertSecondButtonReturn || response == .alertThirdButtonReturn else { return }
                if response == .alertThirdButtonReturn {
                    BrowserPreferences.shared.setHarmfulSiteAllowed(true, for: host)
                }
                self.temporarilyAllowedHosts.insert(host)
                var request = originalRequest
                request.url = url
                webView.load(request)
            }

            if let window = self.window {
                alert.beginSheetModal(for: window, completionHandler: proceed)
            } else {
                let response = alert.runModal()
                proceed(response)
            }
        }

        if Thread.isMainThread {
            show()
        } else {
            DispatchQueue.main.async(execute: show)
        }
    }

    private func presentAlert(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let modalWindow = window ?? NSApp.keyWindow {
            alert.beginSheetModal(for: modalWindow, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func presentTransientAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        presentAlert(alert) { _ in }
    }

    private func presentErrorPageIfNeeded(for webView: WKWebView, error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }

        let failingURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString
            ?? webView.url?.absoluteString
            ?? "about:blank"
        let title = htmlEscaped("This page could not be loaded")
        let message = htmlEscaped(error.localizedDescription)
        let urlString = htmlEscaped(failingURL)
        let html = """
        <!doctype html>
        <html lang="en">
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Error</title>
        <style>
        :root { color-scheme: light dark; }
        body {
          margin: 0;
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
          background: #eef1f5;
          color: #1b2128;
          display: grid;
          place-items: center;
          min-height: 100vh;
        }
        .card {
          width: min(560px, calc(100vw - 48px));
          border-radius: 22px;
          padding: 28px;
          background: rgba(255,255,255,0.9);
          box-shadow: 0 20px 60px rgba(28,35,44,0.14);
        }
        h1 { font-size: 24px; margin: 0 0 10px; }
        p { margin: 0 0 12px; line-height: 1.6; }
        code {
          display: block;
          margin-top: 14px;
          padding: 12px 14px;
          border-radius: 12px;
          background: rgba(25,30,38,0.08);
          word-break: break-all;
        }
        </style>
        <body>
          <div class="card">
            <h1>\(title)</h1>
            <p>\(message)</p>
            <code>\(urlString)</code>
          </div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func isSafeStoredURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "file" || scheme == "about"
    }

    private func shouldAllowPopup(for navigationAction: WKNavigationAction, opener: WKWebView) -> Bool {
        guard let url = navigationAction.request.url, isSafeStoredURL(url) else {
            return false
        }

        guard BrowserPreferences.shared.popupBlockingEnabled else {
            return true
        }

        switch navigationAction.navigationType {
        case .linkActivated, .formSubmitted, .formResubmitted:
            return true
        case .backForward, .reload:
            return false
        case .other:
            break
        @unknown default:
            break
        }

        let sourceURL = navigationAction.request.mainDocumentURL ?? opener.url
        let sourceHost = sourceURL?.host?.lowercased()
        let targetHost = url.host?.lowercased()

        if url.scheme?.lowercased() == "about", url.absoluteString == "about:blank" {
            return true
        }

        if let sourceHost, let targetHost, sourceHost == targetHost {
            return true
        }

        return false
    }

    @available(macOS 12.0, *)
    private func requestMediaPermission(originHost: String, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let kind: MediaPermissionKind
        switch type {
        case .camera:
            kind = .camera
        case .microphone:
            kind = .microphone
        case .cameraAndMicrophone:
            kind = .cameraAndMicrophone
        @unknown default:
            decisionHandler(.deny)
            return
        }

        if let saved = MediaPermissionStore.shared.decision(for: originHost, kind: kind) {
            decisionHandler(saved == .allow ? .grant : .deny)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "サイト権限の確認"

        switch type {
        case .camera:
            alert.informativeText = "\(originHost) がカメラへのアクセスを要求しています。"
        case .microphone:
            alert.informativeText = "\(originHost) がマイクへのアクセスを要求しています。"
        case .cameraAndMicrophone:
            alert.informativeText = "\(originHost) がカメラとマイクへのアクセスを要求しています。"
        @unknown default:
            alert.informativeText = "\(originHost) がメディアデバイスへのアクセスを要求しています。"
        }

        alert.addButton(withTitle: "許可")
        alert.addButton(withTitle: "拒否")

        presentAlert(alert) { response in
            guard response == .alertFirstButtonReturn else {
                MediaPermissionStore.shared.setDecision(.deny, for: originHost, kind: kind)
                decisionHandler(.deny)
                return
            }

            let group = DispatchGroup()
            var allowed = true

            func requestAVPermission(_ mediaType: AVMediaType) {
                group.enter()
                AVCaptureDevice.requestAccess(for: mediaType) { granted in
                    if !granted {
                        allowed = false
                    }
                    group.leave()
                }
            }

            switch type {
            case .camera:
                requestAVPermission(.video)
            case .microphone:
                requestAVPermission(.audio)
            case .cameraAndMicrophone:
                requestAVPermission(.video)
                requestAVPermission(.audio)
            @unknown default:
                allowed = false
            }

            group.notify(queue: .main) {
                MediaPermissionStore.shared.setDecision(allowed ? .allow : .deny, for: originHost, kind: kind)
                decisionHandler(allowed ? .grant : .deny)
            }
        }
    }

    private var isWindowFullScreen: Bool {
        window?.styleMask.contains(.fullScreen) == true
    }

    private func installFullScreenMouseMonitorIfNeeded() {
        guard fullScreenMouseMonitor == nil else { return }
        fullScreenMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in
            self?.handleFullScreenPointerEvent(event)
            return event
        }
        window?.acceptsMouseMovedEvents = true
    }

    private func uninstallFullScreenMouseMonitor() {
        if let fullScreenMouseMonitor {
            NSEvent.removeMonitor(fullScreenMouseMonitor)
            self.fullScreenMouseMonitor = nil
        }
        window?.acceptsMouseMovedEvents = false
    }

    private func invalidateFullScreenToolbarHideTimer() {
        fullScreenHideTimer?.invalidate()
        fullScreenHideTimer = nil
    }

    private func handleFullScreenPointerEvent(_ event: NSEvent) {
        guard isWindowFullScreen, let contentView = window?.contentView else { return }
        let location = contentView.convert(event.locationInWindow, from: nil)
        let maxY = contentView.bounds.maxY
        let revealThreshold = maxY - UI.fullScreenRevealHotzoneHeight

        if location.y >= revealThreshold {
            setFullScreenToolbarHidden(false, animated: true)
            scheduleFullScreenToolbarHide()
            return
        }

        if isAddressEditing {
            invalidateFullScreenToolbarHideTimer()
            return
        }

        scheduleFullScreenToolbarHide()
    }

    private func scheduleFullScreenToolbarHide() {
        guard isWindowFullScreen else { return }
        invalidateFullScreenToolbarHideTimer()
        fullScreenHideTimer = Timer.scheduledTimer(withTimeInterval: UI.fullScreenHideDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.isAddressEditing {
                self.scheduleFullScreenToolbarHide()
                return
            }
            self.setFullScreenToolbarHidden(true, animated: true)
        }
    }

    private func refreshFullScreenToolbarBehavior(animated: Bool) {
        if isWindowFullScreen {
            installFullScreenMouseMonitorIfNeeded()
            setFullScreenToolbarHidden(true, animated: animated)
        } else {
            invalidateFullScreenToolbarHideTimer()
            uninstallFullScreenMouseMonitor()
            setFullScreenToolbarHidden(false, animated: animated)
        }
    }

    private func setFullScreenToolbarHidden(_ hidden: Bool, animated: Bool) {
        guard let toolbarTopConstraint else { return }
        let targetConstant: CGFloat = hidden ? -UI.toolbarHeight : 0
        guard toolbarTopConstraint.constant != targetConstant || isFullScreenToolbarHidden != hidden else { return }

        isFullScreenToolbarHidden = hidden
        toolbarTopConstraint.constant = targetConstant

        let applyLayout = {
            self.toolbarContainer.alphaValue = hidden ? 0.02 : 1.0
            self.rootContainer.layoutSubtreeIfNeeded()
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = hidden ? 0.18 : 0.16
                context.timingFunction = CAMediaTimingFunction(name: hidden ? .easeIn : .easeOut)
                self.toolbarContainer.animator().alphaValue = hidden ? 0.02 : 1.0
                self.rootContainer.animator().layoutSubtreeIfNeeded()
            }
        } else {
            applyLayout()
        }
    }
}

extension MainWindowController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        _ = windowFeatures

        if navigationAction.targetFrame == nil {
            guard shouldAllowPopup(for: navigationAction, opener: webView) else {
                return nil
            }

            let popupWebView = WKWebView(frame: .zero, configuration: configuration)
            popupWebView.translatesAutoresizingMaskIntoConstraints = false
            popupWebView.allowsBackForwardNavigationGestures = false
            popupWebView.navigationDelegate = self
            popupWebView.uiDelegate = self

            let initialURL = navigationAction.request.url
            let targetGroup = tabManager.group(for: webView) ?? tabManager.currentGroup
            return tabManager.addTab(
                webView: popupWebView,
                initialURL: initialURL,
                shouldLoadInitialURL: false,
                group: targetGroup,
                activate: true
            )
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = frame.securityOrigin.host
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        presentAlert(alert) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = frame.securityOrigin.host
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        presentAlert(alert) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = frame.securityOrigin.host
        alert.informativeText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        presentAlert(alert) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        _ = frame
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard let modalWindow = window ?? NSApp.keyWindow else {
            completionHandler(nil)
            return
        }
        panel.beginSheetModal(for: modalWindow) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    @available(macOS 12.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        _ = frame
        requestMediaPermission(originHost: origin.host, type: type, decisionHandler: decisionHandler)
    }
}

extension MainWindowController: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        _ = response
        if let preferredDirectory = BrowserPreferences.shared.preferredDownloadDirectoryURL() {
            let startedAccess = preferredDirectory.startAccessingSecurityScopedResource()
            let destinationURL = availableDestinationURL(in: preferredDirectory, suggestedFilename: suggestedFilename)
            downloadDestinationURLs[ObjectIdentifier(download)] = destinationURL
            if startedAccess {
                downloadSecurityScopedAccess[ObjectIdentifier(download)] = preferredDirectory
            }
            completionHandler(destinationURL)
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename
        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloadsURL
        }
        guard let modalWindow = window ?? NSApp.keyWindow else {
            completionHandler(nil)
            return
        }
        panel.beginSheetModal(for: modalWindow) { [weak self] responseResult in
            if responseResult == .OK, let destinationURL = panel.url {
                self?.downloadDestinationURLs[ObjectIdentifier(download)] = destinationURL
                completionHandler(destinationURL)
            } else {
                completionHandler(nil)
            }
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        let sourceURL = downloadSourceURLs.removeValue(forKey: ObjectIdentifier(download))
        if let accessURL = downloadSecurityScopedAccess.removeValue(forKey: ObjectIdentifier(download)) {
            accessURL.stopAccessingSecurityScopedResource()
        }
        guard let destinationURL = downloadDestinationURLs.removeValue(forKey: ObjectIdentifier(download)) else {
            return
        }
        DownloadStore.shared.add(sourceURL: sourceURL, destinationURL: destinationURL)
        presentTransientAlert(title: "ダウンロード完了", message: destinationURL.lastPathComponent, style: .informational)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        _ = resumeData
        downloadSourceURLs.removeValue(forKey: ObjectIdentifier(download))
        downloadDestinationURLs.removeValue(forKey: ObjectIdentifier(download))
        if let accessURL = downloadSecurityScopedAccess.removeValue(forKey: ObjectIdentifier(download)) {
            accessURL.stopAccessingSecurityScopedResource()
        }
        presentTransientAlert(title: "ダウンロード失敗", message: error.localizedDescription, style: .warning)
    }

    private func availableDestinationURL(in directory: URL, suggestedFilename: String) -> URL {
        let fileManager = FileManager.default
        let sanitizedName = suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = sanitizedName.isEmpty ? "Download" : sanitizedName
        let ext = URL(fileURLWithPath: baseName).pathExtension
        let stem = ext.isEmpty ? baseName : (baseName as NSString).deletingPathExtension

        var candidate = directory.appendingPathComponent(baseName)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let numberedName = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            candidate = directory.appendingPathComponent(numberedName)
            counter += 1
        }
        return candidate
    }
}

extension MainWindowController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }

        if message.name == Self.longPressLinkMessageName {
            guard let href = body["href"] as? String else { return }
            guard let url = URL(string: href) else { return }
            guard isSafeStoredURL(url) else { return }
            let group = message.webView.flatMap { tabManager.group(for: $0) } ?? tabManager.currentGroup
            tabManager.openBackgroundTab(url: url, in: group)
            return
        }

        if message.name == Self.selectionSearchMessageName {
            guard let query = body["query"] as? String else { return }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            actions.openLocationInput(trimmed)
        }
    }
}

private final class LiquidGlassToolbarView: NSView {
    let contentLayoutView = NonDraggableView()
    private var backgroundView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    override func layout() {
        super.layout()
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        contentLayoutView.translatesAutoresizingMaskIntoConstraints = false

        let visualEffectView = NonDraggableVisualEffectView()
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.material = .underWindowBackground
        visualEffectView.state = .followsWindowActiveState
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.isEmphasized = false
        visualEffectView.addSubview(contentLayoutView)
        NSLayoutConstraint.activate([
            contentLayoutView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            contentLayoutView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            contentLayoutView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            contentLayoutView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])
        let backgroundView: NSView = visualEffectView

        self.backgroundView = backgroundView
        addSubview(backgroundView)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

private final class NonDraggableVisualEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { false }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

private final class HorizontalOnlyClipView: NSClipView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        return enclosingScrollView ?? self
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        constrained.origin.y = 0
        return constrained
    }
}

private class NonDraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

private class NonInteractiveView: NonDraggableView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class NonInteractiveStackView: NSStackView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private class NonDraggableScrollView: NSScrollView {
    override var mouseDownCanMoveWindow: Bool { false }
}

private final class TabInteractionView: NonDraggableView {
    var onClick: ((NSPoint, Int) -> Void)?
    var onDragBegan: ((NSPoint) -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?
    var onFileDropURLs: (([URL]) -> Void)?
    private var dragStartInWindow: NSPoint?
    private var dragActive = false
    private var previousWindowMovableState: Bool?
    private var isDropTargetHighlighted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        if let window {
            previousWindowMovableState = window.isMovable
            window.isMovable = false
        }
        if event.clickCount >= 2 {
            dragStartInWindow = nil
            dragActive = false
            onClick?(event.locationInWindow, event.clickCount)
            return
        }
        dragStartInWindow = event.locationInWindow
        dragActive = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartInWindow else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        if !dragActive, hypot(dx, dy) >= 1.0 {
            dragActive = true
            onDragBegan?(start)
        }
        if dragActive {
            onDragMoved?(event.locationInWindow)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let window, let previousWindowMovableState {
            window.isMovable = previousWindowMovableState
        }
        previousWindowMovableState = nil
        guard let start = dragStartInWindow else { return }
        if dragActive {
            onDragEnded?(event.locationInWindow)
        } else {
            onClick?(start, 1)
        }
        dragStartInWindow = nil
        dragActive = false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let urls = acceptedFileURLs(from: sender), !urls.isEmpty else { return [] }
        setDropTargetHighlighted(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        _ = sender
        setDropTargetHighlighted(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        acceptedFileURLs(from: sender)?.isEmpty == false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = acceptedFileURLs(from: sender), !urls.isEmpty else {
            setDropTargetHighlighted(false)
            return false
        }
        setDropTargetHighlighted(false)
        onFileDropURLs?(urls)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        _ = sender
        setDropTargetHighlighted(false)
    }

    private func acceptedFileURLs(from sender: NSDraggingInfo) -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return nil
        }
        return urls.filter(MainWindowController.isBrowserOpenableLocalDocument(_:))
    }

    private func setDropTargetHighlighted(_ highlighted: Bool) {
        guard highlighted != isDropTargetHighlighted else { return }
        isDropTargetHighlighted = highlighted
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = highlighted ? 1 : 0
        layer?.borderColor = NSColor.selectedControlColor.withAlphaComponent(0.45).cgColor
        layer?.backgroundColor = highlighted ? NSColor.selectedControlColor.withAlphaComponent(0.08).cgColor : NSColor.clear.cgColor
    }
}

private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class ClickableLabelField: NSTextField {
    var onActivate: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }
}

private final class TabBirthAnimationView: NSView {
    let plusImageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height)
        let icon = max(10, min(16, side * 0.55))
        plusImageView.frame = CGRect(
            x: (bounds.width - icon) * 0.5,
            y: (bounds.height - icon) * 0.5,
            width: icon,
            height: icon
        )
        layer?.cornerRadius = min(bounds.height * 0.25, 9)
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.20).cgColor
        layer?.borderWidth = 0.8
        layer?.borderColor = NSColor.white.withAlphaComponent(0.36).cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 5
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        layer?.masksToBounds = false

        plusImageView.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        plusImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        plusImageView.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        plusImageView.imageScaling = .scaleProportionallyDown
        plusImageView.alphaValue = 1.0
        addSubview(plusImageView)
    }
}

private final class TabChipView: NSView {
    private enum BadgeKind {
        case none
        case close
        case pin
        case bookmark
    }

    private let index: Int
    private let thumbnailView = PassthroughImageView()
    private let statusBadgeView = NSView()
    private let statusIconView = PassthroughImageView()
    private let activeAccentLayer = CAGradientLayer()
    private let active: Bool
    private let protectedState: Bool
    private let bookmarkedState: Bool
    private let badgeKind: BadgeKind

    var isActiveChip: Bool { active }
    var tabIndex: Int { index }

    init(
        index: Int,
        title: String,
        thumbnail: NSImage?,
        size: NSSize,
        isActive: Bool,
        isProtected: Bool,
        isBookmarked: Bool,
        activeAccentColor: NSColor
    ) {
        self.index = index
        self.active = isActive
        protectedState = isProtected
        bookmarkedState = isBookmarked
        if isProtected {
            badgeKind = .pin
        } else if isBookmarked {
            badgeKind = .bookmark
        } else if isActive {
            badgeKind = .close
        } else {
            badgeKind = .none
        }
        super.init(frame: .zero)
        setupView(
            title: title,
            thumbnail: thumbnail,
            size: size,
            isActive: isActive,
            isProtected: isProtected,
            isBookmarked: isBookmarked,
            activeAccentColor: activeAccentColor
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func containsCloseBadge(at locationInWindow: NSPoint) -> Bool {
        guard badgeKind == .close, !statusBadgeView.isHidden else { return false }
        let localPoint = convert(locationInWindow, from: nil)
        return statusBadgeView.frame.insetBy(dx: -2, dy: -2).contains(localPoint)
    }

    override func layout() {
        super.layout()
        guard active else { return }
        activeAccentLayer.frame = CGRect(x: 2, y: bounds.height - 3, width: bounds.width - 4, height: 2)
    }

    private func setupView(
        title: String,
        thumbnail: NSImage?,
        size: NSSize,
        isActive: Bool,
        isProtected: Bool,
        isBookmarked: Bool,
        activeAccentColor: NSColor
    ) {
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = title
        wantsLayer = true
        layer?.cornerRadius = 2
        layer?.masksToBounds = false
        layer?.borderWidth = 1
        layer?.borderColor = isActive
            ? activeAccentColor.withAlphaComponent(0.90).cgColor
            : NSColor.white.withAlphaComponent(0.56).cgColor
        layer?.backgroundColor = isActive
            ? activeAccentColor.withAlphaComponent(0.24).cgColor
            : NSColor.white.withAlphaComponent(0.30).cgColor
        layer?.shadowColor = activeAccentColor.withAlphaComponent(0.92).cgColor
        layer?.shadowOpacity = isActive ? 0.52 : 0
        layer?.shadowRadius = isActive ? 8 : 0
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.imageScaling = .scaleAxesIndependently
        thumbnailView.image = thumbnail
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 1
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.68).cgColor
        addSubview(thumbnailView)

        statusBadgeView.translatesAutoresizingMaskIntoConstraints = false
        statusBadgeView.wantsLayer = true
        statusBadgeView.layer?.cornerRadius = 7
        statusBadgeView.layer?.masksToBounds = true
        addSubview(statusBadgeView)

        statusIconView.translatesAutoresizingMaskIntoConstraints = false
        statusIconView.imageScaling = .scaleProportionallyUpOrDown
        statusBadgeView.addSubview(statusIconView)

        switch badgeKind {
        case .close:
            let markerImage = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
            statusIconView.image = markerImage?.withSymbolConfiguration(.init(pointSize: 8.5, weight: .bold))
            statusIconView.contentTintColor = NSColor.white.withAlphaComponent(0.96)
            statusBadgeView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
            statusBadgeView.isHidden = false
        case .pin:
            let markerImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
            statusIconView.image = markerImage?.withSymbolConfiguration(.init(pointSize: 8.5, weight: .bold))
            statusIconView.contentTintColor = NSColor.white.withAlphaComponent(0.96)
            statusBadgeView.layer?.backgroundColor = NSColor(calibratedRed: 0.29, green: 0.67, blue: 1.0, alpha: 0.96).cgColor
            statusBadgeView.isHidden = false
        case .bookmark:
            let markerImage = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)
            statusIconView.image = markerImage?.withSymbolConfiguration(.init(pointSize: 8.5, weight: .bold))
            statusIconView.contentTintColor = NSColor.white.withAlphaComponent(0.96)
            statusBadgeView.layer?.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.15, alpha: 0.96).cgColor
            statusBadgeView.isHidden = false
        case .none:
            statusBadgeView.isHidden = true
        }

        if isActive {
            activeAccentLayer.colors = [
                activeAccentColor.withAlphaComponent(0.95).cgColor,
                activeAccentColor.withAlphaComponent(0.65).cgColor
            ]
            activeAccentLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
            activeAccentLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
            layer?.addSublayer(activeAccentLayer)
        }

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size.width),
            heightAnchor.constraint(equalToConstant: size.height),

            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            thumbnailView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            thumbnailView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            statusBadgeView.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            statusBadgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            statusBadgeView.widthAnchor.constraint(equalToConstant: 14),
            statusBadgeView.heightAnchor.constraint(equalToConstant: 14),

            statusIconView.centerXAnchor.constraint(equalTo: statusBadgeView.centerXAnchor),
            statusIconView.centerYAnchor.constraint(equalTo: statusBadgeView.centerYAnchor),
            statusIconView.widthAnchor.constraint(equalToConstant: 8.5),
            statusIconView.heightAnchor.constraint(equalToConstant: 8.5)
        ])

        if isActive {
            activeAccentLayer.cornerRadius = 1
        }

        if protectedState {
            let protectedOrange = NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.06, alpha: 1.0)
            layer?.borderColor = protectedOrange.withAlphaComponent(isActive ? 0.95 : 0.82).cgColor
            layer?.shadowColor = protectedOrange.withAlphaComponent(isActive ? 0.98 : 0.88).cgColor
            layer?.shadowOpacity = isActive ? 0.62 : 0.36
            layer?.shadowRadius = isActive ? 9 : 5
        } else if bookmarkedState {
            let bookmarkYellow = NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.16, alpha: 1.0)
            layer?.borderColor = bookmarkYellow.withAlphaComponent(isActive ? 0.90 : 0.78).cgColor
        }
    }
}
