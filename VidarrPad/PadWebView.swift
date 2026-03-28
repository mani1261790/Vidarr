import SwiftUI
import WebKit

struct PadTabTransitionVisualState: Equatable {
    var fromX: CGFloat
    var toX: CGFloat
    var fromAlpha: CGFloat
    var toAlpha: CGFloat
    var dimAlpha: CGFloat
    var gapAlpha: CGFloat
    var toShadowOpacity: Float

    static let identity = PadTabTransitionVisualState(
        fromX: 0,
        toX: 0,
        fromAlpha: 1,
        toAlpha: 1,
        dimAlpha: 0,
        gapAlpha: 0,
        toShadowOpacity: 0
    )
}

struct PadWebStageView: UIViewRepresentable {
    let selectedWebView: WKWebView?
    let transitionFromWebView: WKWebView?
    let transitionToWebView: WKWebView?
    let transitionVisualState: PadTabTransitionVisualState?
    var gestureConfiguration: PadGestureConfiguration? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        context.coordinator.containerView = view
        context.coordinator.installChromeIfNeeded(in: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.containerView = uiView
        context.coordinator.installChromeIfNeeded(in: uiView)
        context.coordinator.update(
            selectedWebView: selectedWebView,
            transitionFromWebView: transitionFromWebView,
            transitionToWebView: transitionToWebView,
            transitionVisualState: transitionVisualState,
            gestureConfiguration: gestureConfiguration
        )
    }

    final class Coordinator {
        weak var containerView: UIView?
        private weak var attachedGestureView: UIView?
        private var panRecognizer: UIPanGestureRecognizer?
        private var gestureCoordinator: PadGestureCaptureCoordinator?
        private let dimView = UIView()
        private let gapView = UIView()
        private weak var activeFromWebView: WKWebView?
        private weak var activeToWebView: WKWebView?
        private weak var activeSelectedWebView: WKWebView?

        func installChromeIfNeeded(in container: UIView) {
            if dimView.superview == nil {
                dimView.backgroundColor = .black
                dimView.isUserInteractionEnabled = false
                dimView.alpha = 0
                container.addSubview(dimView)
            }
            if gapView.superview == nil {
                gapView.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.96)
                gapView.layer.cornerRadius = 9
                gapView.layer.cornerCurve = .continuous
                gapView.layer.borderWidth = 1
                gapView.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
                gapView.layer.shadowColor = UIColor.black.withAlphaComponent(0.12).cgColor
                gapView.layer.shadowRadius = 10
                gapView.layer.shadowOpacity = 1
                gapView.layer.shadowOffset = .zero
                gapView.isHidden = true
                gapView.isUserInteractionEnabled = false
                container.addSubview(gapView)
            }
        }

        func update(
            selectedWebView: WKWebView?,
            transitionFromWebView: WKWebView?,
            transitionToWebView: WKWebView?,
            transitionVisualState: PadTabTransitionVisualState?,
            gestureConfiguration: PadGestureConfiguration?
        ) {
            guard let containerView else { return }
            let bounds = containerView.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }

