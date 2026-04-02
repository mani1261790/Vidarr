import CoreGraphics
import Foundation
import SwiftUI
import UIKit

enum PadGestureAction: String {
    case previousTab
    case nextTab
    case closeTab
    case closeAllTabs
    case restoreClosedTab
    case reload
    case reloadAll
    case back
    case forward
    case search
    case newTab
}

struct PadGestureHUDState: Equatable {
    let action: PadGestureAction
    let title: String
    let systemImageName: String
    let confidence: CGFloat
    let isCommitted: Bool
}

struct PadGestureConfiguration {
    let sensitivity: PadGestureSensitivity
    let enabledOptions: Set<PadGestureOption>
    let onPreview: (PadGestureHUDState?) -> Void
    let onHorizontalSwipeDrag: (PadGestureAction, CGFloat) -> Void
    let onHorizontalSwipeFinish: (PadGestureAction, CGFloat) -> Void
    let onHorizontalSwipeCancel: () -> Void
    let onCommit: (PadGestureAction) -> Void
    let onCancel: () -> Void
}

final class PadGestureCaptureCoordinator: NSObject, UIGestureRecognizerDelegate {
    private struct CaptureConfig {
        let triggerHorizontalDelta: CGFloat = 3.8
        let triggerDominanceRatio: CGFloat = 1.52
        let triggerWindowMs: TimeInterval = 90
        let seedHistoryWindowMs: TimeInterval = 240
        let minPathLength: CGFloat = 68
        let matchScoreThreshold: CGFloat = 0.66
        let livePreviewScoreThreshold: CGFloat = 0.34
        let upStrokeDominanceRatio: CGFloat = 2.0
        let horizontalSwipeStartDistance: CGFloat = 24
        let horizontalSwipeConfirmDistance: CGFloat = 30
        let horizontalSwipeDominanceRatio: CGFloat = 2.1
        let horizontalSwipeVerticalExcursion: CGFloat = 18
    }

    private struct DeltaSample {
        let dx: CGFloat
        let dy: CGFloat
        let timestamp: TimeInterval
    }

    private enum State {
        case idle
        case capturing
    }

    private let config = CaptureConfig()
    private var enabledOptions: Set<PadGestureOption>

    var sensitivity: PadGestureSensitivity
    private var onPreview: (PadGestureHUDState?) -> Void
    private var onHorizontalSwipeDrag: (PadGestureAction, CGFloat) -> Void
    private var onHorizontalSwipeFinish: (PadGestureAction, CGFloat) -> Void
    private var onHorizontalSwipeCancel: () -> Void
    private var onCommit: (PadGestureAction) -> Void
    private var onCancel: () -> Void

    private var state: State = .idle
    private var recentSamples: [DeltaSample] = []
    private var capturePoints: [CGPoint] = []
    private var lastLiveCandidate: PadGestureResult?
    private var captureInvalidated = false
    private var captureHasStrongVerticalComponent = false
    private var lastLocation: CGPoint?
    private var latestTimestamp: TimeInterval = 0
    private var currentViewWidth: CGFloat = 0
    private var activeHorizontalAction: PadGestureAction?
    private var interactiveTabSwipeActive = false
    private var interactiveTabSwipeTotalX: CGFloat = 0
    private var suppressHorizontalCancelOnReset = false

    private lazy var recognizer = PadGestureRecognizer(
        matchScoreThreshold: config.matchScoreThreshold,
        minPathLength: config.minPathLength,
        dominanceRatio: config.upStrokeDominanceRatio
    )

    init(
        sensitivity: PadGestureSensitivity,
        onPreview: @escaping (PadGestureHUDState?) -> Void,
        onHorizontalSwipeDrag: @escaping (PadGestureAction, CGFloat) -> Void,
        onHorizontalSwipeFinish: @escaping (PadGestureAction, CGFloat) -> Void,
        onHorizontalSwipeCancel: @escaping () -> Void,
        onCommit: @escaping (PadGestureAction) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sensitivity = sensitivity
        self.enabledOptions = Set(PadGestureOption.allCases)
        self.onPreview = onPreview
        self.onHorizontalSwipeDrag = onHorizontalSwipeDrag
        self.onHorizontalSwipeFinish = onHorizontalSwipeFinish
        self.onHorizontalSwipeCancel = onHorizontalSwipeCancel
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    func update(configuration: PadGestureConfiguration) {
        sensitivity = configuration.sensitivity
        enabledOptions = configuration.enabledOptions
        onPreview = configuration.onPreview
        onHorizontalSwipeDrag = configuration.onHorizontalSwipeDrag
        onHorizontalSwipeFinish = configuration.onHorizontalSwipeFinish
        onHorizontalSwipeCancel = configuration.onHorizontalSwipeCancel
        onCommit = configuration.onCommit
        onCancel = configuration.onCancel
    }

    private var allowedGestureNames: Set<String> {
        var names: Set<String> = []
        if enabledOptions.contains(.back) { names.insert("UpRight") }
        if enabledOptions.contains(.forward) { names.insert("UpLeft") }
        if enabledOptions.contains(.closeTab) { names.insert("DownRight") }
        if enabledOptions.contains(.newTab) { names.insert("DownLeft") }
        if enabledOptions.contains(.reload) { names.insert("O") }
        if enabledOptions.contains(.restoreClosedTab) { names.insert("U") }
        if enabledOptions.contains(.reloadAll) { names.insert("OO") }
        if enabledOptions.contains(.closeAllTabs) { names.insert("DownRightDownRight") }
        if enabledOptions.contains(.nextTab) { names.insert("Left") }
        if enabledOptions.contains(.previousTab) { names.insert("Right") }
        return names
    }

    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: recognizer.view)
        let timestamp = ProcessInfo.processInfo.systemUptime
        latestTimestamp = timestamp
        currentViewWidth = recognizer.view?.bounds.width ?? 0

