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
    private static let toastText = NSLocalizedString("Saving to cartridge", comment: "")
    private static let toastDetailText = NSLocalizedString("Do not remove the cartridge or disconnect the device.", comment: "")
    private static let lingerAfterEnd: TimeInterval = 2.0

    private let toast = DeltaOperatorToast()
    private var startObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?
    private var activeWritebacks = 0

    /// Supplies the view controller whose view the toast is presented in.
    var activeViewController: (() -> UIViewController?)?

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
        guard activeWritebacks == 1, let viewController = activeViewController?() else { return }
        toast.show(text: Self.toastText, detail: Self.toastDetailText, in: viewController.view, dismissal: .manual)
    }

    private func handleEnd() {
        activeWritebacks = max(0, activeWritebacks - 1)
        guard activeWritebacks == 0 else { return }
        toast.dismiss(after: Self.lingerAfterEnd)
    }
}
