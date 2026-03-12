//
//  OperatorUICoordinators.swift
//  DeltaOperator
//
//  Coordinates Operator UI state in Delta's game collection and placeholder views.
//

import Combine
import CoreData
import DeltaCore
import OperatorKit
import UIKit

/// Manages Operator cell injection in a game collection grid.
final class OperatorCollectionCoordinator {
    private var cancellables = Set<AnyCancellable>()
    private let prototypeCell = OperatorStatusCell()
    private weak var collectionView: UICollectionView?
    private weak var dataSource: OperatorSlotDataSource?

    /// The identifier of the current game collection tab, updated when the tab changes.
    var gameCollectionIdentifier: String? {
        didSet {
            guard gameCollectionIdentifier != oldValue else { return }
            self.handleStateChange(OperatorKitController.shared.slotState,
                                   signature: OperatorKitController.shared.publishedSignature)
        }
    }

    // MARK: - Lifecycle

    /// Registers the cell, wires the configuration handler, and subscribes to state changes.
    ///
    /// - Parameters:
    ///   - collectionView: The collection view to inject the operator cell into.
    ///   - dataSource: The data source managing the game grid.
    func start(collectionView: UICollectionView, dataSource: OperatorSlotDataSource) {
        self.collectionView = collectionView
        self.dataSource = dataSource
        collectionView.register(OperatorStatusCell.self,
                                forCellWithReuseIdentifier: OperatorStatusCell.reuseIdentifier)
        self.wireCellConfiguration(dataSource: dataSource)
        self.subscribeToSlotState()
    }

    /// Sets the cell configuration handler on the data source.
    ///
    /// - Parameter dataSource: The data source to wire the handler on.
    private func wireCellConfiguration(dataSource: OperatorSlotDataSource) {
        dataSource.operatorCellConfigurationHandler = { [weak self] cell in
            guard let self, let collectionView = self.collectionView else { return }
            if let layout = collectionView.collectionViewLayout as? GridCollectionViewLayout {
                cell.cellWidth = layout.itemWidth
            }
            cell.configure(with: OperatorKitController.shared.slotState)
        }
    }

    /// Subscribes to slot state and signature changes on the main queue.
    private func subscribeToSlotState() {
        OperatorKitController.shared.$slotState
            .combineLatest(OperatorKitController.shared.$publishedSignature)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (slotState, signature) in
                self?.handleStateChange(slotState, signature: signature)
            }
            .store(in: &cancellables)
    }

    // MARK: - Layout

    /// Returns the size for the operator status cell using Auto Layout sizing.
    ///
    /// - Parameter width: The target cell width from the grid layout.
    /// - Returns: The computed cell size fitting the current slot state.
    func operatorCellSize(for width: CGFloat) -> CGSize {
        let cell = self.prototypeCell
        cell.cellWidth = width
        cell.configure(with: OperatorKitController.shared.slotState)

        let constraint = cell.contentView.widthAnchor.constraint(equalToConstant: width)
        constraint.isActive = true
        defer { constraint.isActive = false }

        let size = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: size.height)
    }

    // MARK: - Event Handlers

    /// Shows, hides, or updates the operator cell based on the current slot state.
    ///
    /// - Parameters:
    ///   - slotState: The current slot state from OperatorKit.
    ///   - signature: The current cartridge signature, if available.
    private func handleStateChange(_ slotState: OperatorSlotState, signature: CartridgeSignature?) {
        guard let collectionView, let dataSource else { return }

        let shouldShow = self.shouldShowOperatorSlot(for: slotState, signature: signature)

        if dataSource.showOperatorSlot != shouldShow {
            dataSource.showOperatorSlot = shouldShow
            collectionView.reloadData()
        } else if shouldShow {
            self.updateVisibleOperatorCell(in: collectionView, with: slotState)
        }
    }

    /// Updates the operator cell already visible in the collection view.
    ///
    /// - Parameters:
    ///   - collectionView: The collection view containing the cell.
    ///   - slotState: The current slot state to configure the cell with.
    private func updateVisibleOperatorCell(in collectionView: UICollectionView, with slotState: OperatorSlotState) {
        let operatorItem = collectionView.numberOfItems(inSection: 0) - 1
        guard operatorItem >= 0 else { return }
        guard let cell = collectionView.cellForItem(at: IndexPath(item: operatorItem, section: 0)) as? OperatorStatusCell else { return }
        if let layout = collectionView.collectionViewLayout as? GridCollectionViewLayout {
            cell.cellWidth = layout.itemWidth
        }
        cell.configure(with: slotState)
    }

    // MARK: - Helpers

    /// Returns whether the operator cell should be visible for the given state and tab.
    ///
    /// - Parameters:
    ///   - state: The current slot state.
    ///   - signature: The current cartridge signature, if available.
    private func shouldShowOperatorSlot(for state: OperatorSlotState, signature: CartridgeSignature?) -> Bool {
        if case .disconnected = state { return false }
        if case .imported = state { return false }
        if case .transferring(let progress) = state, progress >= 1.0 { return false }
        guard let gameCollectionIdentifier else { return false }

        if let signature {
            guard case .transferring = state else { return false }
            return GameType(fileExtension: signature.romExtension)?.rawValue == gameCollectionIdentifier
        }

        return [GameType.gbc.rawValue, GameType.gba.rawValue].contains(gameCollectionIdentifier)
    }
}

