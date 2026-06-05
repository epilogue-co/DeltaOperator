//
//  DeltaOperatorToast.swift
//  DeltaOperator
//
//  A reusable toast presenter for operator status messages (writeback, loading, warnings).
//

import Roxas
import UIKit

/// Presents a single transient toast in a target view. Knows nothing about cartridge/save logic;
/// callers supply the text, the view, and how it dismisses.
final class DeltaOperatorToast {
    enum Dismissal {
        /// Stays until `dismiss()` is called.
        case manual
        /// Removes itself after `after` seconds.
        case auto(after: TimeInterval)
    }

    private static let minimumOnScreen: TimeInterval = 1.0
    private weak var toastView: RSTToastView?
    private var shownAt: Date?
    private var dismissWorkItem: DispatchWorkItem?

    /// Shows a toast, replacing any currently-visible one.
    ///
    /// - Parameters:
    ///   - text: The primary toast text.
    ///   - detail: Optional secondary text shown beneath `text`.
    ///   - view: The view to present the toast in.
    ///   - dismissal: Whether the toast stays until `dismiss()` or auto-removes after a delay.
    func show(text: String, detail: String? = nil, in view: UIView, dismissal: Dismissal = .manual) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        toastView?.dismiss()

        let toast = RSTToastView(text: text, detailText: detail)
        toast.textLabel.textAlignment = .center
        toast.presentationEdge = .top
        switch dismissal {
        case .manual: toast.show(in: view)
        case .auto(let after): toast.show(in: view, duration: after)
        }
        toastView = toast
        shownAt = Date()
    }

    /// Dismisses the current toast after `delay`, but never before `minimumOnScreen` has elapsed.
    ///
    /// - Parameter delay: Seconds to wait before dismissing (clamped up to honor `minimumOnScreen`).
    func dismiss(after delay: TimeInterval = 0) {
        guard toastView != nil else { return }
        let elapsed = shownAt.map { Date().timeIntervalSince($0) } ?? Self.minimumOnScreen
        let workItem = DispatchWorkItem { [weak self] in
            self?.toastView?.dismiss()
            self?.toastView = nil
            self?.shownAt = nil
            self?.dismissWorkItem = nil
        }
        dismissWorkItem?.cancel()
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, Self.minimumOnScreen - elapsed), execute: workItem)
    }
}
