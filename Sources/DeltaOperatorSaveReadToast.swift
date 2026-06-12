//
//  DeltaOperatorSaveReadToast.swift
//  DeltaOperator
//
//  Shows the "Reading Save Data" toast while a cartridge save read is in progress.
//

import OperatorKit
import UIKit

/// Shows the "Reading Save Data" toast during cartridge save reads (import and launch-time
/// recovery alike), ref-counted across overlapping reads.
final class DeltaOperatorSaveReadToast {
    private static let toastText = NSLocalizedString("Reading Save Data", comment: "")

    private let toast = DeltaOperatorToast()
    private var startObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?
    private var activeReads = 0

    init() {
        let nc = NotificationCenter.default
        startObserver = nc.addObserver(
            forName: OperatorKitController.saveReadDidStartNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleStart() }
        endObserver = nc.addObserver(
            forName: OperatorKitController.saveReadDidEndNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleEnd() }
    }

    deinit {
        [startObserver, endObserver]
            .compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func handleStart() {
        activeReads += 1
        guard activeReads == 1, let view = Self.presentationView() else { return }
        toast.show(text: Self.toastText, in: view, dismissal: .manual)
    }

    private func handleEnd() {
        activeReads = max(0, activeReads - 1)
        guard activeReads == 0 else { return }
        toast.dismiss()
    }

    /// The top-most visible view controller's view, so the toast shows wherever the user is. Delta
    /// keeps a GameViewController at the window root with the library presented over it, so we use the
    /// presented top rather than searching for a GameViewController (which is always the hidden root).
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
