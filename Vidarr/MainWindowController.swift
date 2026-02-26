import Cocoa
import WebKit

final class MainWindowController: NSWindowController {
    private enum UI {
        static let toolbarHeight: CGFloat = 54
        static let tabChipSize = NSSize(width: 96, height: 48)
        static let tabSwitchGap: CGFloat = 16
    }

    private let rootContainer = NonDraggableView()
    private let toolbarContainer = LiquidGlassToolbarView()
    private let webContainer = NonDraggableView()

    private let tabStripContainer = NonDraggableView()
    private let tabStripScrollView = NonDraggableScrollView()
    private let tabInteractionView = TabInteractionView()
    private let tabStripDocumentView = NonInteractiveView()
    private let tabStripStackView = NonInteractiveStackView()
    private let groupSelectorButton = NSButton(title: "", target: nil, action: nil)
    private let newTabButton = NSButton(title: "+", target: nil, action: nil)
    private let rightPanelView = NonDraggableView()
    private let addressBarField = AddressBarField()
    private let tabSearchField = NSSearchField()

    private var tabStripMinLeadingConstraint: NSLayoutConstraint?
    private var tabStripWidthConstraint: NSLayoutConstraint?
    private var rightPanelWidthConstraint: NSLayoutConstraint?

    private let tabManager: TabManager
    private let session: BrowserSession
    private let actions: ActionCenter

