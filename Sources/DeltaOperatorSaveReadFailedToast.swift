//
//  DeltaOperatorSaveReadFailedToast.swift
//  DeltaOperator
//
//  Shows a warning toast when the cartridge save couldn't be read during import.
//

import OperatorKit
import UIKit

/// Shows a warning toast when OperatorKit reports the cartridge save couldn't be read after retries.
/// The game still launches saveless, so this just tells the user to clean the contacts and reinsert.
final class DeltaOperatorSaveReadFailedToast {
    private static let toastText = NSLocalizedString("Save data integrity check failed!", comment: "")
    private static let toastDetailText = NSLocalizedString("The save data appears to be inconsistent between read cycles. Please clean the cartridge pins and try again.", comment: "")
    private static let presentDelay: TimeInterval = 0.7
    private static let onScreen: TimeInterval = 4.0

    private let toast = DeltaOperatorToast()
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: OperatorKitController.saveReadFailedNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleSaveReadFailed() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Presents the warning over the top-most view controller after a short settle delay.
    private func handleSaveReadFailed() {
        // Small delay so the toast settles after any in-flight scene transition (e.g. an auto-launch).
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.presentDelay) { [weak self] in
            guard let self, let view = Self.presentationView() else { return }
            self.toast.show(text: Self.toastText, detail: Self.toastDetailText, in: view, dismissal: .auto(after: Self.onScreen))
        }
    }

    /// The top-most visible view controller's view, so the warning shows wherever the user is. Delta
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