            if let fromWebView = transitionFromWebView,
               let toWebView = transitionToWebView,
               let visualState = transitionVisualState
            {
                activeSelectedWebView = nil
                ensureSubview(fromWebView, in: containerView)
                ensureSubview(toWebView, in: containerView)
                containerView.sendSubviewToBack(toWebView)
                containerView.bringSubviewToFront(fromWebView)
                containerView.bringSubviewToFront(dimView)
                containerView.bringSubviewToFront(gapView)

                let gap = gapView.bounds.width > 0 ? gapView.bounds.width : CGFloat(16)
                fromWebView.frame = bounds.offsetBy(dx: visualState.fromX, dy: 0)
                toWebView.frame = bounds.offsetBy(dx: visualState.toX, dy: 0)

                dimView.isHidden = visualState.dimAlpha <= 0.001
                dimView.frame = bounds
                dimView.alpha = visualState.dimAlpha

                let direction = visualState.toX >= 0 ? CGFloat(1) : CGFloat(-1)
                let fromEdge = visualState.fromX + (direction > 0 ? bounds.width : 0)
                let toEdge = visualState.toX + (direction > 0 ? 0 : bounds.width)
                let gapX = ((fromEdge + toEdge) * 0.5) - (gap * 0.5)
                gapView.isHidden = visualState.gapAlpha <= 0.001
                gapView.alpha = visualState.gapAlpha
                gapView.frame = CGRect(x: gapX, y: 0, width: gap, height: bounds.height)

                fromWebView.alpha = visualState.fromAlpha
                toWebView.alpha = visualState.toAlpha
                toWebView.layer.shadowColor = UIColor.black.withAlphaComponent(0.14).cgColor
                toWebView.layer.shadowRadius = 16
                toWebView.layer.shadowOpacity = visualState.toShadowOpacity
                toWebView.layer.shadowOffset = CGSize(width: 0, height: 4)
                toWebView.layer.masksToBounds = false
                toWebView.layer.cornerRadius = 18
                toWebView.layer.cornerCurve = .continuous
                toWebView.layer.borderWidth = 1.2
                toWebView.layer.borderColor = UIColor.white.withAlphaComponent(0.26).cgColor
                fromWebView.layer.cornerRadius = 18
                fromWebView.layer.cornerCurve = .continuous
                fromWebView.layer.masksToBounds = true
                toWebView.layer.masksToBounds = false

                activeFromWebView = fromWebView
                activeToWebView = toWebView
                configureGestureRecognizer(for: fromWebView, configuration: gestureConfiguration)
                cleanupDetachedViews(keeping: [fromWebView, toWebView])
            } else if let selectedWebView {
                activeFromWebView = nil
                activeToWebView = nil
                activeSelectedWebView = selectedWebView
                ensureSubview(selectedWebView, in: containerView)
                selectedWebView.frame = bounds
                selectedWebView.layer.shadowOpacity = 0
                selectedWebView.alpha = 1
                selectedWebView.layer.cornerRadius = 0
                selectedWebView.layer.borderWidth = 0
                dimView.isHidden = true
                gapView.isHidden = true
                dimView.alpha = 0
                gapView.alpha = 0
                configureGestureRecognizer(for: selectedWebView, configuration: gestureConfiguration)
                cleanupDetachedViews(keeping: [selectedWebView])
            } else {
                activeFromWebView = nil
                activeToWebView = nil
                activeSelectedWebView = nil
                configureGestureRecognizer(for: nil, configuration: nil)
                cleanupDetachedViews(keeping: [])
                dimView.isHidden = true
                gapView.isHidden = true
                dimView.alpha = 0
                gapView.alpha = 0
            }
        }

        private func ensureSubview(_ webView: WKWebView, in container: UIView) {
            if webView.superview !== container {
                webView.removeFromSuperview()
                webView.frame = container.bounds
                container.addSubview(webView)
            }
        }

        private func cleanupDetachedViews(keeping webViews: [WKWebView]) {
            let keepSet = Set(webViews.map(ObjectIdentifier.init))
            for subview in containerView?.subviews ?? [] {
                guard let webView = subview as? WKWebView else { continue }
                if !keepSet.contains(ObjectIdentifier(webView)) {
                    webView.removeFromSuperview()
                }
            }
            containerView?.bringSubviewToFront(dimView)
            containerView?.bringSubviewToFront(gapView)
        }

        private func configureGestureRecognizer(for webView: WKWebView?, configuration: PadGestureConfiguration?) {
            guard let configuration, let webView else {
                if let panRecognizer, let attachedGestureView {
                    attachedGestureView.removeGestureRecognizer(panRecognizer)
                }
                attachedGestureView = nil
                panRecognizer = nil
                gestureCoordinator = nil
                return
            }

            let coordinator: PadGestureCaptureCoordinator
            if let gestureCoordinator {
                gestureCoordinator.update(configuration: configuration)
                coordinator = gestureCoordinator
            } else {
                coordinator = PadGestureCaptureCoordinator(
                    sensitivity: configuration.sensitivity,
                    onPreview: configuration.onPreview,
                    onHorizontalSwipeDrag: configuration.onHorizontalSwipeDrag,
                    onHorizontalSwipeFinish: configuration.onHorizontalSwipeFinish,
                    onHorizontalSwipeCancel: configuration.onHorizontalSwipeCancel,
                    onCommit: configuration.onCommit,
                    onCancel: configuration.onCancel
                )
                gestureCoordinator = coordinator
            }

            let recognizer: UIPanGestureRecognizer
            if let panRecognizer {
                recognizer = panRecognizer
            } else {
                recognizer = UIPanGestureRecognizer(target: coordinator, action: #selector(PadGestureCaptureCoordinator.handlePan(_:)))
                recognizer.minimumNumberOfTouches = 1
                recognizer.maximumNumberOfTouches = 1
                recognizer.cancelsTouchesInView = false
                recognizer.delaysTouchesBegan = false
                recognizer.delaysTouchesEnded = false
                recognizer.delegate = coordinator
                panRecognizer = recognizer
            }

            if attachedGestureView !== webView {
                attachedGestureView?.removeGestureRecognizer(recognizer)
                webView.addGestureRecognizer(recognizer)
                attachedGestureView = webView
            }
        }
    }
}