    private var overlayView: GestureOverlayView?
    private var isAddressEditing = false
    private var tabSearchQuery = ""
    private var currentAddressURLString = ""
    private var interactiveTabSwitchState: InteractiveTabSwitchState?
    private var dragFromTabIndex: Int?
    private var dragToTabIndex: Int?
    private var preferenceObserver: NSObjectProtocol?
    private var lastEphemeralMode = BrowserPreferences.shared.ephemeralModeEnabled
    private var lastDoNotTrack = BrowserPreferences.shared.sendDoNotTrack
    private var lastContentBlockingEnabled = BrowserPreferences.shared.contentBlockingEnabled
    private var temporarilyAllowedHosts: Set<String> = []
    private let trackingQueryKeys: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "gclid", "dclid", "fbclid", "msclkid", "yclid", "mc_cid", "mc_eid", "igshid", "rb_clickid"
    ]

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
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self

        configureWindow()
        configureBindings()
        configurePreferenceObserver()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let preferenceObserver {
            NotificationCenter.default.removeObserver(preferenceObserver)
        }
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

        NSLayoutConstraint.activate([
            rootContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            toolbarContainer.topAnchor.constraint(equalTo: rootContainer.topAnchor),
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

        groupSelectorButton.translatesAutoresizingMaskIntoConstraints = false
        groupSelectorButton.target = self
        groupSelectorButton.action = #selector(didTapGroupSelector)
        groupSelectorButton.isBordered = false
        groupSelectorButton.image = NSImage(systemSymbolName: "square.grid.3x2", accessibilityDescription: "Tab Group")
        groupSelectorButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        groupSelectorButton.contentTintColor = NSColor.labelColor.withAlphaComponent(0.88)
        groupSelectorButton.wantsLayer = true
        groupSelectorButton.layer?.cornerRadius = 4
        groupSelectorButton.layer?.borderWidth = 1
        groupSelectorButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        groupSelectorButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor

        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton.target = self
        newTabButton.action = #selector(didTapNewTab)
        newTabButton.isBordered = false
        newTabButton.title = ""
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        newTabButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        newTabButton.contentTintColor = NSColor.labelColor.withAlphaComponent(0.98)
        newTabButton.wantsLayer = false

        rightPanelView.translatesAutoresizingMaskIntoConstraints = false

        addressBarField.translatesAutoresizingMaskIntoConstraints = false
        addressBarField.delegate = self
        addressBarField.font = NSFont.systemFont(ofSize: 13.0)
        addressBarField.focusRingType = .none
        addressBarField.onActivate = { [weak self] in
            self?.beginAddressEditing()
        }

        tabSearchField.translatesAutoresizingMaskIntoConstraints = false
        tabSearchField.font = NSFont.systemFont(ofSize: 12.0)
        tabSearchField.placeholderString = "タブを検索"
        tabSearchField.sendsSearchStringImmediately = true
        tabSearchField.sendsWholeSearchString = false
        tabSearchField.target = self
        tabSearchField.action = #selector(tabSearchDidChange(_:))
        tabSearchField.delegate = self

        let toolbarContent = toolbarContainer.contentLayoutView
        toolbarContent.addSubview(groupSelectorButton)
        toolbarContent.addSubview(tabStripContainer)
        toolbarContent.addSubview(newTabButton)
        toolbarContent.addSubview(rightPanelView)
        rightPanelView.addSubview(addressBarField)
        rightPanelView.addSubview(tabSearchField)

        let minLeading = tabStripContainer.leadingAnchor.constraint(greaterThanOrEqualTo: toolbarContent.leadingAnchor, constant: 84)
        tabStripMinLeadingConstraint = minLeading
        let tabWidth = tabStripContainer.widthAnchor.constraint(equalToConstant: 520)
        tabStripWidthConstraint = tabWidth
        let rightPanelWidth = rightPanelView.widthAnchor.constraint(equalToConstant: 250)
        rightPanelWidthConstraint = rightPanelWidth

        NSLayoutConstraint.activate([
            groupSelectorButton.leadingAnchor.constraint(equalTo: toolbarContent.leadingAnchor, constant: 12),
            groupSelectorButton.centerYAnchor.constraint(equalTo: tabStripContainer.centerYAnchor),
            groupSelectorButton.widthAnchor.constraint(equalToConstant: 28),
            groupSelectorButton.heightAnchor.constraint(equalToConstant: 24),

            minLeading,
            tabWidth,
            tabStripContainer.centerXAnchor.constraint(equalTo: toolbarContent.centerXAnchor),
            tabStripContainer.topAnchor.constraint(equalTo: toolbarContent.topAnchor, constant: 1),
            tabStripContainer.bottomAnchor.constraint(equalTo: toolbarContent.bottomAnchor, constant: -1),
            tabStripContainer.trailingAnchor.constraint(lessThanOrEqualTo: newTabButton.leadingAnchor, constant: -6),

            tabStripScrollView.topAnchor.constraint(equalTo: tabStripContainer.topAnchor),
            tabStripScrollView.leadingAnchor.constraint(equalTo: tabStripContainer.leadingAnchor),
            tabStripScrollView.trailingAnchor.constraint(equalTo: tabStripContainer.trailingAnchor),
            tabStripScrollView.bottomAnchor.constraint(equalTo: tabStripContainer.bottomAnchor),
            tabInteractionView.topAnchor.constraint(equalTo: tabStripContainer.topAnchor),
            tabInteractionView.leadingAnchor.constraint(equalTo: tabStripContainer.leadingAnchor),
            tabInteractionView.trailingAnchor.constraint(equalTo: tabStripContainer.trailingAnchor),
            tabInteractionView.bottomAnchor.constraint(equalTo: tabStripContainer.bottomAnchor),

            newTabButton.centerYAnchor.constraint(equalTo: tabStripContainer.centerYAnchor),
            newTabButton.trailingAnchor.constraint(equalTo: rightPanelView.leadingAnchor, constant: -8),
            newTabButton.widthAnchor.constraint(equalToConstant: 24),
            newTabButton.heightAnchor.constraint(equalToConstant: 24),

            rightPanelView.trailingAnchor.constraint(equalTo: toolbarContent.trailingAnchor, constant: -10),
            rightPanelView.topAnchor.constraint(equalTo: toolbarContent.topAnchor, constant: 4),
            rightPanelView.bottomAnchor.constraint(equalTo: toolbarContent.bottomAnchor, constant: -4),
            rightPanelWidth,

            addressBarField.topAnchor.constraint(equalTo: rightPanelView.topAnchor, constant: 1),
            addressBarField.leadingAnchor.constraint(equalTo: rightPanelView.leadingAnchor, constant: 6),
            addressBarField.trailingAnchor.constraint(equalTo: rightPanelView.trailingAnchor, constant: -6),
            addressBarField.heightAnchor.constraint(equalToConstant: 18),

            tabSearchField.leadingAnchor.constraint(equalTo: rightPanelView.leadingAnchor, constant: 4),
            tabSearchField.trailingAnchor.constraint(equalTo: rightPanelView.trailingAnchor, constant: -4),
            tabSearchField.topAnchor.constraint(equalTo: addressBarField.bottomAnchor, constant: 4),
            tabSearchField.heightAnchor.constraint(equalToConstant: 20),
            tabSearchField.bottomAnchor.constraint(lessThanOrEqualTo: rightPanelView.bottomAnchor, constant: -2)
        ])

        setupTabStripInteractions()
        applyAddressDisplayMode(display: "")
        syncGroupSelectorSelection()
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

    private func applyPreferenceChangesIfNeeded() {
        let prefs = BrowserPreferences.shared
        let shouldReconfigureTabs = (prefs.ephemeralModeEnabled != lastEphemeralMode)
            || (prefs.sendDoNotTrack != lastDoNotTrack)
            || (prefs.contentBlockingEnabled != lastContentBlockingEnabled)

        lastEphemeralMode = prefs.ephemeralModeEnabled
        lastDoNotTrack = prefs.sendDoNotTrack
        lastContentBlockingEnabled = prefs.contentBlockingEnabled

        guard shouldReconfigureTabs else { return }
        tabManager.reconfigureAllTabsForCurrentPreferences()
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

    @objc private func didTapNewTab() {
        actions.newTab()
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
        actions.newTab()
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

    func menuToggleWebInspector() {
        guard let webView = tabManager.currentWebView else { return }
        let selector = NSSelectorFromString("_toggleWebInspector:")
        guard webView.responds(to: selector) else { return }
        webView.perform(selector, with: nil)
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

    @objc private func tabSearchDidChange(_ sender: NSSearchField) {
        tabSearchQuery = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rebuildTabStrip()
    }

    private func beginAddressEditing() {
        guard !isAddressEditing else { return }
        isAddressEditing = true

        applyAddressEditingMode()
        addressBarField.stringValue = currentAddressURLString

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.addressBarField)
            self.addressBarField.selectText(nil)
        }
    }

    private func endAddressEditingWithoutSubmit() {
        guard isAddressEditing else { return }
        isAddressEditing = false
        let display = tabManager.currentWebView?.url?.absoluteString ?? ""
        applyAddressDisplayMode(display: display)
        window?.makeFirstResponder(nil)
    }

    private func submitAddressFieldIfNeeded() {
        let input = addressBarField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.isEmpty {
            actions.openLocationInput(input)
        }
        isAddressEditing = false
        applyAddressDisplayMode(display: input)
        window?.makeFirstResponder(nil)
    }

    private func applyAddressDisplayMode(display: String) {
        currentAddressURLString = display
        addressBarField.stringValue = display
        addressBarField.toolTip = display
        applyAddressReadOnlyMode()
    }

    private func applyAddressReadOnlyMode() {
        addressBarField.isEditable = false
        addressBarField.isSelectable = false
        addressBarField.isBezeled = false
        addressBarField.isBordered = false
        addressBarField.drawsBackground = false
        addressBarField.backgroundColor = .clear
        addressBarField.textColor = NSColor.labelColor.withAlphaComponent(0.94)
        addressBarField.alignment = .right
        addressBarField.cell?.lineBreakMode = .byTruncatingMiddle
    }

    private func applyAddressEditingMode() {
        addressBarField.isEditable = true
        addressBarField.isSelectable = true
        addressBarField.isBezeled = true
        addressBarField.isBordered = true
        addressBarField.bezelStyle = .roundedBezel
        addressBarField.drawsBackground = true
        addressBarField.backgroundColor = NSColor.textBackgroundColor
        addressBarField.textColor = NSColor.textColor
        addressBarField.alignment = .right
        addressBarField.cell?.lineBreakMode = .byClipping
    }

    private func attachWebView(_ webView: WKWebView) {
        webContainer.subviews.forEach { $0.removeFromSuperview() }
        overlayView = nil

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
    }

    private func performGestureTabSwitch(direction: ActionCenter.GestureTabSwitchDirection) {
        guard interactiveTabSwitchState == nil else { return }
        guard beginInteractiveTabSwitch(direction: direction), let state = interactiveTabSwitchState else { return }
        completeProgrammaticTabSwitch(state)
    }

    private func beginInteractiveTabSwitch(direction: ActionCenter.GestureTabSwitchDirection) -> Bool {
        guard interactiveTabSwitchState == nil else { return true }

        let count = tabManager.tabCount
        guard count > 1 else { return false }

        let currentIndex = tabManager.currentIndex
        guard currentIndex >= 0, currentIndex < count else { return false }
        guard let fromWebView = tabManager.currentWebView else { return false }

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
        let width = webContainer.bounds.width
        guard width > 1 else {
            tabManager.selectTab(index: state.targetIndex)
            return
        }

        let fromTargetX = state.direction == .left
            ? -(width + UI.tabSwitchGap)
            : (width + UI.tabSwitchGap)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            state.fromWebView.animator().frame.origin.x = pixelAligned(fromTargetX)
            state.toWebView.animator().frame.origin.x = 0
        } completionHandler: { [weak self] in
            self?.tabManager.selectTab(index: state.targetIndex)
        }
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

        let offset: CGFloat
        switch state.direction {
        case .left:
            offset = max(-fullTravel, min(0, totalX))
            let fromX = pixelAligned(offset)
            let toX = pixelAligned(fullTravel + offset)
            state.fromWebView.frame = bounds.offsetBy(dx: fromX, dy: 0)
            state.toWebView.frame = bounds.offsetBy(dx: toX, dy: 0)
        case .right:
            offset = min(fullTravel, max(0, totalX))
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
        let minDuration: TimeInterval = shouldCommit ? 0.22 : 0.16
        let maxDuration: TimeInterval = shouldCommit ? 0.34 : 0.24
        let duration = minDuration + ((maxDuration - minDuration) * TimeInterval(normalized))

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: shouldCommit ? .easeOut : .easeInEaseOut)
            state.fromWebView.animator().frame.origin.x = pixelAligned(fromTargetX)
            state.toWebView.animator().frame.origin.x = pixelAligned(toTargetX)
        } completionHandler: { [weak self] in
            guard let self else { return }
            if shouldCommit {
                self.tabManager.selectTab(index: state.targetIndex)
            } else {
                self.attachWebView(state.fromWebView)
            }
        }
    }

    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard scale > 0 else { return value.rounded() }
        return (value * scale).rounded() / scale
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

        let maxButtonX = trafficButtons.compactMap { button -> CGFloat? in
            guard let superview = button.superview else { return nil }
            let rect = contentView.convert(button.frame, from: superview)
            return rect.maxX
        }.max() ?? 74

        let groupSelectorRequiredLeading: CGFloat = 12 + 28 + 12
        tabStripMinLeadingConstraint?.constant = max(maxButtonX + 10, groupSelectorRequiredLeading)

        let rightPanelWidth = min(300, max(220, window.frame.width * 0.24))
        rightPanelWidthConstraint?.constant = rightPanelWidth

        let reservedRight = rightPanelWidth + 10 + 20 + 8 + 12
        let available = window.frame.width - (maxButtonX + 10) - reservedRight
        tabStripWidthConstraint?.constant = min(640, max(220, available))
        layoutTabStripAndRevealActive()
    }

    private func syncGroupSelectorSelection() {
        let accent = accentColorForCurrentGroup()
        groupSelectorButton.layer?.borderColor = accent.withAlphaComponent(0.52).cgColor
        groupSelectorButton.layer?.backgroundColor = accent.withAlphaComponent(0.20).cgColor
        groupSelectorButton.contentTintColor = accent.withAlphaComponent(0.96)
        groupSelectorButton.toolTip = tabManager.currentGroup.displayName
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
    }

    private func handleTabDragMoved(fromIndex: Int, locationInWindow: NSPoint) {
        guard tabSearchQuery.isEmpty else { return }
        dragFromTabIndex = fromIndex
        dragToTabIndex = nearestTabIndex(to: locationInWindow) ?? fromIndex
    }

    private func handleTabDragEnded(fromIndex: Int, locationInWindow: NSPoint) {
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
        if control == addressBarField, commandSelector == #selector(insertNewline(_:)) {
            submitAddressFieldIfNeeded()
            return true
        }

        if control == addressBarField, commandSelector == #selector(cancelOperation(_:)) {
            endAddressEditingWithoutSubmit()
            return true
        }

        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field == addressBarField else { return }
        if isAddressEditing {
            endAddressEditingWithoutSubmit()
        }
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        syncToolbarLayout()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        syncToolbarLayout()
    }
}