/// Manages the Operator slot overlay on the "No Games" placeholder.
final class OperatorOverlayCoordinator {
    private static let gameCollectionVCIdentifier = "gameCollectionViewController"
    private static let regularItemWidth: CGFloat = 150
    private static let regularSpacing: CGFloat = 25
    private static let compactItemWidth: CGFloat = 90
    private static let compactSpacing: CGFloat = 12
    private static let overlayTopInset: CGFloat = 20
    let slotView = OperatorStatusView()
    private var cancellables = Set<AnyCancellable>()
    private var leadingConstraint: NSLayoutConstraint?
    private weak var parentView: UIView?
    private weak var placeholderStackView: UIStackView?
    private var lastFocusedPlatform: String?

    /// Whether the "No Games" placeholder is currently visible.
    var isPlaceholderVisible = false {
        didSet {
            guard isPlaceholderVisible != oldValue else { return }
            self.updateVisibility()
        }
    }

    // MARK: - Lifecycle

    /// Adds the overlay view to the parent and subscribes to state changes.
    ///
    /// - Parameters:
    ///   - parentView: The view to add the overlay into.
    ///   - placeholderStackView: The "No Games" placeholder stack to show/hide.
    func install(in parentView: UIView, placeholderStackView: UIStackView) {
        self.parentView = parentView
        self.placeholderStackView = placeholderStackView
        self.installSlotView(in: parentView)
        self.subscribeToSlotState()
    }

