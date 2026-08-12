import Cocoa
import VidarrCore

final class GestureOverlayView: NSView {
    struct CaptureConfig {
        let triggerHorizontalDelta: CGFloat = 4.5
        let triggerDominanceRatio: CGFloat = 1.65
        let triggerWindowMs: TimeInterval = 90
        let seedHistoryWindowMs: TimeInterval = 240
        let minPathLength: CGFloat = 90
        let matchScoreThreshold: CGFloat = 0.68
        let livePreviewScoreThreshold: CGFloat = 0.48
        let upStrokeDominanceRatio: CGFloat = 2.0
        let closeActionSuppressionSeconds: TimeInterval = 0.55
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
    private var captureHasStrongVerticalComponent = false
    private var interactiveTabSwipeActive = false
    private var interactiveTabSwipeTotalX: CGFloat = 0
    private var hudAnchorPoint: CGPoint = .zero
    private var latestEventTimestamp: TimeInterval = 0
    private var captureSuppressionUntil: TimeInterval = 0
    private var rightDragLastPointInWindow: NSPoint?
    private var sensitivityMultiplier: CGFloat {
        BrowserPreferences.shared.gestureSensitivity.multiplier
    }

    private var allowedGestureNames: Set<String> {
        let prefs = BrowserPreferences.shared
        var names: Set<String> = []
        if prefs.isGestureEnabled(.back) { names.insert("UpRight") }
        if prefs.isGestureEnabled(.forward) { names.insert("UpLeft") }
        if prefs.isGestureEnabled(.closeTab) { names.insert("DownRight") }
        if prefs.isGestureEnabled(.newTab) { names.insert("DownLeft") }
        if prefs.isGestureEnabled(.reload) { names.insert("O") }
        if prefs.isGestureEnabled(.restoreClosedTab) { names.insert("U") }
        if prefs.isGestureEnabled(.closeAllTabs) { names.insert("DownRightDownRight") }
        if prefs.isGestureEnabled(.nextTab) { names.insert("Left") }
        if prefs.isGestureEnabled(.previousTab) { names.insert("Right") }
        return names
    }

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

    override func hitTest(_ point: NSPoint) -> NSView? {
        hitTarget(at: point, for: NSApp.currentEvent?.type)
    }

    func hitTarget(at point: NSPoint, for eventType: NSEvent.EventType?) -> NSView? {
        guard bounds.contains(point), Self.capturesEvent(eventType) else {
            return nil
        }
        return self
    }

    static func capturesEvent(_ type: NSEvent.EventType?) -> Bool {
        switch type {
        case .scrollWheel, .rightMouseDown, .rightMouseDragged, .rightMouseUp:
            return true
        default:
            return false
        }
    }

    override func scrollWheel(with event: NSEvent) {
        // Normalize to stroke direction. X and Y use independent signs.
        let xSign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let ySign: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        let dx = event.scrollingDeltaX * xSign
        let dy = event.scrollingDeltaY * ySign
        handleGestureInput(
            dx: dx,
            dy: dy,
            timestamp: event.timestamp,
            anchorInWindow: event.locationInWindow,
            shouldCommit: shouldCommitImmediately(for: event),
            passthrough: { [weak self] in
                self?.superScrollWheel(event)
            }
        )
    }

    override func rightMouseDown(with event: NSEvent) {
        rightDragLastPointInWindow = event.locationInWindow
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard let last = rightDragLastPointInWindow else {
            rightDragLastPointInWindow = event.locationInWindow
            return
        }
        let current = event.locationInWindow
        rightDragLastPointInWindow = current

        let dx = current.x - last.x
        let dy = current.y - last.y
        if abs(dx) < 0.01, abs(dy) < 0.01 { return }

        handleGestureInput(
            dx: dx,
            dy: dy,
            timestamp: event.timestamp,
            anchorInWindow: current,
            shouldCommit: false,
            passthrough: {}
        )
    }

    override func rightMouseUp(with event: NSEvent) {
        rightDragLastPointInWindow = nil
        if state == .capturing {
            commitCapture()
        }
    }

    private func superScrollWheel(_ event: NSEvent) {
        super.scrollWheel(with: event)
    }

