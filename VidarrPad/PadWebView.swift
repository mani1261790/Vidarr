import SwiftUI
import WebKit

struct PadWebView: UIViewRepresentable {
    let webView: WKWebView
    var gestureConfiguration: PadGestureConfiguration? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.configureGestureRecognizer(for: webView, configuration: gestureConfiguration)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.configureGestureRecognizer(for: uiView, configuration: gestureConfiguration)
    }

    final class Coordinator {
        private weak var attachedView: UIView?
        private var panRecognizer: UIPanGestureRecognizer?
        private var gestureCoordinator: PadGestureCaptureCoordinator?

        func configureGestureRecognizer(for webView: WKWebView, configuration: PadGestureConfiguration?) {
            guard let configuration else {
                if let panRecognizer, let attachedView {
                    attachedView.removeGestureRecognizer(panRecognizer)
                }
                attachedView = nil
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

            if attachedView !== webView {
                attachedView?.removeGestureRecognizer(recognizer)
                webView.addGestureRecognizer(recognizer)
                attachedView = webView
            }
        }
    }
}
