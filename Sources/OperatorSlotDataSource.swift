//
//  OperatorSlotDataSource.swift
//  DeltaOperator
//
//  Subclasses the Roxas game data source to inject an Operator cartridge
//  status cell at the end of the grid.
//

import DeltaCore
import OperatorKit
import Roxas
import UIKit

/// Data source that appends an Operator cartridge status cell to the game collection grid.
class OperatorSlotDataSource: RSTFetchedResultsCollectionViewPrefetchingDataSource<Game, UIImage> {

    // MARK: - Operator Slot

    /// Called to configure the operator status cell each time it is dequeued.
    ///
    /// - Parameter cell: The dequeued status cell to configure.
    var operatorCellConfigurationHandler: ((OperatorStatusCell) -> Void)?

    /// Whether the operator status cell is currently visible in the collection view.
    var showOperatorSlot = false

    /// Returns `true` if the given index path points to the injected operator status cell.
    ///
    /// - Parameter indexPath: The index path to check.
    /// - Returns: `true` if the index path points to the operator status cell.
    func isOperatorSlotIndexPath(_ indexPath: IndexPath) -> Bool {
        guard showOperatorSlot, indexPath.section == 0 else { return false }
        let frcCount = fetchedResultsController.sections?.first?.numberOfObjects ?? 0
        return indexPath.item == frcCount
    }

    // MARK: - UICollectionViewDataSource

    /// Adds one extra item to section 0 when the operator slot is visible.
    ///
    /// - Parameters:
    ///   - collectionView: The collection view requesting the count.
    ///   - section: The section index.
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let frcCount = super.collectionView(collectionView, numberOfItemsInSection: section)
        return (section == 0 && showOperatorSlot) ? frcCount + 1 : frcCount
    }

    /// Dequeues an `OperatorStatusCell` for the slot index path or falls back to the default game cell.
    ///
    /// - Parameters:
    ///   - collectionView: The collection view requesting the cell.
    ///   - indexPath: The index path of the cell.
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if isOperatorSlotIndexPath(indexPath) {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: OperatorStatusCell.reuseIdentifier,
                for: indexPath
            ) as! OperatorStatusCell
            operatorCellConfigurationHandler?(cell)
            return cell
        }
        return super.collectionView(collectionView, cellForItemAt: indexPath)
    }

    // MARK: - Prefetching

    /// Filters out the operator slot index path before prefetching game artwork.
    ///
    /// - Parameters:
    ///   - collectionView: The collection view requesting prefetch.
    ///   - indexPaths: The index paths to prefetch.
    override func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let filtered = indexPaths.filter { !isOperatorSlotIndexPath($0) }
        guard !filtered.isEmpty else { return }
        super.collectionView(collectionView, prefetchItemsAt: filtered)
    }

    /// Filters out the operator slot index path before cancelling prefetch requests.
    ///
    /// - Parameters:
    ///   - collectionView: The collection view cancelling prefetch.
    ///   - indexPaths: The index paths to cancel.
    override func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let filtered = indexPaths.filter { !isOperatorSlotIndexPath($0) }
        guard !filtered.isEmpty else { return }
        super.collectionView(collectionView, cancelPrefetchingForItemsAt: filtered)
    }
}
