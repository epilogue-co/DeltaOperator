//
//  DeltaOperatorWritebackToast.swift
//  DeltaOperator
//
//  Displays a toast during save writeback to warn the user not to remove the cartridge.
//

import OperatorKit
import Roxas
import UIKit

/// Manages the "Saving to cartridge" toast shown during save writeback.
final class DeltaOperatorWritebackToast {
    private static let minimumDuration: TimeInterval = 2.0
    private static let toastText = NSLocalizedString("Saving to cartridge", comment: "")
    private static let toastDetailText = NSLocalizedString("Do not remove the cartridge or disconnect the device.", comment: "")

    private weak var toastView: RSTToastView?
    private var dismissWorkItem: DispatchWorkItem?
    private var startObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?

    /// The toast checks this before showing — return true to skip (e.g. for tiny saves).
    var shouldSuppress: (() -> Bool)?

    /// The toast uses this to find the view to present in.
    var activeViewController: (() -> UIViewController?)?

    // MARK: - Lifecycle

    /// Subscribes to writeback start/end notifications.
    init() {
        let nc = NotificationCenter.default

        startObserver = nc.addObserver(
            forName: OperatorKitController.saveWritebackDidStartNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.show() }

        endObserver = nc.addObserver(
            forName: OperatorKitController.saveWritebackDidEndNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleDismiss() }
    }

    /// Removes notification observers.
    deinit {
        [startObserver, endObserver]
            .compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Private API

    /// Shows the toast in the active game view controller.
    private func show() {
        guard shouldSuppress?() != true else { return }

        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        guard toastView == nil,
              let viewController = activeViewController?()
        else { return }

        let toast = RSTToastView(text: Self.toastText, detailText: Self.toastDetailText)
        toast.textLabel.textAlignment = .center
        toast.presentationEdge = .top
        toast.show(in: viewController.view)
        toastView = toast
    }

    /// Dismisses the toast after a minimum display duration.
    private func scheduleDismiss() {
        guard shouldSuppress?() != true else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.toastView?.dismiss()
            self?.toastView = nil
            self?.dismissWorkItem = nil
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.minimumDuration, execute: workItem)
    }
}
