import Cocoa

final class GestureHUDView: NSView {
    private struct Descriptor {
        let actionTitle: String
        let gestureHint: String
        let symbolName: String
        let tint: NSColor
    }

    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let hintField = NSTextField(labelWithString: "")
    private let capsuleLayer = CALayer()
    private let strokeLayer = CALayer()
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

    func showLiveCandidate(name: String, score: CGFloat, at _: CGPoint) {
        apply(descriptor: descriptor(for: name), committed: false, score: score)
        positionInCenter()
        alphaValue = 1
        isHidden = false
    }

    func showCommittedAction(name: String, score: CGFloat, at _: CGPoint, duration: TimeInterval = 0.3) {
        apply(descriptor: descriptor(for: name), committed: true, score: score)
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

    private func setupView() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = true
        isHidden = true

        layer?.cornerRadius = 16
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.76).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor
        layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.65).cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        capsuleLayer.cornerRadius = 28
        capsuleLayer.backgroundColor = NSColor.white.withAlphaComponent(0.20).cgColor
        strokeLayer.cornerRadius = 28
        strokeLayer.borderWidth = 1
        strokeLayer.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        layer?.addSublayer(capsuleLayer)
        layer?.addSublayer(strokeLayer)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleField.textColor = NSColor.labelColor
        addSubview(titleField)

        hintField.translatesAutoresizingMaskIntoConstraints = false
        hintField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        hintField.textColor = NSColor.secondaryLabelColor
        addSubview(hintField)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 56),
            iconView.heightAnchor.constraint(equalToConstant: 56),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 16),

            hintField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            hintField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            hintField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 6)
        ])
    }

    override func layout() {
        super.layout()
        let capsuleRect = CGRect(x: 8, y: bounds.midY - 28, width: 56, height: 56)
        capsuleLayer.frame = capsuleRect
        strokeLayer.frame = capsuleRect
    }

    private func apply(descriptor: Descriptor, committed: Bool, score: CGFloat) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        let image = NSImage(systemSymbolName: descriptor.symbolName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "questionmark.circle.fill", accessibilityDescription: nil)
        iconView.image = image?.withSymbolConfiguration(configuration)
        iconView.contentTintColor = descriptor.tint

        titleField.stringValue = descriptor.actionTitle + (committed ? " 実行" : " 候補")
        hintField.stringValue = descriptor.gestureHint + "    score \(String(format: "%.2f", score))"
    }

    private func positionInCenter() {
        guard let superview else { return }
        let size = NSSize(width: 340, height: 92)
        let x = (superview.bounds.width - size.width) * 0.5
        let y = (superview.bounds.height - size.height) * 0.5
        frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func descriptor(for name: String) -> Descriptor {
        switch name {
        case "Left":
            return Descriptor(actionTitle: "次のタブへ切り替え", gestureHint: "ジェスチャー  ←", symbolName: "arrow.right.circle.fill", tint: .systemCyan)
        case "Right":
            return Descriptor(actionTitle: "前のタブへ切り替え", gestureHint: "ジェスチャー  →", symbolName: "arrow.left.circle.fill", tint: .systemCyan)
        case "L":
            return Descriptor(actionTitle: "現在タブを閉じる", gestureHint: "ジェスチャー  L", symbolName: "xmark.square.fill", tint: .systemOrange)
        case "LL":
            return Descriptor(actionTitle: "全タブを閉じる", gestureHint: "ジェスチャー  LL", symbolName: "trash.circle.fill", tint: .systemRed)
        case "U":
            return Descriptor(actionTitle: "閉じたタブを復元", gestureHint: "ジェスチャー  U", symbolName: "arrow.uturn.backward.circle.fill", tint: .systemGreen)
        case "O":
            return Descriptor(actionTitle: "現在タブを再読み込み", gestureHint: "ジェスチャー  O", symbolName: "arrow.clockwise.circle.fill", tint: .systemBlue)
        case "OO":
            return Descriptor(actionTitle: "全タブを再読み込み", gestureHint: "ジェスチャー  OO", symbolName: "arrow.triangle.2.circlepath.circle.fill", tint: .systemBlue)
        case "UpRight":
            return Descriptor(actionTitle: "戻る", gestureHint: "ジェスチャー  ↑→", symbolName: "chevron.backward.circle.fill", tint: .systemPurple)
        case "UpLeft":
            return Descriptor(actionTitle: "進む", gestureHint: "ジェスチャー  ↑←", symbolName: "chevron.forward.circle.fill", tint: .systemPurple)
        case "S":
            return Descriptor(actionTitle: "検索 / URL入力", gestureHint: "ジェスチャー  S", symbolName: "magnifyingglass.circle.fill", tint: .systemTeal)
        case "DownLeft":
            return Descriptor(actionTitle: "新しいタブを開く", gestureHint: "ジェスチャー  ↓←", symbolName: "plus.square.on.square", tint: .systemIndigo)
        default:
            return Descriptor(actionTitle: "アクション", gestureHint: "ジェスチャー  ?", symbolName: "questionmark.circle.fill", tint: .systemGray)
        }
    }
}
