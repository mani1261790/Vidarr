import SwiftUI
import UIKit

enum PadGestureAction: String {
    case previousTab
    case nextTab
    case closeTab
    case closeAllTabs
    case restoreClosedTab
    case reload
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

struct PadGestureOverlay: UIViewRepresentable {
    let sensitivity: PadGestureSensitivity
    let onPreview: (PadGestureHUDState?) -> Void
    let onCommit: (PadGestureAction) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(sensitivity: sensitivity, onPreview: onPreview, onCommit: onCommit, onCancel: onCancel)
    }

    func makeUIView(context: Context) -> GestureCaptureView {
        let view = GestureCaptureView()
        let recognizer = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        recognizer.cancelsTouchesInView = true
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: GestureCaptureView, context: Context) {
        context.coordinator.sensitivity = sensitivity
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var sensitivity: PadGestureSensitivity
        private let onPreview: (PadGestureHUDState?) -> Void
        private let onCommit: (PadGestureAction) -> Void
        private let onCancel: () -> Void

        private var points: [CGPoint] = []
        private var lastPreviewAction: PadGestureAction?

        init(
            sensitivity: PadGestureSensitivity,
            onPreview: @escaping (PadGestureHUDState?) -> Void,
            onCommit: @escaping (PadGestureAction) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.sensitivity = sensitivity
            self.onPreview = onPreview
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let location = recognizer.location(in: recognizer.view)
            switch recognizer.state {
            case .began:
                points = [location]
                lastPreviewAction = nil
                onPreview(nil)
            case .changed:
                appendPoint(location)
                let pointsSnapshot = points
                guard let evaluation = evaluate(points: pointsSnapshot, sensitivity: sensitivity, final: false) else {
                    if lastPreviewAction != nil {
                        lastPreviewAction = nil
                        onPreview(nil)
                    }
                    return
                }
                if lastPreviewAction != evaluation.action || evaluation.confidence > 0.98 {
                    lastPreviewAction = evaluation.action
                    onPreview(PadGestureHUDState(
                        action: evaluation.action,
                        title: evaluation.title,
                        systemImageName: evaluation.systemImageName,
                        confidence: evaluation.confidence,
                        isCommitted: false
                    ))
                }
            case .ended:
                appendPoint(location)
                guard let evaluation = evaluate(points: points, sensitivity: sensitivity, final: true) else {
                    reset()
                    onCancel()
                    return
                }
                onPreview(PadGestureHUDState(
                    action: evaluation.action,
                    title: evaluation.title,
                    systemImageName: evaluation.systemImageName,
                    confidence: evaluation.confidence,
                    isCommitted: true
                ))
                onCommit(evaluation.action)
                reset()
            default:
                reset()
                onCancel()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }

        private func appendPoint(_ point: CGPoint) {
            if let last = points.last, hypot(point.x - last.x, point.y - last.y) < 4 {
                return
            }
            points.append(point)
        }

        private func reset() {
            points.removeAll()
            lastPreviewAction = nil
        }
    }
}

final class GestureCaptureView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct GestureEvaluation {
    let action: PadGestureAction
    let title: String
    let systemImageName: String
    let confidence: CGFloat
}

private enum GestureDirection: String {
    case left
    case right
    case up
    case down
    case upLeft
    case upRight
    case downLeft
    case downRight
}

private func evaluate(points: [CGPoint], sensitivity: PadGestureSensitivity, final: Bool) -> GestureEvaluation? {
    let minDistance = 48 / sensitivity.multiplier
    guard pathLength(points) >= minDistance else { return nil }
    let sequence = directionSequence(from: points, sensitivity: sensitivity)
    guard !sequence.isEmpty else { return nil }

    let candidates: [([GestureDirection], PadGestureAction, String, String)] = [
        ([.right], .nextTab, "Next Tab", "arrow.right.circle"),
        ([.left], .previousTab, "Previous Tab", "arrow.left.circle"),
        ([.downRight], .closeTab, "Close Tab", "xmark.circle"),
        ([.downRight, .downRight], .closeAllTabs, "Close All Tabs", "xmark.circle.fill"),
        ([.downRight, .up], .restoreClosedTab, "Restore Tab", "arrow.uturn.backward.circle"),
        ([.upRight, .downLeft], .reload, "Reload", "arrow.clockwise.circle"),
        ([.upRight], .back, "Back", "arrow.uturn.backward"),
        ([.upLeft], .forward, "Forward", "arrow.uturn.forward"),
        ([.left, .down, .right, .downLeft], .search, "Search", "magnifyingglass.circle"),
        ([.downLeft], .newTab, "New Tab", "plus.circle")
    ]

    var best: GestureEvaluation?
    for candidate in candidates {
        if let confidence = score(sequence: sequence, target: candidate.0, final: final) {
            let evaluation = GestureEvaluation(action: candidate.1, title: candidate.2, systemImageName: candidate.3, confidence: confidence)
            if best == nil || evaluation.confidence > best!.confidence {
                best = evaluation
            }
        }
    }

    guard let best else { return nil }
    let threshold: CGFloat = final ? 0.78 : 0.42
    return best.confidence >= threshold ? best : nil
}

private func score(sequence: [GestureDirection], target: [GestureDirection], final: Bool) -> CGFloat? {
    if final {
        guard sequence == target else { return nil }
        return 1.0
    }

    guard sequence.count <= target.count else { return nil }
    guard zip(sequence, target).allSatisfy({ $0 == $1 }) else { return nil }
    return CGFloat(sequence.count) / CGFloat(target.count)
}

private func directionSequence(from points: [CGPoint], sensitivity: PadGestureSensitivity) -> [GestureDirection] {
    let segmentThreshold = 18 / sensitivity.multiplier
    var sequence: [GestureDirection] = []
    var anchor = points.first ?? .zero
    var accumulated = CGPoint.zero

    for point in points.dropFirst() {
        accumulated.x += point.x - anchor.x
        accumulated.y += point.y - anchor.y
        anchor = point

        let length = hypot(accumulated.x, accumulated.y)
        guard length >= segmentThreshold else { continue }
        guard let direction = quantizeDirection(dx: accumulated.x, dy: accumulated.y) else { continue }
        if sequence.last != direction {
            sequence.append(direction)
        }
        accumulated = .zero
    }

    if sequence.count >= 3 {
        sequence = mergeNoisySegments(sequence)
    }
    return sequence
}

private func quantizeDirection(dx: CGFloat, dy: CGFloat) -> GestureDirection? {
    let absDX = abs(dx)
    let absDY = abs(dy)
    guard absDX > 0.1 || absDY > 0.1 else { return nil }

    let ratio = absDX / max(absDY, 0.001)
    if ratio >= 2.0 {
        return dx >= 0 ? .right : .left
    }
    if ratio <= 0.5 {
        return dy >= 0 ? .down : .up
    }

    switch (dx >= 0, dy >= 0) {
    case (true, true): return .downRight
    case (true, false): return .upRight
    case (false, true): return .downLeft
    case (false, false): return .upLeft
    }
}

private func mergeNoisySegments(_ sequence: [GestureDirection]) -> [GestureDirection] {
    var result: [GestureDirection] = []
    for direction in sequence {
        if result.last == direction { continue }
        if result.count >= 2, result[result.count - 2] == direction {
            result.removeLast()
            continue
        }
        result.append(direction)
    }
    return result
}

private func pathLength(_ points: [CGPoint]) -> CGFloat {
    guard points.count > 1 else { return 0 }
    return zip(points, points.dropFirst()).reduce(0) { partial, pair in
        partial + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
    }
}

struct PadGestureHUD: View {
    let state: PadGestureHUDState

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: state.systemImageName)
                .font(.system(size: 34, weight: .semibold))
            Text(state.title)
                .font(.system(size: 14, weight: .semibold))
            if !state.isCommitted {
                Text("\(Int(state.confidence * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .frame(minWidth: 170)
        .background(hudBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
    }

    @ViewBuilder
    private var hudBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.001))
                .glassEffect()
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        }
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
