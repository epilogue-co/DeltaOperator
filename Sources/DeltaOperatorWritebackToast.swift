//
//  DeltaOperatorWritebackToast.swift
//  DeltaOperator
//
//  Shows the "Saving to cartridge" toast during save writeback.
//

import OperatorKit
import UIKit

/// Shows the "Saving to cartridge" toast during writeback, ref-counted across overlapping writebacks.
final class DeltaOperatorWritebackToast {
    private static let toastText = NSLocalizedString("Saving to Cartridge", comment: "")
    private static let toastDetailText = NSLocalizedString("Do not remove the cartridge.", comment: "")
    private static let lingerAfterEnd: TimeInterval = 2.0

    private let toast = DeltaOperatorToast()
    private var startObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?
    private var activeWritebacks = 0

    init() {
        let nc = NotificationCenter.default
        startObserver = nc.addObserver(
            forName: OperatorKitController.saveWritebackDidStartNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleStart() }
        endObserver = nc.addObserver(
            forName: OperatorKitController.saveWritebackDidEndNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleEnd() }
    }

    deinit {
        [startObserver, endObserver]
            .compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func handleStart() {
        activeWritebacks += 1
        guard activeWritebacks == 1, let view = Self.presentationView() else { return }
        toast.show(text: Self.toastText, detail: Self.toastDetailText, in: view, dismissal: .manual)
    }

    private func handleEnd() {
        activeWritebacks = max(0, activeWritebacks - 1)
        guard activeWritebacks == 0 else { return }
        toast.dismiss(after: Self.lingerAfterEnd)
    }

    /// The top-most presented view controller's view in the foreground key window. Quitting to the
    /// library keeps a GameViewController at the window root with the library presented over it, so
    /// presenting there would bury the "do not remove" warning exactly when a post-quit writeback runs.
    ///
    /// - Returns: The view to present the toast in, or nil if no foreground key window was found.
    private static func presentationView() -> UIView? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top?.view
    }
}
