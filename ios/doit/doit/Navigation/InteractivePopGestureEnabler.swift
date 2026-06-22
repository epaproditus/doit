import SwiftUI
import UIKit

/// Re-enables UIKit's interactive pop gesture when the navigation bar is
/// hidden. SwiftUI's `NavigationStack` normally provides edge swipe-back,
/// but `.toolbar(.hidden, for: .navigationBar)` commonly disables it.
struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        PopGestureViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class PopGestureViewController: UIViewController {
    private weak var navigationControllerReference: UINavigationController?
    private let gestureDelegate = PopGestureRecognizerDelegate()

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let navigationController else { return }
        navigationControllerReference = navigationController
        navigationController.interactivePopGestureRecognizer?.isEnabled = true
        navigationController.interactivePopGestureRecognizer?.delegate = gestureDelegate
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard let navigationController = navigationControllerReference else { return }
        navigationController.interactivePopGestureRecognizer?.delegate = nil
    }
}

private final class PopGestureRecognizerDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController = gestureRecognizer.view?.nearestNavigationController else {
            return false
        }
        return navigationController.viewControllers.count > 1
    }
}

private extension UIView {
    var nearestNavigationController: UINavigationController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let navigationController = current as? UINavigationController {
                return navigationController
            }
            responder = current.next
        }
        return nil
    }
}

extension View {
    /// Enables the standard iOS left-edge swipe to pop this view from a
    /// `NavigationStack` when the system navigation bar is hidden.
    func interactivePopGestureEnabled() -> some View {
        background {
            InteractivePopGestureEnabler()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
