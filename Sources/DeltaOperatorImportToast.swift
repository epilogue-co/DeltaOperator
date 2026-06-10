//
//  DeltaOperatorImportToast.swift
//  DeltaOperator
//
//  Shows warning toasts during cartridge import: a read retry and the unidentified-game fallback.
//

import OperatorKit
import UIKit

/// Shows transient warnings while a cartridge is imported. A flaky read can produce a dump that doesn't
/// match the games database, so OperatorKit re-reads it; this surfaces that retry and, if every attempt
/// still fails to identify the game, the fallback to importing it unrecognized.
final class DeltaOperatorImportToast {
    private static let retryText = NSLocalizedString("Couldn't read the cartridge", comment: "")
    private static let retryDetailText = NSLocalizedString("Trying again…", comment: "")
    private static let unidentifiedText = NSLocalizedString("Couldn't identify this game", comment: "")
    private static let unidentifiedDetailText = NSLocalizedString("Importing it as an unrecognized game. Clean the cartridge pins and reinsert to try again.", comment: "")
    private static let presentDelay: TimeInterval = 0.7
    private static let onScreen: TimeInterval = 4.0

    private let toast = DeltaOperatorToast()
    private var observers: [NSObjectProtocol] = []

    init() {
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: OperatorKitController.cartridgeReadRetryNotification, object: nil, queue: .main) { [weak self] _ in
                self?.present(text: Self.retryText, detail: Self.retryDetailText)
            },
            nc.addObserver(forName: OperatorKitController.gameUnidentifiedNotification, object: nil, queue: .main) { [weak self] _ in
                self?.present(text: Self.unidentifiedText, detail: Self.unidentifiedDetailText)
            },
        ]
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Presents a warning over the top-most view controller after a short settle delay.
    ///
    /// - Parameters:
    ///   - text: The primary warning text.
    ///   - detail: The secondary text shown beneath `text`.
    private func present(text: String, detail: String) {
        // Small delay so the toast settles after any in-flight scene transition (e.g. an auto-launch).
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.presentDelay) { [weak self] in
            guard let self, let view = Self.presentationView() else { return }
            self.toast.show(text: text, detail: detail, in: view, dismissal: .auto(after: Self.onScreen))
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
