import Cocoa

final class GestureOverlayView: NSView {
    struct CaptureConfig {
        let triggerHorizontalDelta: CGFloat = 6.0
        let triggerDominanceRatio: CGFloat = 2.0
        let triggerWindowMs: TimeInterval = 120
        let captureEndTimeoutMs: TimeInterval = 180
        let minPathLength: CGFloat = 120
        let matchScoreThreshold: CGFloat = 0.75
        let upStrokeDominanceRatio: CGFloat = 2.0
    }

    weak var actionCenter: ActionCenter?

    let config = CaptureConfig()

    private struct DeltaSample {
        let dx: CGFloat
        let dy: CGFloat
        let timestamp: TimeInterval
    }

    private enum State {
        case idle
        case capturing
    }

    private var state: State = .idle
    private var recentSamples: [DeltaSample] = []
    private var capturePoints: [CGPoint] = []
    private var captureTimer: Timer?
    private var hudAnchorPoint: CGPoint = .zero

    private lazy var recognizer = GestureRecognizer(
        matchScoreThreshold: config.matchScoreThreshold,
        minPathLength: config.minPathLength,
        dominanceRatio: config.upStrokeDominanceRatio
    )

    private let hudView = GestureHUDView(frame: CGRect(x: 0, y: 0, width: 160, height: 28))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override var isOpaque: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        hudAnchorPoint = convert(event.locationInWindow, from: nil)

        switch state {
        case .idle:
            trackRecent(dx: dx, dy: dy, timestamp: event.timestamp)
            if shouldStartCapture() {
                startCapture(at: hudAnchorPoint, withSeed: recentSamples)
                scheduleCommitTimer()
                return
            }
            super.scrollWheel(with: event)

        case .capturing:
            appendCaptureDelta(dx: dx, dy: dy)
            updateHUDIfNeeded()
            scheduleCommitTimer()
            // キャプチャ中は WebView 側へスクロールイベントを渡さない。
        }
    }

    private func trackRecent(dx: CGFloat, dy: CGFloat, timestamp: TimeInterval) {
        recentSamples.append(DeltaSample(dx: dx, dy: dy, timestamp: timestamp))

        let maxAge = config.triggerWindowMs / 1000
        let threshold = timestamp - maxAge
        recentSamples.removeAll { $0.timestamp < threshold }
    }

    private func shouldStartCapture() -> Bool {
        guard !recentSamples.isEmpty else { return false }

        let sumX = recentSamples.reduce(CGFloat.zero) { $0 + $1.dx }
        let sumY = recentSamples.reduce(CGFloat.zero) { $0 + $1.dy }

        return abs(sumX) > abs(sumY) * config.triggerDominanceRatio
            && abs(sumX) > config.triggerHorizontalDelta
    }

    private func startCapture(at point: CGPoint, withSeed seed: [DeltaSample]) {
        state = .capturing
        capturePoints = [point]

        for sample in seed {
            appendCaptureDelta(dx: sample.dx, dy: sample.dy)
        }

        recentSamples.removeAll()
        updateHUDIfNeeded()
    }

    private func appendCaptureDelta(dx: CGFloat, dy: CGFloat) {
        guard !capturePoints.isEmpty else { return }
        let last = capturePoints[capturePoints.count - 1]
        capturePoints.append(CGPoint(x: last.x + dx, y: last.y + dy))
    }

    private func scheduleCommitTimer() {
        captureTimer?.invalidate()
        let timer = Timer(timeInterval: config.captureEndTimeoutMs / 1000, repeats: false) { [weak self] _ in
            self?.commitCapture()
        }
        captureTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func commitCapture() {
        defer { resetCaptureState() }

        guard !capturePoints.isEmpty else {
            hudView.hideImmediately()
            return
        }

        let strict = recognizer.recognize(points: capturePoints)
        let relaxed: GestureResult? = {
            guard strict == nil else { return nil }
            guard pathLength(capturePoints) >= config.minPathLength * 0.62 else { return nil }
            return recognizer.bestPassingMatch(points: capturePoints, minimumScore: max(0.82, config.matchScoreThreshold))
        }()

        guard let result = strict ?? relaxed else {
            hudView.hideImmediately()
            return
        }

        performAction(for: result.name)
        hudView.showCommittedAction(name: result.name, score: result.score, at: hudAnchorPoint)
    }

    private func resetCaptureState() {
        state = .idle
        capturePoints.removeAll()
        captureTimer?.invalidate()
        captureTimer = nil
        recentSamples.removeAll()
    }

    private func updateHUDIfNeeded() {
        guard let best = recognizer.bestMatch(points: capturePoints) else {
            hudView.hideImmediately()
            return
        }
        hudView.showLiveCandidate(name: best.name, score: best.score, at: hudAnchorPoint)
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }

        var total: CGFloat = 0
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            total += sqrt(dx * dx + dy * dy)
        }
        return total
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(hudView)
    }

    private func performAction(for name: String) {
        guard let actions = actionCenter else { return }

        switch name {
        case "Left":
            actions.tabPrev()
        case "Right":
            actions.tabNext()
        case "L":
            actions.tabClose()
        case "LL":
            actions.tabCloseAll()
        case "U":
            actions.tabReopenClosed()
        case "O":
            actions.reload()
        case "OO":
            actions.reloadAll()
        case "UpRight":
            actions.goBack()
        case "UpLeft":
            actions.goForward()
        case "S":
            actions.search()
        default:
            break
        }
    }
}