        switch recognizer.state {
        case .began:
            lastLocation = location
            recentSamples.removeAll()
            if state != .capturing {
                onPreview(nil)
            }

        case .changed:
            guard let lastLocation else {
                self.lastLocation = location
                return
            }
            let dx = location.x - lastLocation.x
            let dy = -(location.y - lastLocation.y)
            self.lastLocation = location
            handleInput(dx: dx, dy: dy, timestamp: timestamp, anchor: location)

        case .ended:
            if let lastLocation {
                let dx = location.x - lastLocation.x
                let dy = -(location.y - lastLocation.y)
                self.lastLocation = nil
                handleInput(dx: dx, dy: dy, timestamp: timestamp, anchor: location)
            }
            if state == .capturing {
                commitCapture()
            } else {
                recentSamples.removeAll()
                onCancel()
            }

        default:
            lastLocation = nil
            reset()
            onCancel()
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    private var sensitivityMultiplier: CGFloat {
        sensitivity.multiplier
    }

    private func handleInput(dx: CGFloat, dy: CGFloat, timestamp: TimeInterval, anchor: CGPoint) {
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return }

        switch state {
        case .idle:
            trackRecent(dx: dx, dy: dy, timestamp: timestamp)
            if shouldStartCapture() {
                startCapture(at: anchor, withSeed: recentSamples)
                return
            }

        case .capturing:
            appendCaptureDelta(dx: dx, dy: dy)
            if handleInteractiveTabSwipe(dx: dx, dy: dy) {
                return
            }
            updateHUDIfNeeded()
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

    private func updateHUDIfNeeded() {
        if captureInvalidated {
            cancelHorizontalSwipePreviewIfNeeded()
            onPreview(nil)
            return
        }

        cancelHorizontalSwipePreviewIfNeeded()

        switch directionalPreviewDecision(points: capturePoints) {
        case .candidate(let directional):
            if let state = hudState(for: directional.name, confidence: directional.score, committed: false) {
                lastLiveCandidate = directional
                onPreview(state)
                return
            }
        case .invalid:
            lastLiveCandidate = nil
            onPreview(nil)
            return
        case .none:
            break
        }

        if let best = recognizer.bestPassingMatch(
            points: capturePoints,
            minimumScore: config.livePreviewScoreThreshold,
            allowedNames: allowedGestureNames
        ) {
            if best.name == "Left" || best.name == "Right" {
                lastLiveCandidate = nil
                onPreview(nil)
            } else if let state = hudState(for: best.name, confidence: best.score, committed: false) {
                lastLiveCandidate = best
                onPreview(state)
            }
            return
        }

        if let early = recognizer.bestPassingMatch(
            points: capturePoints,
            minimumScore: 0.20,
            allowedNames: allowedGestureNames.subtracting(["O", "OO"])
        ) {
            if early.name == "Left" || early.name == "Right" {
                lastLiveCandidate = nil
                onPreview(nil)
            } else if let state = hudState(for: early.name, confidence: early.score, committed: false) {
                lastLiveCandidate = early
                onPreview(state)
                return
            }
        }

        if enabledOptions.contains(.restoreClosedTab),
           let result = recognizeUGesture(points: capturePoints),
           let state = hudState(for: result.name, confidence: result.score, committed: false) {
            onPreview(state)
            return
        }

        if lastLiveCandidate != nil {
            captureInvalidated = true
            lastLiveCandidate = nil
        }
        onPreview(nil)
    }

    private func commitCapture() {
        defer { reset() }

        guard !capturePoints.isEmpty else {
            onPreview(nil)
            return
        }

        if interactiveTabSwipeActive, let action = activeHorizontalAction {
            suppressHorizontalCancelOnReset = true
            activeHorizontalAction = nil
            onHorizontalSwipeFinish(action, interactiveTabSwipeTotalX)
            return
        }

        guard !captureInvalidated else {
            onPreview(nil)
            return
        }

        let strict = recognizer.recognize(points: capturePoints, allowedNames: allowedGestureNames)
        let relaxed: PadGestureResult? = {
            guard strict == nil else { return nil }
            guard pathLength(capturePoints) >= (config.minPathLength * 0.45) / max(0.75, sensitivityMultiplier) else { return nil }
            return recognizer.bestPassingMatch(
                points: capturePoints,
                minimumScore: max(0.58, config.matchScoreThreshold - 0.16),
                allowedNames: allowedGestureNames
            )
        }()

        let uFallback: PadGestureResult? = {
            guard strict == nil, relaxed == nil else { return nil }
            guard enabledOptions.contains(.restoreClosedTab) else { return nil }
            return recognizeUGesture(points: capturePoints)
        }()

        let llFallback: PadGestureResult? = {
            guard strict == nil, relaxed == nil, uFallback == nil else { return nil }
            guard enabledOptions.contains(.closeAllTabs) else { return nil }
            return recognizeCloseAllTabsGesture(points: capturePoints)
        }()

        if let result = strict ?? relaxed ?? uFallback ?? llFallback,
           let action = mapAction(name: result.name)
        {
            if action == .previousTab || action == .nextTab {
                suppressHorizontalCancelOnReset = true
                activeHorizontalAction = nil
            }
            onCommit(action)
            return
        }

        if isLikelyDoubleLoop(capturePoints) {
            guard enabledOptions.contains(.reloadAll) else {
                onCancel()
                return
            }
            onCommit(.reloadAll)
            return
        }

        if !captureHasStrongVerticalComponent,
           let horizontal = recognizeHorizontalSwipe(points: capturePoints),
           let action = mapAction(name: horizontal.name)
        {
            onCommit(action)
            return
        }

        onCancel()
    }

    private func recognizeHorizontalSwipe(points: [CGPoint]) -> PadGestureResult? {
        guard points.count >= 3 else { return nil }
        let start = points[0]
        let end = points[points.count - 1]
        let dx = end.x - start.x
        let dy = end.y - start.y
        let absDX = abs(dx)
        let absDY = abs(dy)

        guard absDX >= config.horizontalSwipeConfirmDistance else { return nil }
        guard absDX >= absDY * 1.6 else { return nil }

        let path = pathLength(points)
        guard path >= 32 else { return nil }
        guard path <= absDX * 1.5 + 8 else { return nil }

        var minY = points[0].y
        var maxY = points[0].y
        for point in points {
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let verticalExcursion = maxY - minY
        guard verticalExcursion <= max(26, absDX * 0.36) else { return nil }

        let name = dx < 0 ? "Left" : "Right"
        return PadGestureResult(name: name, score: 1.0)
    }

    private func handleInteractiveTabSwipe(dx: CGFloat, dy: CGFloat) -> Bool {
        if captureHasStrongVerticalComponent {
            return false
        }

        if interactiveTabSwipeActive, let action = activeHorizontalAction {
            interactiveTabSwipeTotalX += dx
            onHorizontalSwipeDrag(action, interactiveTabSwipeTotalX)
            onPreview(nil)
            return true
        }

        guard capturePoints.count >= 4 else { return false }

        let start = capturePoints[0]
        let end = capturePoints[capturePoints.count - 1]
        let displacementX = end.x - start.x
        let displacementY = end.y - start.y
        let absDX = abs(displacementX)
        let absDY = abs(displacementY)
        guard absDX >= config.horizontalSwipeStartDistance else { return false }
        guard absDX >= absDY * config.horizontalSwipeDominanceRatio else { return false }

        var minY = capturePoints[0].y
        var maxY = capturePoints[0].y
        for point in capturePoints {
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let verticalExcursion = maxY - minY
        guard verticalExcursion <= config.horizontalSwipeVerticalExcursion else { return false }

        let action: PadGestureAction = displacementX < 0 ? .nextTab : .previousTab
        let requiredOption: PadGestureOption = displacementX < 0 ? .nextTab : .previousTab
        guard enabledOptions.contains(requiredOption) else { return false }
        interactiveTabSwipeActive = true
        interactiveTabSwipeTotalX = displacementX
        activeHorizontalAction = action
        onHorizontalSwipeDrag(action, interactiveTabSwipeTotalX)
        onPreview(nil)
        return true
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
        let closeDistance = hypot(end.x - start.x, end.y - start.y)
        let closeRatio = closeDistance / diagonal
        guard closeRatio <= 0.68 else { return false }

        let a = max(width * 0.5, 1)
        let b = max(height * 0.5, 1)
        let ellipseCircumference = .pi * (3 * (a + b) - sqrt((3 * a + b) * (a + 3 * b)))
        guard ellipseCircumference > 1 else { return false }

        let loops = pathLength(points) / ellipseCircumference
        return loops >= 1.22
    }

    private func mapAction(name: String) -> PadGestureAction? {
        switch name {
        case "Left":
            return .nextTab
        case "Right":
            return .previousTab
        case "DownRight":
            return .closeTab
        case "DownRightDownRight":
            return .closeAllTabs
        case "U":
            return .restoreClosedTab
        case "O":
            return .reload
        case "OO":
            return .reloadAll
        case "UpRight":
            return .back
        case "UpLeft":
            return .forward
        case "DownLeft":
            return .newTab
        default:
            return nil
        }
    }

    private func hudState(for name: String, confidence: CGFloat, committed: Bool) -> PadGestureHUDState? {
        guard let action = mapAction(name: name),
              let option = preferenceOption(for: action),
              enabledOptions.contains(option) else { return nil }
        return PadGestureHUDState(
            action: action,
            title: "",
            systemImageName: symbol(for: name),
            confidence: confidence,
            isCommitted: committed
        )
    }

    private func preferenceOption(for action: PadGestureAction) -> PadGestureOption? {
        switch action {
        case .nextTab: return .nextTab
        case .previousTab: return .previousTab
        case .closeTab: return .closeTab
        case .closeAllTabs: return .closeAllTabs
        case .restoreClosedTab: return .restoreClosedTab
        case .reload: return .reload
        case .reloadAll: return .reloadAll
        case .back: return .back
        case .forward: return .forward
        case .search: return nil
        case .newTab: return .newTab
        }
    }

    private func symbol(for name: String) -> String {
        switch name {
        case "Left":
            return "arrow.left.circle.fill"
        case "Right":
            return "arrow.right.circle.fill"
        case "DownRight":
            return "xmark.square.fill"
        case "DownRightDownRight":
            return "trash.circle.fill"
        case "O":
            return "arrow.clockwise.circle.fill"
        case "U":
            return "arrow.uturn.backward.circle.fill"
        case "OO":
            return "square.stack.3d.up.fill"
        case "UpRight":
            return "chevron.backward.circle.fill"
        case "UpLeft":
            return "chevron.forward.circle.fill"
        case "DownLeft":
            return "plus.square.on.square"
        default:
            return "questionmark.circle"
        }
    }

    private func recognizeUGesture(points: [CGPoint]) -> PadGestureResult? {
        guard points.count >= 6 else { return nil }
        let compact = collapseDirections(simplifyDirections(points))
        guard compact.count >= 3 else { return nil }
        for index in 0...(compact.count - 3) {
            let slice = Array(compact[index..<(index + 3)])
            guard slice[0].axis == .vertical, slice[0].signed < 0 else { continue }
            guard slice[1].axis == .horizontal, slice[1].signed > 0 else { continue }
            guard slice[2].axis == .vertical, slice[2].signed > 0 else { continue }
            let verticalA = abs(slice[0].primary)
            let horizontal = abs(slice[1].primary)
            let verticalB = abs(slice[2].primary)
            guard verticalA >= 18, horizontal >= 14, verticalB >= 14 else { continue }
            let score = min(1.0, 0.64 + min(verticalA + horizontal + verticalB, 180) / 500)
            return PadGestureResult(name: "U", score: score)
        }
        return nil
    }

    private func recognizeCloseAllTabsGesture(points: [CGPoint]) -> PadGestureResult? {
        let compact = collapseDirections(simplifyDirections(points))
        guard compact.count >= 4 else { return nil }
        for index in 0...(compact.count - 4) {
            let slice = Array(compact[index..<(index + 4)])
            guard slice[0].axis == .vertical, slice[0].signed < 0 else { continue }
            guard slice[1].axis == .horizontal, slice[1].signed > 0 else { continue }
            guard slice[2].axis == .vertical, slice[2].signed < 0 else { continue }
            guard slice[3].axis == .horizontal, slice[3].signed > 0 else { continue }
            let a = abs(slice[0].primary)
            let b = abs(slice[1].primary)
            let c = abs(slice[2].primary)
            let d = abs(slice[3].primary)
            guard a >= 18, b >= 14, c >= 14, d >= 12 else { continue }
            let score = min(1.0, 0.66 + min(a + b + c + d, 220) / 560)
            return PadGestureResult(name: "DownRightDownRight", score: score)
        }
        return nil
    }

    private enum DirectionalPreviewDecision {
        case none
        case invalid
        case candidate(PadGestureResult)
    }

    private func directionalPreviewDecision(points: [CGPoint]) -> DirectionalPreviewDecision {
        let compact = collapseDirections(simplifyDirections(points))
        guard compact.count >= 2 else { return .none }

        let recent = Array(compact.suffix(3))
        if recent.count >= 3,
           enabledOptions.contains(.restoreClosedTab),
           recent[recent.count - 3].axis == .vertical, recent[recent.count - 3].signed < 0, abs(recent[recent.count - 3].primary) >= 14,
           recent[recent.count - 2].axis == .horizontal, recent[recent.count - 2].signed > 0, abs(recent[recent.count - 2].primary) >= 12,
           recent[recent.count - 1].axis == .vertical, recent[recent.count - 1].signed > 0, abs(recent[recent.count - 1].primary) >= 10 {
            return .candidate(PadGestureResult(name: "U", score: 0.8))
        }

        if recent.count >= 3,
           enabledOptions.contains(.closeAllTabs),
           recent[recent.count - 3].axis == .vertical, recent[recent.count - 3].signed < 0, abs(recent[recent.count - 3].primary) >= 14,
           recent[recent.count - 2].axis == .horizontal, recent[recent.count - 2].signed > 0, abs(recent[recent.count - 2].primary) >= 12,
           recent[recent.count - 1].axis == .vertical, recent[recent.count - 1].signed < 0, abs(recent[recent.count - 1].primary) >= 10 {
            return .candidate(PadGestureResult(name: "DownRightDownRight", score: 0.74))
        }

        let first = recent[recent.count - 2]
        let second = recent[recent.count - 1]
        guard abs(first.primary) >= 14, abs(second.primary) >= 10 else { return .none }

        if first.axis == .vertical, first.signed < 0, second.axis == .horizontal, second.signed > 0,
           enabledOptions.contains(.closeTab) {
            return .candidate(PadGestureResult(name: "DownRight", score: 0.66))
        }
        if first.axis == .vertical, first.signed < 0, second.axis == .horizontal, second.signed < 0,
           enabledOptions.contains(.newTab) {
            return .candidate(PadGestureResult(name: "DownLeft", score: 0.66))
        }
        if first.axis == .vertical, first.signed > 0, second.axis == .horizontal, second.signed > 0,
           enabledOptions.contains(.back) {
            return .candidate(PadGestureResult(name: "UpRight", score: 0.66))
        }
        if first.axis == .vertical, first.signed > 0, second.axis == .horizontal, second.signed < 0,
           enabledOptions.contains(.forward) {
            return .candidate(PadGestureResult(name: "UpLeft", score: 0.66))
        }

        if captureHasStrongVerticalComponent {
            if first.axis == .vertical, first.signed < 0, second.axis == .horizontal {
                return .invalid
            }
            if first.axis == .vertical, first.signed > 0, second.axis == .horizontal {
                return .invalid
            }
            if recent.count >= 3,
               recent[recent.count - 3].axis == .vertical,
               recent[recent.count - 2].axis == .horizontal,
               recent[recent.count - 1].axis == .vertical {
                return .invalid
            }
        }
        return .none
    }

    private enum GestureAxis { case horizontal, vertical }
    private struct DirectionSegment {
        let axis: GestureAxis
        let signed: CGFloat
        let primary: CGFloat
    }

    private func simplifyDirections(_ points: [CGPoint]) -> [DirectionSegment] {
        guard points.count > 1 else { return [] }
        return zip(points, points.dropFirst()).compactMap { a, b in
            let dx = b.x - a.x
            let dy = b.y - a.y
            let absDX = abs(dx)
            let absDY = abs(dy)
            guard max(absDX, absDY) >= 3 else { return nil }
            if absDY >= absDX * 0.9 {
                return DirectionSegment(axis: .vertical, signed: dy, primary: absDY)
            }
            if absDX >= absDY * 0.9 {
                return DirectionSegment(axis: .horizontal, signed: dx, primary: absDX)
            }
            return nil
        }
    }

    private func collapseDirections(_ segments: [DirectionSegment]) -> [DirectionSegment] {
        var collapsed: [DirectionSegment] = []
        for segment in segments {
            if let last = collapsed.last,
               last.axis == segment.axis,
               (last.signed >= 0) == (segment.signed >= 0) {
                collapsed.removeLast()
                collapsed.append(DirectionSegment(axis: last.axis, signed: last.signed + segment.signed, primary: last.primary + segment.primary))
            } else {
                collapsed.append(segment)
            }
        }
        return collapsed
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { partial, pair in
            partial + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
    }

    private func reset() {
        state = .idle
        recentSamples.removeAll()
        capturePoints.removeAll()
        lastLiveCandidate = nil
        captureInvalidated = false
        captureHasStrongVerticalComponent = false
        interactiveTabSwipeActive = false
        interactiveTabSwipeTotalX = 0
        if suppressHorizontalCancelOnReset {
            suppressHorizontalCancelOnReset = false
        } else {
            cancelHorizontalSwipePreviewIfNeeded()
        }
        onPreview(nil)
    }

    private func cancelHorizontalSwipePreviewIfNeeded() {
        guard activeHorizontalAction != nil else { return }
        activeHorizontalAction = nil
        onHorizontalSwipeCancel()
    }
}

private struct PadGestureTemplate {
    let name: String
    let points: [CGPoint]
}

private struct PadGestureResult {
    let name: String
    let score: CGFloat
}

private final class PadGestureRecognizer {
    private let squareSize: CGFloat = 250
    private let resampleCount: Int = 96

    private let matchScoreThreshold: CGFloat
    private let minPathLength: CGFloat
    private let dominanceRatio: CGFloat
    private let compositePreferenceSlack: CGFloat = 0.12

    private lazy var templates: [PadGestureTemplate] = {
        Self.rawTemplates().map { template in
            PadGestureTemplate(name: template.name, points: normalize(template.points))
        }
    }()

    init(matchScoreThreshold: CGFloat = 0.75, minPathLength: CGFloat = 120, dominanceRatio: CGFloat = 2.0) {
        self.matchScoreThreshold = matchScoreThreshold
        self.minPathLength = minPathLength
        self.dominanceRatio = dominanceRatio
    }

    func recognize(points raw: [CGPoint], allowedNames: Set<String>? = nil) -> PadGestureResult? {
        guard raw.count >= 10 else { return nil }
        guard pathLength(raw) >= minPathLength else { return nil }

        let normalized = normalize(raw)
        let ranked = rankedTemplateMatches(for: normalized)
        guard let passing = bestPassingCandidate(
            from: ranked,
            raw: raw,
            minimumScore: matchScoreThreshold,
            allowedNames: allowedNames
        ) else { return nil }
        return PadGestureResult(name: passing.name, score: passing.score)
    }

    func bestPassingMatch(points raw: [CGPoint], minimumScore: CGFloat, allowedNames: Set<String>? = nil) -> PadGestureResult? {
        guard raw.count >= 5 else { return nil }

        let normalized = normalize(raw)
        let ranked = rankedTemplateMatches(for: normalized)
        guard let passing = bestPassingCandidate(
            from: ranked,
            raw: raw,
            minimumScore: minimumScore,
            allowedNames: allowedNames
        ) else { return nil }
        return PadGestureResult(name: passing.name, score: passing.score)
    }

    private func rankedTemplateMatches(for normalizedPoints: [CGPoint]) -> [(name: String, score: CGFloat)] {
        var bestDistanceByName: [String: CGFloat] = [:]
        for template in templates {
            let d = pathDistance(normalizedPoints, template.points)
            if let current = bestDistanceByName[template.name] {
                bestDistanceByName[template.name] = min(current, d)
            } else {
                bestDistanceByName[template.name] = d
            }
        }

        let halfDiagonal = 0.5 * sqrt(2) * squareSize
        return bestDistanceByName
            .map { (name: $0.key, score: max(0, min(1, 1 - $0.value / halfDiagonal))) }
            .sorted { $0.score > $1.score }
    }

    private func normalize(_ points: [CGPoint]) -> [CGPoint] {
        var pts = resample(points, n: resampleCount)
        pts = rotateToIndicativeAngle(pts)
        pts = scaleToSquare(pts, size: squareSize)
        pts = translateToOrigin(pts)
        return pts
    }

    private func passesHeuristic(for name: String, raw: [CGPoint]) -> Bool {
        let start = raw.first ?? .zero
        let end = raw.last ?? .zero
        let dx = end.x - start.x
        let dy = end.y - start.y
        let corners = cornerCount(raw)

        switch name {
        case "Left":
            return isSimpleHorizontalStroke(raw, horizontalDirection: .left, dx: dx, dy: dy, corners: corners)
        case "Right":
            return isSimpleHorizontalStroke(raw, horizontalDirection: .right, dx: dx, dy: dy, corners: corners)
        case "L":
            return corners >= 1 && corners <= 2 && dx > 0 && dy < 0 && abs(dy) > minPathLength * 0.12
        case "LL":
            return corners >= 3 && pathLength(raw) >= minPathLength * 1.5 && dx > 0
        case "U":
            return isDownRightUpUShape(raw)
        case "O":
            return isClosedCircular(raw, expectedTurns: 2 * .pi, tolerance: 1.55 * .pi, closeRatioLimit: 0.45)
                && estimatedLoopCount(raw) <= 1.45
        case "OO":
            return isClosedCircular(raw, expectedTurns: 4 * .pi, tolerance: 2.75 * .pi, closeRatioLimit: 0.68)
                && pathLength(raw) >= minPathLength * 0.94
                && estimatedLoopCount(raw) >= 1.22
        case "UpRight":
            return isVerticalThenHorizontal(raw, verticalDirection: .up, horizontalDirection: .right)
        case "UpLeft":
            return isVerticalThenHorizontal(raw, verticalDirection: .up, horizontalDirection: .left)
        case "DownLeft":
            return isVerticalThenHorizontal(raw, verticalDirection: .down, horizontalDirection: .left)
        case "DownRight":
            return isVerticalThenHorizontal(raw, verticalDirection: .down, horizontalDirection: .right)
        case "DownRightDownRight":
            return isDoubleDownRight(raw) && pathLength(raw) >= minPathLength * 1.45
        case "S":
            return isSLike(raw)
        default:
            return false
        }
    }

    private func bestPassingCandidate(
        from ranked: [(name: String, score: CGFloat)],
        raw: [CGPoint],
        minimumScore: CGFloat,
        allowedNames: Set<String>?
    ) -> (name: String, score: CGFloat)? {
        let passing = ranked.filter { candidate in
            if let allowedNames, !allowedNames.contains(candidate.name) {
                return false
            }
            return candidate.score >= minimumScore && passesHeuristic(for: candidate.name, raw: raw)
        }

        guard let best = passing.first else { return nil }

        if best.name == "Left" || best.name == "Right",
           let composite = passing.first(where: {
               $0.name == "UpRight"
                   || $0.name == "UpLeft"
                   || $0.name == "DownLeft"
                   || $0.name == "DownRight"
                   || $0.name == "DownRightDownRight"
           }),
           composite.score >= best.score - compositePreferenceSlack {
            return composite
        }

        if best.name == "O",
           let doubleCircle = passing.first(where: { $0.name == "OO" }),
           (estimatedLoopCount(raw) >= 1.24 || doubleCircle.score >= best.score - 0.22) {
            return doubleCircle
        }

        return best
    }

    private enum HorizontalDirection { case left, right }
    private enum VerticalDirection { case up, down }

    private func isSimpleHorizontalStroke(
        _ raw: [CGPoint],
        horizontalDirection: HorizontalDirection,
        dx: CGFloat,
        dy: CGFloat,
        corners: Int
    ) -> Bool {
        switch horizontalDirection {
        case .left: guard dx < 0 else { return false }
        case .right: guard dx > 0 else { return false }
        }

        let absDx = abs(dx)
        let absDy = abs(dy)
        guard absDx > max(absDy * 1.6, minPathLength * 0.18) else { return false }
        guard corners <= 1 else { return false }

        let box = boundingBox(raw)
        guard box.width > 0 else { return false }
        guard box.height <= max(box.width * 0.34, 22) else { return false }
        guard totalTurningAngle(raw) <= .pi * 0.66 else { return false }

        switch horizontalDirection {
        case .left:
            guard !isVerticalThenHorizontal(raw, verticalDirection: .up, horizontalDirection: .left) else { return false }
            guard !isVerticalThenHorizontal(raw, verticalDirection: .down, horizontalDirection: .left) else { return false }
        case .right:
            guard !isVerticalThenHorizontal(raw, verticalDirection: .up, horizontalDirection: .right) else { return false }
            guard !isVerticalThenHorizontal(raw, verticalDirection: .down, horizontalDirection: .right) else { return false }
        }

        return true
    }

    private func isVerticalThenHorizontal(
        _ raw: [CGPoint],
        verticalDirection: VerticalDirection,
        horizontalDirection: HorizontalDirection
    ) -> Bool {
        guard raw.count >= 8 else { return false }

        let box = boundingBox(raw)
        let minVerticalTravel = max(22, box.height * 0.34)
        let minHorizontalTravel = max(20, box.width * 0.34)

        for ratio in stride(from: 0.34, through: 0.72, by: 0.06) {
            let split = max(2, min(raw.count - 3, Int(CGFloat(raw.count - 1) * CGFloat(ratio))))
            let first = vector(from: raw[0], to: raw[split])
            let second = vector(from: raw[split], to: raw[raw.count - 1])

            guard abs(first.dy) >= minVerticalTravel else { continue }
            guard abs(second.dx) >= minHorizontalTravel else { continue }

            switch verticalDirection {
            case .up:
                guard first.dy > 0, abs(first.dy) > abs(first.dx) * 0.92 else { continue }
            case .down:
                guard first.dy < 0, abs(first.dy) > abs(first.dx) * 0.92 else { continue }
            }

            switch horizontalDirection {
            case .right:
                if second.dx > 0 && abs(second.dx) > abs(second.dy) * 0.7 { return true }
            case .left:
                if second.dx < 0 && abs(second.dx) > abs(second.dy) * 0.7 { return true }
            }
        }

        return false
    }

    private func isDoubleDownRight(_ raw: [CGPoint]) -> Bool {
        guard raw.count >= 12 else { return false }

        let box = boundingBox(raw)
        let minVerticalTravel = max(20, box.height * 0.18)
        let minHorizontalTravel = max(20, box.width * 0.18)

        for r1 in stride(from: 0.14, through: 0.32, by: 0.04) {
            let i1 = max(2, min(raw.count - 5, Int(CGFloat(raw.count - 1) * CGFloat(r1))))
            for r2 in stride(from: 0.34, through: 0.52, by: 0.04) {
                let i2 = max(i1 + 2, min(raw.count - 4, Int(CGFloat(raw.count - 1) * CGFloat(r2))))
                for r3 in stride(from: 0.56, through: 0.78, by: 0.04) {
                    let i3 = max(i2 + 2, min(raw.count - 3, Int(CGFloat(raw.count - 1) * CGFloat(r3))))

                    let v1 = vector(from: raw[0], to: raw[i1])
                    let v2 = vector(from: raw[i1], to: raw[i2])
                    let v3 = vector(from: raw[i2], to: raw[i3])
                    let v4 = vector(from: raw[i3], to: raw[raw.count - 1])

                    guard v1.dy < 0, abs(v1.dy) >= minVerticalTravel, abs(v1.dy) > abs(v1.dx) * 0.78 else { continue }
                    guard v2.dx > 0, abs(v2.dx) >= minHorizontalTravel, abs(v2.dx) > abs(v2.dy) * 0.72 else { continue }
                    guard v3.dy < 0, abs(v3.dy) >= minVerticalTravel, abs(v3.dy) > abs(v3.dx) * 0.78 else { continue }
                    guard v4.dx > 0, abs(v4.dx) >= minHorizontalTravel, abs(v4.dx) > abs(v4.dy) * 0.72 else { continue }

                    return true
                }
            }
        }

        return false
    }

    private func isDownRightUpUShape(_ raw: [CGPoint]) -> Bool {
        guard raw.count >= 10 else { return false }

        let box = boundingBox(raw)
        let minVerticalTravel = max(20, box.height * 0.28)
        let minHorizontalTravel = max(20, box.width * 0.28)

        for r1 in stride(from: 0.20, through: 0.42, by: 0.04) {
            let i1 = max(2, min(raw.count - 5, Int(CGFloat(raw.count - 1) * CGFloat(r1))))
            for r2 in stride(from: 0.56, through: 0.82, by: 0.04) {
                let i2 = max(i1 + 2, min(raw.count - 3, Int(CGFloat(raw.count - 1) * CGFloat(r2))))

                let v1 = vector(from: raw[0], to: raw[i1])
                let v2 = vector(from: raw[i1], to: raw[i2])
                let v3 = vector(from: raw[i2], to: raw[raw.count - 1])

                guard v1.dy < 0, abs(v1.dy) >= minVerticalTravel, abs(v1.dy) > abs(v1.dx) * 0.82 else { continue }
                guard v2.dx > 0, abs(v2.dx) >= minHorizontalTravel, abs(v2.dx) > abs(v2.dy) * 0.72 else { continue }
                guard v3.dy > 0, abs(v3.dy) >= minVerticalTravel, abs(v3.dy) > abs(v3.dx) * 0.82 else { continue }

                let shoulderGap = abs((raw.first?.y ?? 0) - (raw.last?.y ?? 0))
                if shoulderGap <= max(26, box.height * 0.38) { return true }
            }
        }

        return false
    }

    private func isClosedCircular(
        _ raw: [CGPoint],
        expectedTurns: CGFloat,
        tolerance: CGFloat,
        closeRatioLimit: CGFloat
    ) -> Bool {
        guard raw.count >= 10 else { return false }

        let totalTurn = totalTurningAngle(raw)
        let turnMatches = abs(totalTurn - expectedTurns) <= tolerance

        let box = boundingBox(raw)
        let diagonal = sqrt(box.width * box.width + box.height * box.height)
        let closeRatio = diagonal > 0 ? distance(raw[0], raw[raw.count - 1]) / diagonal : 1
        let isClosed = closeRatio < closeRatioLimit

        let aspect = box.height > 0 ? box.width / box.height : 999
        let validAspect = aspect > 0.35 && aspect < 2.8

        return turnMatches && isClosed && validAspect
    }

    private func isSLike(_ raw: [CGPoint]) -> Bool {
        guard raw.count >= 10 else { return false }

        let box = boundingBox(raw)
        let diagonal = sqrt(box.width * box.width + box.height * box.height)
        if diagonal > 0, distance(raw[0], raw[raw.count - 1]) / diagonal < 0.25 { return false }

        let strideStep = max(1, raw.count / 16)
        var previousSign: CGFloat = 0
        var signChanges = 0
        var i = strideStep
        while i < raw.count {
            let delta = raw[i].x - raw[i - strideStep].x
            let sign: CGFloat = delta > 0 ? 1 : (delta < 0 ? -1 : 0)
            if sign != 0 {
                if previousSign != 0 && sign != previousSign { signChanges += 1 }
                previousSign = sign
            }
            i += strideStep
        }
        return signChanges >= 2
    }

    private func estimatedLoopCount(_ raw: [CGPoint]) -> CGFloat {
        guard raw.count >= 6 else { return 0 }
        let box = boundingBox(raw)
        let a = max(box.width * 0.5, 1)
        let b = max(box.height * 0.5, 1)
        let ellipseCircumference = .pi * (3 * (a + b) - sqrt((3 * a + b) * (a + 3 * b)))
        guard ellipseCircumference > 1 else { return 0 }
        return pathLength(raw) / ellipseCircumference
    }

    private func resample(_ points: [CGPoint], n: Int) -> [CGPoint] {
        guard points.count > 1 else { return points }
        let interval = pathLength(points) / CGFloat(n - 1)
        guard interval > 0 else { return points }

        var distanceAccumulator: CGFloat = 0
        var newPoints: [CGPoint] = [points[0]]
        var working = points
        var i = 1

        while i < working.count {
            let segmentLength = distance(working[i - 1], working[i])
            if segmentLength == 0 {
                i += 1
                continue
            }

            if distanceAccumulator + segmentLength >= interval {
                let t = (interval - distanceAccumulator) / segmentLength
                let interpolated = CGPoint(
                    x: working[i - 1].x + t * (working[i].x - working[i - 1].x),
                    y: working[i - 1].y + t * (working[i].y - working[i - 1].y)
                )
                newPoints.append(interpolated)
                working.insert(interpolated, at: i)
                distanceAccumulator = 0
                i += 1
            } else {
                distanceAccumulator += segmentLength
                i += 1
            }
        }

        while newPoints.count < n, let last = working.last {
            newPoints.append(last)
        }
        if newPoints.count > n {
            newPoints = Array(newPoints.prefix(n))
        }
        return newPoints
    }

    private func rotateToIndicativeAngle(_ points: [CGPoint]) -> [CGPoint] {
        guard let first = points.first else { return points }
        let c = centroid(points)
        let theta = atan2(first.y - c.y, first.x - c.x)
        return rotate(points, by: -theta, around: c)
    }

    private func rotate(_ points: [CGPoint], by radians: CGFloat, around center: CGPoint) -> [CGPoint] {
        points.map { p in
            let translatedX = p.x - center.x
            let translatedY = p.y - center.y
            let x = translatedX * cos(radians) - translatedY * sin(radians) + center.x
            let y = translatedX * sin(radians) + translatedY * cos(radians) + center.y
            return CGPoint(x: x, y: y)
        }
    }

    private func scaleToSquare(_ points: [CGPoint], size: CGFloat) -> [CGPoint] {
        let box = boundingBox(points)
        let scale = max(box.width, box.height)
        guard scale > 0 else { return points }
        return points.map {
            CGPoint(
                x: ($0.x - box.minX) / scale * size,
                y: ($0.y - box.minY) / scale * size
            )
        }
    }

    private func translateToOrigin(_ points: [CGPoint]) -> [CGPoint] {
        let c = centroid(points)
        return points.map { CGPoint(x: $0.x - c.x, y: $0.y - c.y) }
    }

    private func pathDistance(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat {
        guard a.count == b.count, !a.isEmpty else { return .greatestFiniteMagnitude }
        var total: CGFloat = 0
        for index in 0..<a.count {
            total += distance(a[index], b[index])
        }
        return total / CGFloat(a.count)
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var total: CGFloat = 0
        for i in 1..<points.count {
            total += distance(points[i - 1], points[i])
        }
        return total
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for p in points {
            sumX += p.x
            sumY += p.y
        }
        return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
    }

    private func vector(from a: CGPoint, to b: CGPoint) -> CGVector {
        CGVector(dx: b.x - a.x, dy: b.y - a.y)
    }

    private func cornerCount(_ points: [CGPoint]) -> Int {
        guard points.count >= 3 else { return 0 }
        let sampled = sampledPoints(points, stride: max(1, points.count / 24))
        guard sampled.count >= 3 else { return 0 }

        var count = 0
        for i in 1..<(sampled.count - 1) {
            let v1 = vector(from: sampled[i - 1], to: sampled[i])
            let v2 = vector(from: sampled[i], to: sampled[i + 1])

            let l1 = sqrt(v1.dx * v1.dx + v1.dy * v1.dy)
            let l2 = sqrt(v2.dx * v2.dx + v2.dy * v2.dy)
            if l1 < 0.1 || l2 < 0.1 { continue }

            let dot = v1.dx * v2.dx + v1.dy * v2.dy
            let normalizedDot = max(-1, min(1, dot / (l1 * l2)))
            let angle = acos(normalizedDot)
            if angle > (.pi / 4) { count += 1 }
        }

        return count
    }

    private func sampledPoints(_ points: [CGPoint], stride: Int) -> [CGPoint] {
        var output: [CGPoint] = []
        var index = 0
        while index < points.count {
            output.append(points[index])
            index += stride
        }
        if let last = points.last, output.last != last {
            output.append(last)
        }
        return output
    }

    private func totalTurningAngle(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for i in 2..<points.count {
            let v1 = vector(from: points[i - 2], to: points[i - 1])
            let v2 = vector(from: points[i - 1], to: points[i])
            let a1 = atan2(v1.dy, v1.dx)
            let a2 = atan2(v2.dy, v2.dx)
            var delta = a2 - a1
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            sum += abs(delta)
        }
        return sum
    }

    private func boundingBox(_ points: [CGPoint]) -> (minX: CGFloat, minY: CGFloat, width: CGFloat, height: CGFloat) {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for p in points {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }

        return (minX, minY, maxX - minX, maxY - minY)
    }

    private static func rawTemplates() -> [PadGestureTemplate] {
        func interpolatedLine(from: CGPoint, to: CGPoint, steps: Int = 24) -> [CGPoint] {
            guard steps > 0 else { return [from, to] }
            return (0...steps).map { i in
                let t = CGFloat(i) / CGFloat(steps)
                return CGPoint(
                    x: from.x + (to.x - from.x) * t,
                    y: from.y + (to.y - from.y) * t
                )
            }
        }

        func polyline(_ controlPoints: [CGPoint], stepsPerSegment: Int = 18) -> [CGPoint] {
            guard controlPoints.count >= 2 else { return controlPoints }
            var output: [CGPoint] = []
            for index in 1..<controlPoints.count {
                let segment = interpolatedLine(from: controlPoints[index - 1], to: controlPoints[index], steps: stepsPerSegment)
                if output.isEmpty {
                    output.append(contentsOf: segment)
                } else {
                    output.append(contentsOf: segment.dropFirst())
                }
            }
            return output
        }

        func circle(loopCount: Int, clockwise: Bool, segmentsPerLoop: Int = 64) -> [CGPoint] {
            let center = CGPoint(x: 125, y: 125)
            let radius: CGFloat = 72

            return (0...(segmentsPerLoop * loopCount)).map { i in
                let t = CGFloat(i) / CGFloat(segmentsPerLoop * loopCount)
                let radians = t * 2 * .pi * CGFloat(loopCount) * (clockwise ? -1 : 1)
                return CGPoint(
                    x: center.x + radius * cos(radians),
                    y: center.y + radius * sin(radians)
                )
            }
        }

        let left = interpolatedLine(from: CGPoint(x: 220, y: 120), to: CGPoint(x: 30, y: 120))
        let right = interpolatedLine(from: CGPoint(x: 30, y: 120), to: CGPoint(x: 220, y: 120))
        let lShape = polyline([
            CGPoint(x: 50, y: 210),
            CGPoint(x: 50, y: 50),
            CGPoint(x: 210, y: 50)
        ])
        let llShapeA = polyline([
            CGPoint(x: 35, y: 210),
            CGPoint(x: 35, y: 50),
            CGPoint(x: 105, y: 50),
            CGPoint(x: 105, y: 210),
            CGPoint(x: 105, y: 50),
            CGPoint(x: 220, y: 50)
        ])
        let llShapeB = polyline([
            CGPoint(x: 35, y: 210),
            CGPoint(x: 35, y: 50),
            CGPoint(x: 120, y: 50),
            CGPoint(x: 165, y: 210),
            CGPoint(x: 165, y: 50),
            CGPoint(x: 225, y: 50)
        ])
        let uShape = polyline([
            CGPoint(x: 45, y: 210),
            CGPoint(x: 45, y: 55),
            CGPoint(x: 205, y: 55),
            CGPoint(x: 205, y: 210)
        ])
        let upRight = polyline([
            CGPoint(x: 125, y: 30),
            CGPoint(x: 125, y: 220),
            CGPoint(x: 220, y: 220)
        ])
        let upLeft = polyline([
            CGPoint(x: 125, y: 30),
            CGPoint(x: 125, y: 220),
            CGPoint(x: 30, y: 220)
        ])
        let downLeft = polyline([
            CGPoint(x: 125, y: 220),
            CGPoint(x: 125, y: 35),
            CGPoint(x: 30, y: 35)
        ])
        let downRight = polyline([
            CGPoint(x: 125, y: 220),
            CGPoint(x: 125, y: 35),
            CGPoint(x: 220, y: 35)
        ])
        let downRightDownRight = polyline([
            CGPoint(x: 70, y: 220),
            CGPoint(x: 70, y: 120),
            CGPoint(x: 150, y: 120),
            CGPoint(x: 150, y: 35),
            CGPoint(x: 230, y: 35)
        ])
        let sShapeA = polyline([
            CGPoint(x: 40, y: 210),
            CGPoint(x: 95, y: 230),
            CGPoint(x: 170, y: 190),
            CGPoint(x: 210, y: 145),
            CGPoint(x: 140, y: 115),
            CGPoint(x: 75, y: 85),
            CGPoint(x: 30, y: 35)
        ])
        let sShapeB = polyline([
            CGPoint(x: 210, y: 210),
            CGPoint(x: 150, y: 235),
            CGPoint(x: 90, y: 190),
            CGPoint(x: 45, y: 145),
            CGPoint(x: 110, y: 110),
            CGPoint(x: 165, y: 80),
            CGPoint(x: 210, y: 35)
        ])

        return [
            PadGestureTemplate(name: "Left", points: left),
            PadGestureTemplate(name: "Right", points: right),
            PadGestureTemplate(name: "L", points: lShape),
            PadGestureTemplate(name: "LL", points: llShapeA),
            PadGestureTemplate(name: "LL", points: llShapeB),
            PadGestureTemplate(name: "U", points: uShape),
            PadGestureTemplate(name: "O", points: circle(loopCount: 1, clockwise: true)),
            PadGestureTemplate(name: "O", points: circle(loopCount: 1, clockwise: false)),
            PadGestureTemplate(name: "OO", points: circle(loopCount: 2, clockwise: true)),
            PadGestureTemplate(name: "OO", points: circle(loopCount: 2, clockwise: false)),
            PadGestureTemplate(name: "UpRight", points: upRight),
            PadGestureTemplate(name: "UpLeft", points: upLeft),
            PadGestureTemplate(name: "DownLeft", points: downLeft),
            PadGestureTemplate(name: "DownRight", points: downRight),
            PadGestureTemplate(name: "DownRightDownRight", points: downRightDownRight),
            PadGestureTemplate(name: "S", points: sShapeA),
            PadGestureTemplate(name: "S", points: sShapeB)
        ]
    }
}

struct PadGestureHUD: View {
    let state: PadGestureHUDState

    var body: some View {
        Image(systemName: state.systemImageName)
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(Color.primary)
            .frame(width: 138, height: 138)
            .background(PadLiquidGlassBackground(cornerRadius: 22))
            .mask(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .frame(width: 138, height: 138)
            )
            .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
    }
}

struct PadLiquidGlassBackground: View {
    var cornerRadius: CGFloat = 0

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.001))
                    .glassEffect()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }
}

struct PadLiquidGlassCapsuleBackground: View {
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Capsule()
                    .fill(Color.white.opacity(0.001))
                    .glassEffect()
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
        }
    }
}