extension MainWindowController: TabManagerDelegate {
    func tabManager(_ manager: TabManager, didSelect webView: WKWebView?) {
        guard let webView else {
            webContainer.subviews.forEach { $0.removeFromSuperview() }
            overlayView = nil
            interactiveTabSwitchState = nil
            applyAddressDisplayMode(display: "")
            rebuildTabStrip()
            return
        }

        interactiveTabSwitchState = nil
        attachWebView(webView)
    }

    func tabManager(_ manager: TabManager, didUpdateTabs count: Int) {
        rebuildTabStrip()
    }
}

extension MainWindowController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tabManager.updateMetadata(for: webView)
        captureThumbnail(for: webView)

        if tabManager.currentWebView === webView, !isAddressEditing {
            applyAddressDisplayMode(display: webView.url?.absoluteString ?? "")
            rebuildTabStrip()
        }
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

            let proceed: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard let self else { return }
                guard response == .alertSecondButtonReturn else { return }
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
}

extension MainWindowController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        _ = webView
        _ = windowFeatures

        // Browser-like behavior: open target="_blank" / window.open in a new tab.
        if navigationAction.targetFrame == nil {
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
                group: targetGroup
            )
        }
        return nil
    }
}

private final class LiquidGlassToolbarView: NSView {
    let contentLayoutView = NonDraggableView()
    private let separatorLayer = CALayer()
    private let topShineLayer = CAGradientLayer()
    private let bottomDepthLayer = CAGradientLayer()

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

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        separatorLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1 / scale)
        topShineLayer.frame = CGRect(x: 0, y: bounds.height * 0.46, width: bounds.width, height: bounds.height * 0.54)
        bottomDepthLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * 0.42)
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(separatorLayer)
        layer?.addSublayer(bottomDepthLayer)
        layer?.addSublayer(topShineLayer)
        separatorLayer.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        topShineLayer.colors = [
            NSColor.white.withAlphaComponent(0.14).cgColor,
            NSColor.white.withAlphaComponent(0.02).cgColor,
            NSColor.clear.cgColor
        ]
        topShineLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        topShineLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        bottomDepthLayer.colors = [
            NSColor.black.withAlphaComponent(0.03).cgColor,
            NSColor.clear.cgColor
        ]
        bottomDepthLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        bottomDepthLayer.endPoint = CGPoint(x: 0.5, y: 1.0)

        contentLayoutView.translatesAutoresizingMaskIntoConstraints = false

        let visualEffectView = NonDraggableVisualEffectView()
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.material = .underWindowBackground
        visualEffectView.state = .followsWindowActiveState
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.isEmphasized = false
        visualEffectView.addSubview(contentLayoutView)
        addSubview(visualEffectView)

        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentLayoutView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            contentLayoutView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            contentLayoutView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            contentLayoutView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])
    }
}

