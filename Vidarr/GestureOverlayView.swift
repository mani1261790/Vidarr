import Cocoa

final class GestureOverlayView: NSView {
    struct CaptureConfig {
        let triggerHorizontalDelta: CGFloat = 4.5
        let triggerDominanceRatio: CGFloat = 1.65
        let triggerWindowMs: TimeInterval = 90
        let seedHistoryWindowMs: TimeInterval = 240
        let captureEndTimeoutMs: TimeInterval = 22
        let minPathLength: CGFloat = 90
        let matchScoreThreshold: CGFloat = 0.68
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

    private let hudView = GestureHUDView(frame: CGRect(x: 0, y: 0, width: 560, height: 290))

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
        // Normalize to stroke direction. X and Y use independent signs.
        let xSign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let ySign: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        let dx = event.scrollingDeltaX * xSign
        let dy = event.scrollingDeltaY * ySign
        hudAnchorPoint = convert(event.locationInWindow, from: nil)

        switch state {
        case .idle:
            trackRecent(dx: dx, dy: dy, timestamp: event.timestamp)
            if shouldStartCapture() {
                startCapture(at: hudAnchorPoint, withSeed: recentSamples)
                if shouldCommitImmediately(for: event) {
                    commitCapture()
                } else {
                    scheduleCommitTimer()
                }
                return
            }
            super.scrollWheel(with: event)

        case .capturing:
            appendCaptureDelta(dx: dx, dy: dy)
            updateHUDIfNeeded()
            if shouldCommitImmediately(for: event) {
                commitCapture()
                return
            }
            scheduleCommitTimer()
            // キャプチャ中は WebView 側へスクロールイベントを渡さない。
        }
    }

    private func trackRecent(dx: CGFloat, dy: CGFloat, timestamp: TimeInterval) {
        recentSamples.append(DeltaSample(dx: dx, dy: dy, timestamp: timestamp))

        let maxAge = config.seedHistoryWindowMs / 1000
        let threshold = timestamp - maxAge
        recentSamples.removeAll { $0.timestamp < threshold }
    }

    private func shouldStartCapture() -> Bool {
        guard !recentSamples.isEmpty else { return false }
        guard let latestTimestamp = recentSamples.last?.timestamp else { return false }

        let triggerAge = config.triggerWindowMs / 1000
        let triggerThreshold = latestTimestamp - triggerAge
        let triggerSamples = recentSamples.filter { $0.timestamp >= triggerThreshold }
        guard !triggerSamples.isEmpty else { return false }

        if triggerSamples.contains(where: { sample in
            abs(sample.dx) > abs(sample.dy) * config.triggerDominanceRatio
                && abs(sample.dx) > config.triggerHorizontalDelta
        }) {
            return true
        }

        let lastSamples = triggerSamples.suffix(4)
        guard !lastSamples.isEmpty else { return false }

        let sumX = lastSamples.reduce(CGFloat.zero) { $0 + $1.dx }
        let sumY = lastSamples.reduce(CGFloat.zero) { $0 + $1.dy }

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
        timer.tolerance = 0.005
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
            guard pathLength(capturePoints) >= config.minPathLength * 0.45 else { return nil }
            return recognizer.bestPassingMatch(points: capturePoints, minimumScore: max(0.58, config.matchScoreThreshold - 0.16))
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

    private func shouldCommitImmediately(for event: NSEvent) -> Bool {
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            return true
        }

        if event.phase == [] && event.momentumPhase.contains(.began) {
            return true
        }

        return false
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
            actions.tabNext()
        case "Right":
            actions.tabPrev()
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
        case "DownLeft":
            actions.newTab()
        default:
            break
        }
    }
}
