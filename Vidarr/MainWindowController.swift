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
    private let addressBarDisplayLabel = ClickableLabelField()
    private let addressBarEditorField = NSTextField()
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
    private var dragPreviewView: NSImageView?
    private weak var dragSourceChipView: TabChipView?
    private var dragPreviewOffsetX: CGFloat = 0
    private var preferenceObserver: NSObjectProtocol?
    private var lastEphemeralMode = BrowserPreferences.shared.ephemeralModeEnabled
    private var lastDoNotTrack = BrowserPreferences.shared.sendDoNotTrack
    private var lastContentBlockingEnabled = BrowserPreferences.shared.contentBlockingEnabled
    private var temporarilyAllowedHosts: Set<String> = []
    private var configuredLongPressControllers: Set<ObjectIdentifier> = []
    private var longPressHandlerBoxes: [ObjectIdentifier: WeakScriptMessageHandler] = [:]
    private let trackingQueryKeys: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "gclid", "dclid", "fbclid", "msclkid", "yclid", "mc_cid", "mc_eid", "igshid", "rb_clickid"
    ]
    private static let longPressLinkMessageName = "vidarrLongPressLink"
    private static let selectionSearchMessageName = "vidarrSelectionSearch"

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
        groupSelectorButton.wantsLayer = false

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

        addressBarDisplayLabel.translatesAutoresizingMaskIntoConstraints = false
        addressBarDisplayLabel.font = NSFont.systemFont(ofSize: 13.0)
        addressBarDisplayLabel.isEditable = false
        addressBarDisplayLabel.isSelectable = false
        addressBarDisplayLabel.isBezeled = false
        addressBarDisplayLabel.isBordered = false
        addressBarDisplayLabel.drawsBackground = false
        addressBarDisplayLabel.alignment = .right
        addressBarDisplayLabel.textColor = NSColor.labelColor.withAlphaComponent(0.94)
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
        toolbarContent.addSubview(groupSelectorButton)
        toolbarContent.addSubview(tabStripContainer)
        toolbarContent.addSubview(newTabButton)
        toolbarContent.addSubview(rightPanelView)
        rightPanelView.addSubview(addressBarDisplayLabel)
        rightPanelView.addSubview(addressBarEditorField)
        rightPanelView.addSubview(tabSearchField)

        let minLeading = groupSelectorButton.leadingAnchor.constraint(greaterThanOrEqualTo: toolbarContent.leadingAnchor, constant: 84)
        tabStripMinLeadingConstraint = minLeading
        let tabWidth = tabStripContainer.widthAnchor.constraint(equalToConstant: 520)
        tabStripWidthConstraint = tabWidth
        let rightPanelWidth = rightPanelView.widthAnchor.constraint(equalToConstant: 250)
        rightPanelWidthConstraint = rightPanelWidth

        NSLayoutConstraint.activate([
            groupSelectorButton.centerYAnchor.constraint(equalTo: tabStripContainer.centerYAnchor),
            groupSelectorButton.trailingAnchor.constraint(equalTo: tabStripContainer.leadingAnchor, constant: -6),
            groupSelectorButton.widthAnchor.constraint(equalToConstant: 28),
            groupSelectorButton.heightAnchor.constraint(equalToConstant: 24),

            minLeading,
            tabWidth,
            tabStripContainer.centerXAnchor.constraint(equalTo: toolbarContent.centerXAnchor),
            tabStripContainer.topAnchor.constraint(equalTo: toolbarContent.topAnchor, constant: 1),
            tabStripContainer.bottomAnchor.constraint(equalTo: toolbarContent.bottomAnchor, constant: -1),
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

    func menuToggleBookmark() {
        guard let webView = tabManager.currentWebView,
              let url = webView.url else {
            return
        }
        tabManager.toggleCurrentTabBookmark()
        let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if tabManager.isCurrentTabBookmarked {
            BookmarkStore.shared.addOrUpdate(url: url, title: title)
        } else {
            BookmarkStore.shared.remove(url: url)
        }
    }

    func menuOpenExternalListURL(_ url: URL) {
        tabManager.newTab(url: url)
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
    }

    func windowDidBecomeKey(_ notification: Notification) {
        syncToolbarLayout()
    }

    func windowDidResignKey(_ notification: Notification) {
        endAddressEditingWithoutSubmit()
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
        if let url = webView.url {
            let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            BrowsingHistoryStore.shared.recordVisit(url: url, title: title)
            if tabManager.isCurrentTabBookmarked, tabManager.currentWebView === webView {
                BookmarkStore.shared.addOrUpdate(url: url, title: title)
            }
        }

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
                group: targetGroup,
                activate: true
            )
        }
        return nil
    }
}

extension MainWindowController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }

        if message.name == Self.longPressLinkMessageName {
            guard let href = body["href"] as? String else { return }
            guard let url = URL(string: href) else { return }
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
    private var dragStartInWindow: NSPoint?
    private var dragActive = false
    private var previousWindowMovableState: Bool?

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

private final class TabChipView: NSView {
    private let index: Int
    private let thumbnailView = PassthroughImageView()
    private let statusBadgeView = NSView()
    private let statusIconView = PassthroughImageView()
    private let activeAccentLayer = CAGradientLayer()
    private let active: Bool
    private let protectedState: Bool
    private let bookmarkedState: Bool

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

        let markerImageName: String
        let markerColor: NSColor
        if isProtected {
            markerImageName = "pin.fill"
            markerColor = NSColor(calibratedRed: 0.29, green: 0.67, blue: 1.0, alpha: 0.96)
        } else if isBookmarked {
            markerImageName = "star.fill"
            markerColor = NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.15, alpha: 0.96)
        } else {
            markerImageName = "xmark"
            markerColor = NSColor.black.withAlphaComponent(0.78)
        }
        let markerImage = NSImage(systemSymbolName: markerImageName, accessibilityDescription: nil)
        statusIconView.image = markerImage?.withSymbolConfiguration(.init(pointSize: 8.5, weight: .bold))
        statusIconView.contentTintColor = NSColor.white.withAlphaComponent(0.96)
        statusBadgeView.layer?.backgroundColor = markerColor.cgColor

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
