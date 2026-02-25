import Cocoa

final class GestureHUDView: NSView {
    private struct Descriptor {
        let actionSymbol: String
    }

    private let actionIconView = NSImageView()
    private let cardLayer = CALayer()
    private let borderLayer = CALayer()
    private let iconCapsuleLayer = CALayer()
    private let gestureShadowLayer = CAShapeLayer()
    private let gestureLayer = CAShapeLayer()
    private var hideWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    override var isOpaque: Bool { false }

    func showLiveCandidate(name: String, score _: CGFloat, at _: CGPoint) {
        apply(name: name, committed: false)
        positionInCenter()
        alphaValue = 1
        isHidden = false
    }

    func showCommittedAction(name: String, score _: CGFloat, at _: CGPoint, duration: TimeInterval = 0.3) {
        apply(name: name, committed: true)
        positionInCenter()
        alphaValue = 1
        isHidden = false

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hideImmediately()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    func hideImmediately() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        isHidden = true
    }

    override func layout() {
        super.layout()

        cardLayer.frame = bounds
        borderLayer.frame = bounds

        let iconCapsuleRect = CGRect(x: bounds.width - 170, y: bounds.midY - 65, width: 130, height: 130)
        iconCapsuleLayer.frame = iconCapsuleRect
        iconCapsuleLayer.cornerRadius = iconCapsuleRect.height * 0.5

        actionIconView.frame = CGRect(
            x: iconCapsuleRect.midX - 42,
            y: iconCapsuleRect.midY - 42,
            width: 84,
            height: 84
        )
        updateGesturePath()
    }

    private func setupView() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = true
        isHidden = true

        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(cardLayer)
        layer?.addSublayer(borderLayer)
        layer?.addSublayer(iconCapsuleLayer)
        layer?.addSublayer(gestureShadowLayer)
        layer?.addSublayer(gestureLayer)

