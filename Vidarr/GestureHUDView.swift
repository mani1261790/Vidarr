import Cocoa

final class GestureHUDView: NSView {
    static let preferredSize = NSSize(width: 220, height: 220)

    private struct Descriptor {
        let actionSymbol: String
    }

    private let actionIconView = NSImageView()
    private let contentHostView = NSView()
    private var glassBackgroundView: NSView?
    private let fallbackCardLayer = CALayer()
    private let fallbackBorderLayer = CALayer()
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

        glassBackgroundView?.frame = bounds
        fallbackCardLayer.frame = bounds
        fallbackBorderLayer.frame = bounds

        let iconSide = bounds.width * 0.38
        actionIconView.frame = CGRect(
            x: bounds.midX - iconSide * 0.5,
            y: bounds.midY - iconSide * 0.5,
            width: iconSide,
            height: iconSide
        )
    }

    private func setupView() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = true
        isHidden = true

        layer?.backgroundColor = NSColor.clear.cgColor
        contentHostView.translatesAutoresizingMaskIntoConstraints = false

        layer?.addSublayer(fallbackCardLayer)
        layer?.addSublayer(fallbackBorderLayer)

        fallbackCardLayer.cornerRadius = 34
        fallbackCardLayer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.80).cgColor
        fallbackCardLayer.shadowColor = NSColor.black.withAlphaComponent(0.7).cgColor
        fallbackCardLayer.shadowOpacity = 0.34
        fallbackCardLayer.shadowRadius = 24
        fallbackCardLayer.shadowOffset = CGSize(width: 0, height: -2)

        fallbackBorderLayer.cornerRadius = 34
        fallbackBorderLayer.borderWidth = 1
        fallbackBorderLayer.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor

        addSubview(contentHostView)
        NSLayoutConstraint.activate([
            contentHostView.topAnchor.constraint(equalTo: topAnchor),
            contentHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentHostView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        actionIconView.imageScaling = .scaleProportionallyUpOrDown
        contentHostView.addSubview(actionIconView)
    }

    private func apply(name: String, committed: Bool) {
        let descriptor = descriptor(for: name)
        let iconConfig = NSImage.SymbolConfiguration(pointSize: committed ? 64 : 60, weight: .bold)
        let icon = NSImage(systemSymbolName: descriptor.actionSymbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        actionIconView.image = icon?.withSymbolConfiguration(iconConfig)
        actionIconView.contentTintColor = iconTintColor(committed: committed)

        fallbackBorderLayer.borderColor = NSColor.white.withAlphaComponent(committed ? 0.40 : 0.28).cgColor
        fallbackCardLayer.backgroundColor = fallbackBackgroundColor(committed: committed).cgColor

        if committed {
            animateCommitPop()
        }
    }

    private func iconTintColor(committed: Bool) -> NSColor {
        if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(committed ? 0.98 : 0.92)
        }
        return NSColor.labelColor.withAlphaComponent(committed ? 1.0 : 0.86)
    }

    private func fallbackBackgroundColor(committed: Bool) -> NSColor {
        if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.black.withAlphaComponent(committed ? 0.74 : 0.66)
        }
        return NSColor.windowBackgroundColor.withAlphaComponent(committed ? 0.86 : 0.80)
    }

    private func positionInCenter() {
        guard let superview else { return }
        let size = Self.preferredSize
        let x = (superview.bounds.width - size.width) * 0.5
        let y = (superview.bounds.height - size.height) * 0.5
        frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
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
        case "DownRight":
            return Descriptor(actionSymbol: "xmark.square.fill")
        case "DownRightDownRight":
            return Descriptor(actionSymbol: "trash.circle.fill")
        case "O":
            return Descriptor(actionSymbol: "arrow.clockwise.circle.fill")
        case "U":
            return Descriptor(actionSymbol: "arrow.uturn.backward.circle.fill")
        case "OO":
            return Descriptor(actionSymbol: "square.stack.3d.up.fill")
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
}