private final class NonDraggableVisualEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { false }
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
    private var dragStartInWindow: NSPoint?
    private var dragActive = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
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
        if !dragActive, hypot(dx, dy) >= 2.0 {
            dragActive = true
            onDragBegan?(start)
        }
        if dragActive {
            onDragMoved?(event.locationInWindow)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStartInWindow else { return }
        if dragActive {
            onDragEnded?(event.locationInWindow)
        } else {
            onClick?(start, 1)
        }
        dragStartInWindow = nil
        dragActive = false
    }
}

private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class AddressBarField: NSTextField {
    var onActivate: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isEditable {
            super.mouseDown(with: event)
            return
        }
        onActivate?()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.isEditable else { return }
            self.window?.makeFirstResponder(self)
            if let editor = self.currentEditor() {
                let end = self.stringValue.count
                editor.selectedRange = NSRange(location: end, length: 0)
            }
        }
    }
}

private final class TabChipView: NSView {
    private let index: Int
    private let thumbnailView = PassthroughImageView()
    private let protectedIconView = PassthroughImageView()
    private let activeAccentLayer = CAGradientLayer()
    private let active: Bool
    private let protectedState: Bool

    var isActiveChip: Bool { active }
    var tabIndex: Int { index }

    init(
        index: Int,
        title: String,
        thumbnail: NSImage?,
        size: NSSize,
        isActive: Bool,
        isProtected: Bool,
        activeAccentColor: NSColor
    ) {
        self.index = index
        self.active = isActive
        protectedState = isProtected
        super.init(frame: .zero)
        setupView(
            title: title,
            thumbnail: thumbnail,
            size: size,
            isActive: isActive,
            isProtected: isProtected,
            activeAccentColor: activeAccentColor
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

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

        protectedIconView.translatesAutoresizingMaskIntoConstraints = false
        protectedIconView.imageScaling = .scaleProportionallyUpOrDown
        protectedIconView.isHidden = !isProtected
        let icon = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        protectedIconView.image = icon?.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        protectedIconView.contentTintColor = NSColor.white.withAlphaComponent(0.95)
        addSubview(protectedIconView)

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

            protectedIconView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            protectedIconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            protectedIconView.widthAnchor.constraint(equalToConstant: 12),
            protectedIconView.heightAnchor.constraint(equalToConstant: 12)
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
        }
    }
}
