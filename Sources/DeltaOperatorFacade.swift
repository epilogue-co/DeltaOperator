//
//  DeltaOperatorFacade.swift
//  DeltaOperator
//
//  Single entry point for Delta to interact with Operator functionality.
//

import OperatorKit

/// Facade that encapsulates all OperatorKit setup and lifecycle management.
final class DeltaOperatorFacade {

    private let delegate = DeltaOperatorDelegate()
    private let gameObserver = DeltaOperatorGameObserver()

    /// Configures the OperatorKit controller and begins listening for device events.
    func start() {
        OperatorKitController.shared.delegate = delegate
        OperatorKitController.shared.start()
    }

    /// Performs post-database-initialization cleanup.
    func onDatabaseReady() {
        OperatorKitController.shared.cleanupStaleGame()
        OperatorKitController.shared.restoreOrphanedBorrowBackup()
    }
}