    /// Adds the slot view to the parent and pins it to the top-leading corner.
    ///
    /// - Parameter parentView: The view to add the slot view into.
    private func installSlotView(in parentView: UIView) {
        self.slotView.translatesAutoresizingMaskIntoConstraints = false
        self.slotView.isHidden = true
        parentView.addSubview(self.slotView)

        let leading = self.slotView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor)
        NSLayoutConstraint.activate([
            leading,
            self.slotView.topAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.topAnchor, constant: Self.overlayTopInset),
        ])
        self.leadingConstraint = leading
    }

    /// Subscribes to slot state and signature changes on the main queue.
    private func subscribeToSlotState() {
        OperatorKitController.shared.$slotState
            .combineLatest(OperatorKitController.shared.$publishedSignature)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (slotState, signature) in
                self?.updateVisibility()
                self?.handlePlatformFocus(slotState: slotState, signature: signature)
            }
            .store(in: &cancellables)
    }

    // MARK: - Layout

    /// Recalculates the overlay position after a layout pass (e.g. rotation or split view).
    func layoutChanged() {
        guard self.slotView.isHidden == false else { return }
        self.updateVisibility()
    }

    // MARK: - Event Handlers

    /// Switches to the matching game collection tab when a cartridge is imported.
    ///
    /// - Parameters:
    ///   - slotState: The current slot state.
    ///   - signature: The current cartridge signature, if available.
    private func handlePlatformFocus(slotState: OperatorSlotState, signature: CartridgeSignature?) {
        guard case .imported = slotState,
              let signature, !signature.isEmpty,
              let platformRaw = GameType(fileExtension: signature.romExtension)?.rawValue
        else {
            if case .disconnected = slotState { self.lastFocusedPlatform = nil }
            if case .connected = slotState { self.lastFocusedPlatform = nil }
            return
        }

        guard platformRaw != self.lastFocusedPlatform else { return }
        self.lastFocusedPlatform = platformRaw
        self.switchToTab(identifier: platformRaw)
    }

    /// Shows or hides the overlay and placeholder based on the current slot state.
    private func updateVisibility() {
        guard let parentView else { return }

        let slotState = OperatorKitController.shared.slotState
        let shouldShowSlot = self.shouldShowSlot(for: slotState)

        self.updatePlaceholder(for: slotState)

        guard shouldShowSlot else {
            self.slotView.isHidden = true
            return
        }

        self.positionSlotView(in: parentView, slotState: slotState)
    }

    /// Returns whether the slot overlay should be visible for the given state.
    ///
    /// - Parameter slotState: The current slot state.
    /// - Returns: `true` if the overlay should be shown.
    private func shouldShowSlot(for slotState: OperatorSlotState) -> Bool {
        switch slotState {
        case .connected, .transferring:
            return self.isPlaceholderVisible
        case .disconnected, .imported:
            return false
        }
    }

    /// Hides or shows the "No Games" placeholder text based on device connection.
    ///
    /// - Parameter slotState: The current slot state.
    private func updatePlaceholder(for slotState: OperatorSlotState) {
        guard self.isPlaceholderVisible else { return }
        if case .disconnected = slotState {
            self.placeholderStackView?.isHidden = false
        } else {
            self.placeholderStackView?.isHidden = true
        }
    }

    /// Calculates the grid layout and positions the slot view to match.
    ///
    /// - Parameters:
    ///   - parentView: The parent view to calculate layout from.
    ///   - slotState: The current slot state to configure the view with.
    private func positionSlotView(in parentView: UIView, slotState: OperatorSlotState) {
        let isRegular = parentView.traitCollection.horizontalSizeClass == .regular
        let itemWidth = isRegular ? Self.regularItemWidth : Self.compactItemWidth
        let minimumInteritemSpacing = isRegular ? Self.regularSpacing : Self.compactSpacing

        let contentInsetLeft = parentView.safeAreaInsets.left
        let contentInsetRight = parentView.safeAreaInsets.right
        let contentWidth = parentView.bounds.width - contentInsetLeft - contentInsetRight
        let maxPerRow = max(Int(floor((contentWidth - minimumInteritemSpacing) / (itemWidth + minimumInteritemSpacing))), 1)
        let interitemSpacing = (contentWidth - CGFloat(maxPerRow) * itemWidth) / CGFloat(maxPerRow + 1)

        self.slotView.cellWidth = itemWidth
        self.leadingConstraint?.constant = interitemSpacing + contentInsetLeft
        self.slotView.configure(with: slotState)

        if self.slotView.isHidden {
            UIView.performWithoutAnimation {
                self.slotView.isHidden = false
                self.slotView.layoutIfNeeded()
            }
        }
    }

    // MARK: - Tab Navigation

    /// Navigates the page view controller to the game collection matching the given identifier.
    ///
    /// - Parameter identifier: The raw game type identifier of the target tab.
    private func switchToTab(identifier: String) {
        guard let gamesVC = self.findGamesViewController() else { return }
        guard let pageVC = gamesVC.children.first(where: { $0 is UIPageViewController }) as? UIPageViewController else { return }
        let pageControl = gamesVC.navigationController?.toolbar.subviews.compactMap({ $0 as? UIPageControl }).first

        guard let (collections, targetIndex) = self.findTargetCollection(identifier: identifier) else { return }

        let currentIndex = pageControl?.currentPage ?? 0
        guard targetIndex != currentIndex else { return }

        self.navigateToTab(gamesVC: gamesVC, pageVC: pageVC, pageControl: pageControl,
                           collections: collections, targetIndex: targetIndex, currentIndex: currentIndex)
    }

    /// Walks the responder chain from the parent view to find the GamesViewController.
    ///
    /// - Returns: The GamesViewController, or nil if not found in the responder chain.
    private func findGamesViewController() -> GamesViewController? {
        var responder: UIResponder? = self.parentView
        while let next = responder?.next {
            if let vc = next as? GamesViewController { return vc }
            responder = next
        }
        return nil
    }

    /// Fetches sorted game collections and finds the index matching the given identifier.
    ///
    /// - Parameter identifier: The raw game type identifier to find.
    /// - Returns: The collections and target index, or nil if not found.
    private func findTargetCollection(identifier: String) -> ([GameCollection], Int)? {
        let fetchRequest = GameCollection.fetchRequest() as NSFetchRequest<GameCollection>
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(GameCollection.index), ascending: true)]
        guard let collections = try? DatabaseManager.shared.viewContext.fetch(fetchRequest),
              let targetIndex = collections.firstIndex(where: { $0.identifier == identifier })
        else { return nil }
        return (collections, targetIndex)
    }

    /// Performs the page navigation and updates the page control and title.
    ///
    /// - Parameters:
    ///   - gamesVC: The GamesViewController hosting the pages.
    ///   - pageVC: The page view controller to navigate.
    ///   - pageControl: The page control to update, if present.
    ///   - collections: The sorted game collections.
    ///   - targetIndex: The index to navigate to.
    ///   - currentIndex: The current page index.
    private func navigateToTab(gamesVC: GamesViewController, pageVC: UIPageViewController,
                               pageControl: UIPageControl?, collections: [GameCollection],
                               targetIndex: Int, currentIndex: Int) {
        let targetVC = gamesVC.storyboard?
            .instantiateViewController(withIdentifier: Self.gameCollectionVCIdentifier)
            as! GameCollectionViewController
        targetVC.gameCollection = collections[targetIndex]
        if let currentVC = pageVC.viewControllers?.first as? GameCollectionViewController {
            targetVC.theme = currentVC.theme
            targetVC.activeEmulatorCore = currentVC.activeEmulatorCore
        }

        let direction: UIPageViewController.NavigationDirection = targetIndex > currentIndex ? .forward : .reverse
        pageVC.setViewControllers([targetVC], direction: direction, animated: true, completion: nil)
        pageControl?.currentPage = targetIndex
        gamesVC.title = targetVC.title
        Settings.previousGameCollection = collections[targetIndex]
    }
}
