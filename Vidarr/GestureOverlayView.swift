import Cocoa
import QuartzCore

final class GestureOverlayView: NSView {
    // Injected action dispatcher (weak to avoid retain cycles)
    weak var actionCenter: ActionCenter?

    // MARK: - Exposed thresholds / tuning constants
    // Sleipnir-like gesture intent tuning
    let triggerHorizontalDelta: CGFloat = 6.0        // |dx| > 6
    let dominanceRatio: CGFloat = 2.0                // |dx| > |dy| * 2 for trigger, and Up gestures require |dy| > |dx| * dominanceRatio
    let captureEndTimeoutMs: TimeInterval = 180      // 180ms 無入力でコミット
    let minPathLength: CGFloat = 120                 // 小さ過ぎるジェスチャーを拒否
    let matchScoreThreshold: CGFloat = 0.75          // $1 のマッチスコアしきい値

    // MARK: - Trigger logic
    private enum CaptureState { case idle, arming, capturing }
    private var state: CaptureState = .idle

    // Integrated path (view coordinates)
    private var points: [CGPoint] = []
    private var captureTimer: Timer?

    // HUD
    private var hudLabel: CATextLayer = CATextLayer()
    private var currentBestResult: GestureResult? { didSet { updateHUD() } }

    // Recognizer (deterministic $1)
    private lazy var recognizer = GestureRecognizer(
        matchScoreThreshold: matchScoreThreshold,
        minPathLength: minPathLength,
        dominanceRatio: dominanceRatio
    )

    // MARK: - Init
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        // HUD setup
        hudLabel.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        hudLabel.fontSize = 12
        hudLabel.alignmentMode = .center
        hudLabel.foregroundColor = NSColor.labelColor.withAlphaComponent(0.95).cgColor
        hudLabel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.7).cgColor
        hudLabel.cornerRadius = 6
        hudLabel.isHidden = true
        layer?.addSublayer(hudLabel)
    }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Event Handling
    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        switch state {
        case .idle:
            // Strict horizontal intent detection
            if abs(dx) > abs(dy) * dominanceRatio && abs(dx) > triggerHorizontalDelta {
                state = .arming
                let startPoint = convert(event.locationInWindow, from: nil)
                startCapture(at: startPoint)
                appendDelta(dx: dx, dy: dy)
                scheduleCommitTimer()
            }
        case .arming, .capturing:
            appendDelta(dx: dx, dy: dy)
            scheduleCommitTimer()
        }

        // Pass-through only when not capturing
        if state == .idle {
            super.scrollWheel(with: event)
        } else {
            // capturing: prevent event from reaching WKWebView
        }
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
    }

    // MARK: - Capture Control
    private func startCapture(at startPoint: CGPoint) {
        state = .capturing
        points = [startPoint]
        currentBestResult = nil
        showHUD(at: startPoint)
    }

    private func appendDelta(dx: CGFloat, dy: CGFloat) {
        guard state != .idle else { return }
        let last = points.last ?? .zero
        let next = CGPoint(x: last.x + dx, y: last.y + dy)
        points.append(next)

        // Update HUD with current best match and score
        if let best = recognizer.bestMatch(points: points) {
            currentBestResult = best
        }
    }

    private func scheduleCommitTimer() {
        captureTimer?.invalidate()
        let interval = captureEndTimeoutMs / 1000.0
        captureTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.commitIfNeeded()
        }
    }

    private func commitIfNeeded() {
        guard state != .idle else { return }
        // Recognize and dispatch action
        if let result = recognizer.recognize(points: points) {
            currentBestResult = result
            performAction(for: result.name)
            // Keep HUD for 300ms to show final action name/score
            let finalText = "  \(result.name)  \(String(format: "%.2f", result.score))  "
            setHUDText(finalText)
            scheduleHideHUD(after: 0.3)
        } else {
            // No match: hide HUD immediately
            hideHUD()
        }
        // Reset state but don't immediately hide HUD (handled above)
        resetState()
    }

    private func resetState() {
        state = .idle
        points.removeAll()
        captureTimer?.invalidate()
        captureTimer = nil
        currentBestResult = nil
    }

    // MARK: - HUD
    private func showHUD(at point: CGPoint) {
        let size = CGSize(width: 160, height: 28)
        let origin = CGPoint(x: point.x + 12, y: point.y - size.height - 12)
        hudLabel.frame = CGRect(origin: origin, size: size)
        hudLabel.isHidden = false
        updateHUD()
    }

    private func setHUDText(_ text: String) {
        hudLabel.string = text
    }

    private func updateHUD() {
        if let best = currentBestResult {
            let text = "  \(best.name)  \(String(format: "%.2f", best.score))  "
            hudLabel.string = text
        } else {
            hudLabel.string = "  …  "
        }
    }

    private func scheduleHideHUD(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.hideHUD()
        }
    }

    private func hideHUD() {
        hudLabel.isHidden = true
        hudLabel.string = nil
    }

    // MARK: - Action dispatch
    private func performAction(for name: String) {
        guard let actions = actionCenter else { return }
        switch name {
        case "Left": actions.tabPrev()
        case "Right": actions.tabNext()
        case "L": actions.tabClose()
        case "U": actions.tabReopenClosed()
        case "O": actions.reload()
        case "OO": actions.reloadAll()
        case "UpRight": actions.goBack()
        case "UpLeft": actions.goForward()
        case "S": actions.search()
        default: break
        }
        print("Gesture committed: \(name)")
    }
}
