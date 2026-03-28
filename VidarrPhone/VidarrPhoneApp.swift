import SwiftUI
import UIKit

@main
final class VidarrPhoneAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = VidarrPhoneSceneDelegate.self
        return configuration
    }
}

final class VidarrPhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = VidarrPhoneHostingController(rootView: PadBrowserRootView())
        window.backgroundColor = .systemBackground
        self.window = window
        window.makeKeyAndVisible()
    }
}

final class VidarrPhoneHostingController<Content: View>: UIHostingController<Content> {
    override var prefersStatusBarHidden: Bool { true }

    override var childForStatusBarHidden: UIViewController? { nil }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.top, .bottom] }

    override var prefersHomeIndicatorAutoHidden: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.insetsLayoutMarginsFromSafeArea = false
    }
}
