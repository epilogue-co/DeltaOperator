//
//  DeltaOperatorGameObserver.swift
//  DeltaOperator
//
//  Bridges cartridge lifecycle events to Delta's active emulation session.
//

import Combine
import DeltaCore
import OperatorKit
import Roxas
import UIKit

/// Manages cartridge removal, save writeback, and periodic save flushing for Delta.
final class DeltaOperatorGameObserver {
    private var cartridgeObserver: NSObjectProtocol?
    private var saveObserver: NSObjectProtocol?
    private var slotStateCancellable: AnyCancellable?
    private var cartridgeSaveApplied = false

    private let writebackToast = DeltaOperatorWritebackToast()
    private let saveReadFailedToast = DeltaOperatorSaveReadFailedToast()
    private static let showGamesSegueIdentifier = "showGamesViewController"

    /// Periodically flushes SRAM to disk for cores that don't trigger save callbacks during gameplay.
    private var saveFlushTimer: Timer?
    private var lastFlushHash: String?
    private static let saveFlushInterval: TimeInterval = 5.0

    // MARK: - Lifecycle

    /// Registers notification observers and subscribes to slot state changes.
    init() {
        let nc = NotificationCenter.default

        // Tear down on the main thread: dismissGameScene touches UIKit, and teardown must not run
        // concurrently with EmulatorCore.start() or a cartridge pulled mid-launch deadlocks stop()/start().
        cartridgeObserver = nc.addObserver(
            forName: OperatorKitController.cartridgeRemovedNotification, object: nil, queue: .main
        ) { [weak self] in self?.handleCartridgeRemoved($0) }

        // Trigger save writeback to cartridge when Core Data persists a GameSave.
        saveObserver = nc.addObserver(
            forName: .NSManagedObjectContextDidSave, object: nil, queue: .main
        ) { [weak self] in self?.handleDatabaseSave($0) }

        // Reload cartridge save and manage flush timer on slot state changes.
        slotStateCancellable = OperatorKitController.shared.$slotState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handleSlotStateChanged($0) }

