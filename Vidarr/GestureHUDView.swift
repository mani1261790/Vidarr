import Cocoa

final class GestureHUDView: NSView {
    private struct Descriptor {
        let actionSymbol: String
    }

    private let actionIconView = NSImageView()
    private let cardLayer = CALayer()
    private let borderLayer = CALayer()
    private let iconCapsuleLayer = CALayer()
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

        let iconCapsuleRect = CGRect(x: bounds.midX - 65, y: bounds.midY - 65, width: 130, height: 130)
        iconCapsuleLayer.frame = iconCapsuleRect
        iconCapsuleLayer.cornerRadius = iconCapsuleRect.height * 0.5

        actionIconView.frame = CGRect(
            x: iconCapsuleRect.midX - 42,
            y: iconCapsuleRect.midY - 42,
            width: 84,
            height: 84
        )
    }

    private func setupView() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = true
        isHidden = true

        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(cardLayer)
        layer?.addSublayer(borderLayer)
        layer?.addSublayer(iconCapsuleLayer)

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

        borderLayer.borderColor = NSColor.white.withAlphaComponent(committed ? 0.40 : 0.28).cgColor
        cardLayer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(committed ? 0.86 : 0.80).cgColor

        if committed {
            animateCommitPop()
        }
    }

    private func positionInCenter() {
        guard let superview else { return }
        let size = NSSize(width: 560, height: 290)
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
}