        cardLayer.cornerRadius = 24
        cardLayer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.80).cgColor
        cardLayer.shadowColor = NSColor.black.withAlphaComponent(0.7).cgColor
        cardLayer.shadowOpacity = 0.34
        cardLayer.shadowRadius = 24
        cardLayer.shadowOffset = CGSize(width: 0, height: -2)

        borderLayer.cornerRadius = 24
        borderLayer.borderWidth = 1
        borderLayer.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor

        iconCapsuleLayer.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        iconCapsuleLayer.borderWidth = 1
        iconCapsuleLayer.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor

        gestureShadowLayer.fillColor = NSColor.clear.cgColor
        gestureShadowLayer.strokeColor = NSColor.black.withAlphaComponent(0.45).cgColor
        gestureShadowLayer.lineWidth = 12
        gestureShadowLayer.lineCap = .round
        gestureShadowLayer.lineJoin = .round

        gestureLayer.fillColor = NSColor.clear.cgColor
        gestureLayer.strokeColor = NSColor.labelColor.withAlphaComponent(0.96).cgColor
        gestureLayer.lineWidth = 7
        gestureLayer.lineCap = .round
        gestureLayer.lineJoin = .round

        actionIconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(actionIconView)
    }

    private func apply(name: String, committed: Bool) {
        let descriptor = descriptor(for: name)
        let iconConfig = NSImage.SymbolConfiguration(pointSize: committed ? 64 : 60, weight: .bold)
        let icon = NSImage(systemSymbolName: descriptor.actionSymbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        actionIconView.image = icon?.withSymbolConfiguration(iconConfig)
        actionIconView.contentTintColor = NSColor.labelColor.withAlphaComponent(committed ? 1.0 : 0.86)

        gestureLayer.opacity = committed ? 1.0 : 0.82
        borderLayer.borderColor = NSColor.white.withAlphaComponent(committed ? 0.40 : 0.28).cgColor
        cardLayer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(committed ? 0.86 : 0.80).cgColor

        if committed {
            animateCommitPop()
        }
        currentGestureName = name
        updateGesturePath()
    }

    private var currentGestureName: String = ""

    private func positionInCenter() {
        guard let superview else { return }
        let size = NSSize(width: 560, height: 290)
        let x = (superview.bounds.width - size.width) * 0.5
        let y = (superview.bounds.height - size.height) * 0.5
        frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func gestureRect() -> CGRect {
        CGRect(x: 34, y: 40, width: 340, height: 210)
    }

    private func updateGesturePath() {
        let path = path(for: currentGestureName, in: gestureRect()).cgPath
        gestureLayer.path = path
        gestureShadowLayer.path = path
    }

    private func animateCommitPop() {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.96
        scale.toValue = 1.0
        scale.duration = 0.14
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(scale, forKey: "hudPop")
    }

    private func descriptor(for name: String) -> Descriptor {
        switch name {
        case "Left":
            return Descriptor(actionSymbol: "arrow.right.circle.fill")
        case "Right":
            return Descriptor(actionSymbol: "arrow.left.circle.fill")
        case "L":
            return Descriptor(actionSymbol: "xmark.square.fill")
        case "LL":
            return Descriptor(actionSymbol: "trash.circle.fill")
        case "U":
            return Descriptor(actionSymbol: "arrow.uturn.backward.circle.fill")
        case "O":
            return Descriptor(actionSymbol: "arrow.clockwise.circle.fill")
        case "OO":
            return Descriptor(actionSymbol: "arrow.triangle.2.circlepath.circle.fill")
        case "UpRight":
            return Descriptor(actionSymbol: "chevron.backward.circle.fill")
        case "UpLeft":
            return Descriptor(actionSymbol: "chevron.forward.circle.fill")
        case "S":
            return Descriptor(actionSymbol: "magnifyingglass.circle.fill")
        case "DownLeft":
            return Descriptor(actionSymbol: "plus.square.on.square")
        default:
            return Descriptor(actionSymbol: "questionmark.circle")
        }
    }

    private func path(for name: String, in rect: CGRect) -> NSBezierPath {
        switch name {
        case "Left":
            return arrowPath(in: rect, from: CGPoint(x: 0.9, y: 0.5), to: CGPoint(x: 0.1, y: 0.5))
        case "Right":
            return arrowPath(in: rect, from: CGPoint(x: 0.1, y: 0.5), to: CGPoint(x: 0.9, y: 0.5))
        case "L":
            return polylinePath(in: rect, points: [CGPoint(x: 0.18, y: 0.82), CGPoint(x: 0.18, y: 0.2), CGPoint(x: 0.82, y: 0.2)])
        case "LL":
            return polylinePath(in: rect, points: [
                CGPoint(x: 0.12, y: 0.82), CGPoint(x: 0.12, y: 0.2), CGPoint(x: 0.38, y: 0.2),
                CGPoint(x: 0.38, y: 0.82), CGPoint(x: 0.38, y: 0.2), CGPoint(x: 0.84, y: 0.2)
            ])
        case "U":
            return polylinePath(in: rect, points: [
                CGPoint(x: 0.18, y: 0.8), CGPoint(x: 0.18, y: 0.26), CGPoint(x: 0.82, y: 0.26), CGPoint(x: 0.82, y: 0.8)
            ])
        case "O":
            return circlePath(in: rect, centerX: 0.5, centerY: 0.5, radius: 0.31)
        case "OO":
            let p = NSBezierPath()
            p.append(circlePath(in: rect, centerX: 0.37, centerY: 0.5, radius: 0.24))
            p.append(circlePath(in: rect, centerX: 0.67, centerY: 0.5, radius: 0.24))
            return p
        case "UpRight":
            return polylinePath(in: rect, points: [CGPoint(x: 0.5, y: 0.18), CGPoint(x: 0.5, y: 0.82), CGPoint(x: 0.84, y: 0.82)])
        case "UpLeft":
            return polylinePath(in: rect, points: [CGPoint(x: 0.5, y: 0.18), CGPoint(x: 0.5, y: 0.82), CGPoint(x: 0.16, y: 0.82)])
        case "S":
            return sCurvePath(in: rect)
        case "DownLeft":
            return polylinePath(in: rect, points: [CGPoint(x: 0.5, y: 0.82), CGPoint(x: 0.5, y: 0.18), CGPoint(x: 0.16, y: 0.18)])
        default:
            return NSBezierPath()
        }
    }

    private func arrowPath(in rect: CGRect, from: CGPoint, to: CGPoint) -> NSBezierPath {
        let path = NSBezierPath()
        let start = map(from, in: rect)
        let end = map(to, in: rect)
        path.move(to: start)
        path.line(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let head: CGFloat = 22
        let left = CGPoint(
            x: end.x - head * cos(angle - .pi / 6),
            y: end.y - head * sin(angle - .pi / 6)
        )
        let right = CGPoint(
            x: end.x - head * cos(angle + .pi / 6),
            y: end.y - head * sin(angle + .pi / 6)
        )
        path.move(to: end)
        path.line(to: left)
        path.move(to: end)
        path.line(to: right)
        return path
    }

    private func polylinePath(in rect: CGRect, points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: map(first, in: rect))
        for point in points.dropFirst() {
            path.line(to: map(point, in: rect))
        }
        return path
    }

    private func circlePath(in rect: CGRect, centerX: CGFloat, centerY: CGFloat, radius: CGFloat) -> NSBezierPath {
        let center = map(CGPoint(x: centerX, y: centerY), in: rect)
        let r = min(rect.width, rect.height) * radius
        return NSBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    private func sCurvePath(in rect: CGRect) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: map(CGPoint(x: 0.82, y: 0.84), in: rect))
        p.curve(
            to: map(CGPoint(x: 0.24, y: 0.58), in: rect),
            controlPoint1: map(CGPoint(x: 0.58, y: 0.92), in: rect),
            controlPoint2: map(CGPoint(x: 0.34, y: 0.72), in: rect)
        )
        p.curve(
            to: map(CGPoint(x: 0.78, y: 0.18), in: rect),
            controlPoint1: map(CGPoint(x: 0.1, y: 0.42), in: rect),
            controlPoint2: map(CGPoint(x: 0.56, y: 0.34), in: rect)
        )
        return p
    }

    private func map(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + rect.width * point.x,
            y: rect.minY + rect.height * point.y
        )
    }
}