        // Configure writeback toast.
        writebackToast.shouldSuppress = { [weak self] in self?.usesPeriodicSaveFlush() ?? false }
        writebackToast.activeViewController = { DeltaOperatorUtils.findActiveGameViewController() }
    }

    /// Removes notification observers and stops the flush timer.
    deinit {
        [cartridgeObserver, saveObserver]
            .compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }
        saveFlushTimer?.invalidate()
    }

    // MARK: - Event Handlers

    /// Notifies OperatorKit when a GameSave is inserted or updated in Core Data.
    ///
    /// - Parameter notification: The Core Data did-save notification.
    private func handleDatabaseSave(_ notification: Notification) {
        let changedSaves: (String) -> [GameSave] = { key in
            (notification.userInfo?[key] as? Set<NSManagedObject>)?.compactMap { $0 as? GameSave } ?? []
        }
        let saves = changedSaves(NSUpdatedObjectsKey) + changedSaves(NSInsertedObjectsKey)
        guard !saves.isEmpty,
              case .imported(let importedID) = OperatorKitController.shared.slotState else { return }

        let viewContext = DatabaseManager.shared.viewContext
        let matchesImported = saves.contains { save in
            guard save.managedObjectContext == viewContext else { return true }
            return save.game?.identifier == importedID
        }
        guard matchesImported else { return }

        if !cartridgeSaveApplied { reloadCartridgeSave(for: importedID) }
        guard cartridgeSaveApplied else { return }
        OperatorKitController.shared.notifySaveDataChanged()
    }

    /// Reloads the cartridge save on import and manages the periodic flush timer.
    ///
    /// - Parameter state: The new slot state from OperatorKit.
    private func handleSlotStateChanged(_ state: OperatorSlotState) {
        if case .imported(let id) = state {
            if let (gameVC, _) = DeltaOperatorUtils.findGameViewController(for: id), gameVC.game is Game {
                reloadCartridgeSave(for: id)
            }
            if usesPeriodicSaveFlush() { startSaveFlushTimer() }
        } else {
            cartridgeSaveApplied = false
            stopSaveFlushTimer()
        }
    }

    /// Stops emulation for the removed cartridge and navigates back to the game list.
    ///
    /// The original save file has already been restored to disk by OperatorKitController
    /// before this notification fires. This method only reloads it into the emulator bridge
    /// (if active) and dismisses the game scene.
    ///
    /// - Parameter notification: The cartridge-removed notification from OperatorKit.
    private func handleCartridgeRemoved(_ notification: Notification) {
        guard let id = notification.userInfo?[OperatorKitController.gameIdentifierKey] as? String else { return }
        stopSaveFlushTimer()

        guard let (gameVC, windowScene) = DeltaOperatorUtils.findGameViewController(for: id) else { return }

        if let saveData = notification.userInfo?[OperatorKitController.restoredSaveDataKey] as? Data,
           let game = gameVC.game as? Game,
           let core = gameVC.emulatorCore {
            core.pause()
            try? saveData.write(to: game.gameSaveURL, options: .atomic)
            core.deltaCore.emulatorBridge.loadGameSave(from: game.gameSaveURL)
        } else {
            gameVC.emulatorCore?.stop()
        }

        dismissGameScene(gameVC, windowScene: windowScene)
    }

    /// Dismisses the game scene, clears auto-save states, stops emulation.
    ///
    /// - Parameters:
    ///   - gameVC: The GameViewController to dismiss.
    ///   - windowScene: The window scene hosting the game.
    private func dismissGameScene(_ gameVC: GameViewController, windowScene: UIWindowScene) {
        if let game = gameVC.game as? Game { DeltaOperatorUtils.deleteAutoSaveStates(for: game) }

        if windowScene is GameScene {
            gameVC.game = nil
            UIApplication.shared.requestSceneSessionDestruction(windowScene.session, options: nil, errorHandler: nil)
        } else {
            gameVC.emulatorCore?.stop()
            gameVC.returnToGameViewController {
                gameVC.performSegue(withIdentifier: Self.showGamesSegueIdentifier, sender: nil)
                DispatchQueue.main.async {
                    gameVC.game = nil
                    if let nav = gameVC.presentedViewController as? UINavigationController,
                       let gamesVC = nav.topViewController as? GamesViewController {
                        gamesVC.activeEmulatorCore = nil
                        gamesVC.theme = .opaque
                    }
                }
            }
        }
    }

    // MARK: - Save Management

    /// Loads the cartridge save data into the active emulator session.
    ///
    /// - Parameter gameIdentifier: The identifier of the imported game.
    private func reloadCartridgeSave(for gameIdentifier: String) {
        guard let (gameVC, _) = DeltaOperatorUtils.findGameViewController(for: gameIdentifier),
              let game = gameVC.game as? Game,
              let core = gameVC.emulatorCore, core.state == .running || core.state == .paused
        else { return }

        let shouldApply = OperatorKitController.shared.cartridgeSaveMatchesDisk()
        let wasRunning = core.state == .running
        if wasRunning { core.pause() }
        if shouldApply, OperatorKitController.shared.applyCartridgeSave() {
            core.deltaCore.emulatorBridge.loadGameSave(from: game.gameSaveURL)
        }
        cartridgeSaveApplied = true
        if wasRunning { core.resume() }
    }

    /// Starts the periodic timer that flushes SRAM to disk every 5 seconds.
    private func startSaveFlushTimer() {
        guard saveFlushTimer == nil else { return }
        lastFlushHash = nil

        saveFlushTimer = Timer.scheduledTimer(
            withTimeInterval: Self.saveFlushInterval, repeats: true
        ) { [weak self] _ in self?.flushSaveIfChanged() }
    }

    /// Stops the periodic flush timer and resets the last known hash.
    private func stopSaveFlushTimer() {
        saveFlushTimer?.invalidate()
        saveFlushTimer = nil
        lastFlushHash = nil
    }

    /// Flushes SRAM to disk via the emulator bridge and triggers a writeback if the data changed.
    private func flushSaveIfChanged() {
        guard let id = OperatorKitController.shared.importedGameIdentifier,
              let (gameVC, _) = DeltaOperatorUtils.findGameViewController(for: id),
              let core = gameVC.emulatorCore, core.state == .running
        else { return }

        let saveURL = core.game.gameSaveURL
        core.deltaCore.emulatorBridge.saveGameSave(to: saveURL)

        guard let hash = try? RSTHasher.sha1HashOfFile(at: saveURL),
              hash != lastFlushHash else { return }
        lastFlushHash = hash
        OperatorKitController.shared.notifySaveDataChanged()
    }

    // MARK: - Helpers

    /// Returns whether the current cartridge needs the periodic SRAM flush.
    ///
    /// GB and SNES cores don't write SRAM to disk during gameplay, so their saves
    /// must be polled and flushed. The writeback toast is also suppressed for these
    /// platforms because the frequent small flushes would otherwise spam it.
    ///
    /// - Returns: True if the cartridge platform is GB/GBC or SNES.
    private func usesPeriodicSaveFlush() -> Bool {
        guard let sig = OperatorKitController.shared.publishedSignature else { return false }
        return sig.platform == .gb || sig.platform == .snes
    }

}
