//
//  OperatorLaunchCoordinator.swift
//  DeltaOperator
//
//  Gates operator-game launches on a verified cartridge save.
//

import DeltaCore
import OperatorKit
import UIKit

/// Verifies the cartridge save before an operator game launches: restores a vanished save file,
/// recovers a failed save read on demand, and asks the user before a saveless launch.
final class OperatorLaunchCoordinator {
    private weak var collectionViewController: GameCollectionViewController?
    /// One-shot consent to launch without save data, consumed by the next gate pass.
    private var savelessLaunchOverride: String?

    /// Wires the coordinator to the collection view controller it launches games in.
    ///
    /// - Parameter collectionViewController: The game grid that owns this coordinator.
    func start(collectionViewController: GameCollectionViewController) {
        self.collectionViewController = collectionViewController
    }

    /// Returns whether the launch must wait for save verification, kicking off recovery if so.
    ///
    /// - Parameter game: The operator game being launched.
    func deferLaunchIfSaveUnverified(of game: Game) -> Bool {
        let controller = OperatorKitController.shared
        if controller.saveReadDidFail {
            if savelessLaunchOverride == game.identifier {
                savelessLaunchOverride = nil
                return false
            }
            recoverSave(for: game)
            return true
        }

        controller.applySaveForLaunch()
        return false
    }

    // MARK: - Recovery

    /// Re-attempts the cartridge save read, then launches on success or asks the user on failure.
    ///
    /// - Parameter game: The operator game awaiting launch.
    private func recoverSave(for game: Game) {
        Task { @MainActor [weak self] in
            let recovered = await OperatorKitController.shared.reattemptSaveRead()
            guard let self else { return }
            if recovered {
                self.launch(game)
            } else {
                self.presentRecoveryAlert(for: game)
            }
        }
    }

    /// Launches the game through the grid's regular selection path.
    ///
    /// - Parameter game: The game to launch.
    private func launch(_ game: Game) {
        guard let collectionViewController,
              let collectionView = collectionViewController.collectionView,
              let indexPath = collectionViewController.dataSource.fetchedResultsController.indexPath(forObject: game)
        else { return }
        collectionViewController.collectionView(collectionView, didSelectItemAt: indexPath)
    }

    /// Asks the user how to proceed after a failed save recovery.
    ///
    /// - Parameter game: The operator game awaiting launch.
    private func presentRecoveryAlert(for game: Game) {
        let alertController = UIAlertController(
            title: NSLocalizedString("Couldn't Read Save Data", comment: ""),
            message: NSLocalizedString("The save on this cartridge couldn't be read. Playing now would start without your save data.", comment: ""),
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Try Again", comment: ""), style: .default) { [weak self] _ in
            self?.recoverSave(for: game)
        })
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Play Without Save", comment: ""), style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.savelessLaunchOverride = game.identifier
            self.launch(game)
        })
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        collectionViewController?.present(alertController, animated: true)
    }
}