    private func handleGestureInput(
        dx: CGFloat,
        dy: CGFloat,
        timestamp: TimeInterval,
        anchorInWindow: NSPoint,
        shouldCommit: Bool,
        passthrough: () -> Void
    ) {
        latestEventTimestamp = timestamp

        if timestamp < captureSuppressionUntil {
            passthrough()
            return
        }

        hudAnchorPoint = convert(anchorInWindow, from: nil)

        switch state {
        case .idle:
            trackRecent(dx: dx, dy: dy, timestamp: timestamp)
            if shouldStartCapture() {
                startCapture(at: hudAnchorPoint, withSeed: recentSamples)
                if shouldCommit {
                    commitCapture()
                }
                return
            }
            passthrough()

        case .capturing:
            appendCaptureDelta(dx: dx, dy: dy)
            if handleInteractiveTabSwipe(dx: dx, dy: dy) {
                if shouldCommit {
                    commitCapture()
                }
                return
            }
            updateHUDIfNeeded()
            if shouldCommit {
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
        let triggerHorizontalDelta = config.triggerHorizontalDelta / max(0.75, sensitivityMultiplier)

        let triggerAge = config.triggerWindowMs / 1000
        let triggerThreshold = latestTimestamp - triggerAge
        let triggerSamples = recentSamples.filter { $0.timestamp >= triggerThreshold }
        guard !triggerSamples.isEmpty else { return false }

        if triggerSamples.contains(where: { sample in
            abs(sample.dx) > abs(sample.dy) * config.triggerDominanceRatio
                && abs(sample.dx) > triggerHorizontalDelta
        }) {
            return true
        }

        let lastSamples = triggerSamples.suffix(4)
        guard !lastSamples.isEmpty else { return false }

        let sumX = lastSamples.reduce(CGFloat.zero) { $0 + $1.dx }
        let sumY = lastSamples.reduce(CGFloat.zero) { $0 + $1.dy }

        return abs(sumX) > abs(sumY) * config.triggerDominanceRatio
            && abs(sumX) > triggerHorizontalDelta
    }

    private func startCapture(at point: CGPoint, withSeed seed: [DeltaSample]) {
        state = .capturing
        capturePoints = [point]
        lastLiveCandidate = nil
        captureInvalidated = false
        captureHasStrongVerticalComponent = false

        for sample in seed {
            appendCaptureDelta(dx: sample.dx, dy: sample.dy)
        }

        recentSamples.removeAll()
        updateHUDIfNeeded()
    }

    private func appendCaptureDelta(dx: CGFloat, dy: CGFloat) {
        guard !capturePoints.isEmpty else { return }
        let last = capturePoints[capturePoints.count - 1]
        let next = CGPoint(x: last.x + dx, y: last.y + dy)
        capturePoints.append(next)
        updateVerticalComponentFlagIfNeeded()
    }

    private func updateVerticalComponentFlagIfNeeded() {
        guard capturePoints.count >= 3 else { return }
        let start = capturePoints[0]
        let end = capturePoints[capturePoints.count - 1]
        let absDX = abs(end.x - start.x)
        let absDY = abs(end.y - start.y)
        if absDY >= 18, absDY >= max(10, absDX * 0.42) {
            captureHasStrongVerticalComponent = true
        }
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
            guard pathLength(capturePoints) >= (config.minPathLength * 0.45) / max(0.75, sensitivityMultiplier) else { return nil }
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
                hudView.showCommittedAction(name: result.name, score: result.score, at: hudAnchorPoint, duration: 0.22)
            }
            return
        }

        // テンプレート不成立時のみ水平スワイプへフォールバックする。
        if !captureHasStrongVerticalComponent,
           let horizontal = recognizeHorizontalSwipe(points: capturePoints)
        {
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
        captureHasStrongVerticalComponent = false
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
        if captureHasStrongVerticalComponent {
            return false
        }

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

    private func isLikelyDoubleLoop(_ points: [CGPoint]) -> Bool {
        guard points.count >= 16 else { return false }

        var minX = points[0].x
        var maxX = points[0].x
        var minY = points[0].y
        var maxY = points[0].y
        for p in points {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }

        let width = maxX - minX
        let height = maxY - minY
        guard width > 24, height > 24 else { return false }

        let diagonal = sqrt(width * width + height * height)
        guard diagonal > 1 else { return false }

        let start = points[0]
        let end = points[points.count - 1]
        let closeDistance = sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2))
        let closeRatio = closeDistance / diagonal
        guard closeRatio <= 0.68 else { return false }

        let a = max(width * 0.5, 1)
        let b = max(height * 0.5, 1)
        let ellipseCircumference = .pi * (3 * (a + b) - sqrt((3 * a + b) * (a + 3 * b)))
        guard ellipseCircumference > 1 else { return false }

        let loops = pathLength(points) / ellipseCircumference
        return loops >= 1.22
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
            guard BrowserPreferences.shared.isGestureEnabled(.nextTab) else { return }
            actions.gestureTabSwitchLeft()
        case "Right":
            guard BrowserPreferences.shared.isGestureEnabled(.previousTab) else { return }
            actions.gestureTabSwitchRight()
        case "DownRight":
            guard BrowserPreferences.shared.isGestureEnabled(.closeTab) else { return }
            actions.tabClose()
            captureSuppressionUntil = latestEventTimestamp + config.closeActionSuppressionSeconds
        case "DownRightDownRight":
            guard BrowserPreferences.shared.isGestureEnabled(.closeAllTabs) else { return }
            actions.tabCloseAll()
            captureSuppressionUntil = latestEventTimestamp + config.closeActionSuppressionSeconds
        case "O":
            guard BrowserPreferences.shared.isGestureEnabled(.reload) else { return }
            actions.reload()
        case "U":
            guard BrowserPreferences.shared.isGestureEnabled(.restoreClosedTab) else { return }
            actions.tabReopenClosed()
        case "OO":
            guard BrowserPreferences.shared.isGestureEnabled(.reloadAll) else { return }
            actions.reloadAll()
        case "UpRight":
            guard BrowserPreferences.shared.isGestureEnabled(.back) else { return }
            actions.goBack()
        case "UpLeft":
            guard BrowserPreferences.shared.isGestureEnabled(.forward) else { return }
            actions.goForward()
        case "DownLeft":
            guard BrowserPreferences.shared.isGestureEnabled(.newTab) else { return }
            actions.newTab()
        default:
            break
        }
    }
}
