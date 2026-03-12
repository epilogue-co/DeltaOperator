//
//  DeltaOperatorDelegate.swift
//  DeltaOperator
//
//  Delta-specific delegate bridging OperatorKit to DatabaseManager.
//

import DeltaCore
import Foundation
import OperatorKit
import Roxas
import UIKit

/// Bridges OperatorKit to Delta's database for game import, save lookup, and deletion.
final class DeltaOperatorDelegate: OperatorKitControllerDelegate, @unchecked Sendable {

    // MARK: - OperatorKitControllerDelegate

    /// Imports a ROM file into Delta's database via DatabaseManager.
    ///
    /// - Parameter url: Path to the temporary ROM file.
    /// - Returns: The imported game's identifier (SHA-1 hash).
    func operatorController(_ controller: OperatorKitController, importROMAt url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DatabaseManager.shared.importGames(at: [url]) { games, errors in
                if let game = games.first { continuation.resume(returning: game.identifier) }
                else { continuation.resume(throwing: errors.first ?? OperatorError.commandFailed) }
            }
        }
    }

    /// Returns the save file URL for the given game.
    ///
    /// - Parameter gameIdentifier: The identifier of the game to look up.
    /// - Returns: The save file URL, or nil if the game is not found.
    func operatorController(_ controller: OperatorKitController, gameSaveURLFor gameIdentifier: String) async -> URL? {
        await MainActor.run {
            fetchGame(identifier: gameIdentifier, in: DatabaseManager.shared.viewContext)?.gameSaveURL
        }
    }

    /// Deletes the game and its ROM file from Delta's database.
    ///
    /// - Parameter gameIdentifier: The identifier of the game to delete.
    func operatorController(_ controller: OperatorKitController, deleteGameWith gameIdentifier: String) {
        let delete: (NSManagedObjectContext) -> Void = { context in
            guard let game = self.fetchGame(identifier: gameIdentifier, in: context) else { return }
            try? FileManager.default.removeItem(at: game.gameSaveURL)
            context.delete(game)
            try? context.save()
        }

        // viewContext must be used on the main thread; use a background context otherwise.
        if Thread.isMainThread { delete(DatabaseManager.shared.viewContext) }
        else { DatabaseManager.shared.performBackgroundTask { delete($0) } }
    }

    /// Returns whether the game already exists in Delta's database.
    ///
    /// - Parameter gameIdentifier: The identifier to look up.
    /// - Returns: `true` if the game exists in the database.
    func operatorController(_ controller: OperatorKitController, hasGameWithIdentifier gameIdentifier: String) async -> Bool {
        await MainActor.run {
            fetchGame(identifier: gameIdentifier, in: DatabaseManager.shared.viewContext) != nil
        }
    }

    /// Flushes in-memory SRAM to the game's save file on disk.
    ///
    /// - Parameter gameIdentifier: The identifier of the game whose SRAM to flush.
    @MainActor func operatorController(_ controller: OperatorKitController, flushSaveFor gameIdentifier: String) {
        guard let gameVC = DeltaOperatorUtils.findActiveGameViewController(),
              let game = gameVC.game as? Game, game.identifier == gameIdentifier,
              let core = gameVC.emulatorCore, core.state == .running || core.state == .paused
        else { return }
        core.deltaCore.emulatorBridge.saveGameSave(to: game.gameSaveURL)
    }

    // MARK: - Helpers

    /// Fetches a game by identifier from the given context.
    ///
    /// - Parameters:
    ///   - identifier: The game identifier to search for.
    ///   - context: The managed object context to fetch from.
    /// - Returns: The matching game, or nil if not found.
    private func fetchGame(identifier: String, in context: NSManagedObjectContext) -> Game? {
        let request = Game.fetchRequest() as NSFetchRequest<Game>
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(Game.identifier), identifier)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

}
