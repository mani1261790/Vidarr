import Cocoa

final class GestureHUDView: NSView {
    private let textField = NSTextField(labelWithString: "")
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

    func showLiveCandidate(name: String, score: CGFloat, at point: CGPoint) {
        position(near: point)
        textField.stringValue = "\(name)  \(String(format: "%.2f", score))"
        alphaValue = 1
        isHidden = false
    }

    func showCommittedAction(name: String, score: CGFloat, at point: CGPoint, duration: TimeInterval = 0.3) {
        position(near: point)
        textField.stringValue = "\(name)  \(String(format: "%.2f", score))"
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
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true

        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.82).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        layer?.borderWidth = 1

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        textField.textColor = .labelColor
        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func position(near point: CGPoint) {
        frame.origin = CGPoint(x: point.x + 12, y: point.y - frame.height - 12)
    }
}
