import Cocoa

final class GestureOverlayView: NSView {
    struct CaptureConfig {
        let triggerHorizontalDelta: CGFloat = 4.5
        let triggerDominanceRatio: CGFloat = 1.65
        let triggerWindowMs: TimeInterval = 90
        let seedHistoryWindowMs: TimeInterval = 240
        let minPathLength: CGFloat = 90
        let matchScoreThreshold: CGFloat = 0.68
        let livePreviewScoreThreshold: CGFloat = 0.52
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
    private var lastLiveCandidate: GestureResult?
    private var captureInvalidated = false
    private var interactiveTabSwipeActive = false
    private var interactiveTabSwipeTotalX: CGFloat = 0
    private var hudAnchorPoint: CGPoint = .zero
    private var latestEventTimestamp: TimeInterval = 0
    private var captureSuppressionUntil: TimeInterval = 0
    private let allowedGestureNames: Set<String> = [
        "UpRight", "UpLeft", "DownRight", "DownLeft",
        "O", "S", "OO", "DownRightDownRight",
        "Right", "Left"
    ]

    private lazy var recognizer = GestureRecognizer(
        matchScoreThreshold: config.matchScoreThreshold,
        minPathLength: config.minPathLength,
        dominanceRatio: config.upStrokeDominanceRatio
    )

    private let hudView = GestureHUDView(
        frame: CGRect(origin: .zero, size: GestureHUDView.preferredSize)
    )

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
        latestEventTimestamp = event.timestamp

        if event.timestamp < captureSuppressionUntil {
            super.scrollWheel(with: event)
            return
        }

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
                }
                return
            }
            super.scrollWheel(with: event)

        case .capturing:
            appendCaptureDelta(dx: dx, dy: dy)
            if handleInteractiveTabSwipe(dx: dx, dy: dy) {
                if shouldCommitImmediately(for: event) {
                    commitCapture()
                }
                return
            }
            updateHUDIfNeeded()
            if shouldCommitImmediately(for: event) {
                commitCapture()
                return
            }
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
        lastLiveCandidate = nil
        captureInvalidated = false

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

    private func commitCapture() {
        defer { resetCaptureState() }

        guard !capturePoints.isEmpty else {
            hudView.hideImmediately()
            return
        }

        if interactiveTabSwipeActive {
            actionCenter?.finishInteractiveTabSwitch(totalX: interactiveTabSwipeTotalX)
            hudView.hideImmediately()
            return
        }

        guard !captureInvalidated else {
            hudView.hideImmediately()
            return
        }

        let strict = recognizer.recognize(points: capturePoints, allowedNames: allowedGestureNames)
        let relaxed: GestureResult? = {
            guard strict == nil else { return nil }
            guard pathLength(capturePoints) >= config.minPathLength * 0.45 else { return nil }
            return recognizer.bestPassingMatch(
                points: capturePoints,
                minimumScore: max(0.58, config.matchScoreThreshold - 0.16),
                allowedNames: allowedGestureNames
            )
        }()

        if let result = strict ?? relaxed {
            performAction(for: result.name)
            if result.name == "Left" || result.name == "Right" {
                hudView.hideImmediately()
            } else {
                hudView.showCommittedAction(name: result.name, score: result.score, at: hudAnchorPoint)
            }
            return
        }

        // テンプレート不成立時のみ水平スワイプへフォールバックする。
        if let horizontal = recognizeHorizontalSwipe(points: capturePoints) {
            performAction(for: horizontal.name)
            hudView.hideImmediately()
            return
        }

        hudView.hideImmediately()
    }

    private func recognizeHorizontalSwipe(points: [CGPoint]) -> GestureResult? {
        guard points.count >= 3 else { return nil }

        let start = points[0]
        let end = points[points.count - 1]
        let dx = end.x - start.x
        let dy = end.y - start.y
        let absDX = abs(dx)
        let absDY = abs(dy)

        guard absDX >= 36 else { return nil }
        guard absDX >= absDY * 1.6 else { return nil }

        let path = pathLength(points)
        guard path >= 32 else { return nil }
        guard path <= absDX * 1.5 + 8 else { return nil }

        // 波打つ入力を除外し、左右スクロールに近い直線ストロークだけを対象にする。
        var minY = points[0].y
        var maxY = points[0].y
        for point in points {
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let verticalExcursion = maxY - minY
        guard verticalExcursion <= max(26, absDX * 0.36) else { return nil }

        let name = dx < 0 ? "Left" : "Right"
        return GestureResult(name: name, score: 1.0)
    }

    private func resetCaptureState() {
        state = .idle
        capturePoints.removeAll()
        lastLiveCandidate = nil
        captureInvalidated = false
        interactiveTabSwipeActive = false
        interactiveTabSwipeTotalX = 0
        recentSamples.removeAll()
    }

    private func updateHUDIfNeeded() {
        if captureInvalidated {
            hudView.hideImmediately()
            return
        }

        if let best = recognizer.bestPassingMatch(
            points: capturePoints,
            minimumScore: config.livePreviewScoreThreshold,
            allowedNames: allowedGestureNames
        ) {
            if best.name == "Left" || best.name == "Right" {
                lastLiveCandidate = nil
                hudView.hideImmediately()
            } else {
                lastLiveCandidate = best
                hudView.showLiveCandidate(name: best.name, score: best.score, at: hudAnchorPoint)
            }
            return
        }

        // 一度候補が出たあとに許可パターンから外れたら、HUDを消して確定実行も無効化する。
        if lastLiveCandidate != nil {
            captureInvalidated = true
            lastLiveCandidate = nil
        }
        hudView.hideImmediately()
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

    private func handleInteractiveTabSwipe(dx: CGFloat, dy _: CGFloat) -> Bool {
        if interactiveTabSwipeActive {
            interactiveTabSwipeTotalX += dx
            actionCenter?.updateInteractiveTabSwitch(totalX: interactiveTabSwipeTotalX)
            return true
        }

        guard capturePoints.count >= 4 else { return false }

        let start = capturePoints[0]
        let end = capturePoints[capturePoints.count - 1]
        let displacementX = end.x - start.x
        let displacementY = end.y - start.y
        let absDX = abs(displacementX)
        let absDY = abs(displacementY)
        guard absDX >= 28 else { return false }
        guard absDX >= absDY * 2.35 else { return false }

        var minY = capturePoints[0].y
        var maxY = capturePoints[0].y
        for point in capturePoints {
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let verticalExcursion = maxY - minY
        guard verticalExcursion <= 20 else { return false }

        let direction: ActionCenter.GestureTabSwitchDirection = displacementX < 0 ? .left : .right
        guard actionCenter?.beginInteractiveTabSwitch(direction: direction) == true else { return false }

        interactiveTabSwipeActive = true
        interactiveTabSwipeTotalX = displacementX
        actionCenter?.updateInteractiveTabSwitch(totalX: interactiveTabSwipeTotalX)
        lastLiveCandidate = nil
        hudView.hideImmediately()
        return true
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
            actions.gestureTabSwitchLeft()
        case "Right":
            actions.gestureTabSwitchRight()
        case "DownRight":
            actions.tabClose()
            captureSuppressionUntil = latestEventTimestamp + 0.28
        case "DownRightDownRight":
            actions.tabCloseAll()
            captureSuppressionUntil = latestEventTimestamp + 0.28
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
