//
//  DeltaOperatorUtils.swift
//  DeltaOperator
//
//  Shared utilities for view controller lookup and save state management.
//

import DeltaCore
import Roxas
import UIKit

/// Shared helpers used by DeltaOperatorDelegate and DeltaOperatorGameObserver.
enum DeltaOperatorUtils {

    /// Finds the GameViewController running the game with the given identifier.
    ///
    /// - Parameter gameIdentifier: The identifier of the game to find.
    /// - Returns: The matching GameViewController and its window scene, or nil.
    static func findGameViewController(for gameIdentifier: String) -> (GameViewController, UIWindowScene)? {
        for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in windowScene.windows {
                guard let gameVC = traverseGameViewController(from: window.rootViewController),
                      (gameVC.game as? Game)?.identifier == gameIdentifier
                else { continue }
                return (gameVC, windowScene)
            }
        }
        return nil
    }

    /// Finds the GameViewController in the current key window.
    ///
    /// - Returns: The active GameViewController, or nil if none is visible.
    static func findActiveGameViewController() -> GameViewController? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                if let gameVC = traverseGameViewController(from: window.rootViewController) {
                    return gameVC
                }
            }
        }
        return nil
    }

    /// Recursively walks the view controller hierarchy to find a GameViewController.
    ///
    /// - Parameter viewController: The root view controller to start traversal from.
    /// - Returns: The first GameViewController found, or nil.
    private static func traverseGameViewController(from viewController: UIViewController?) -> GameViewController? {
        guard let vc = viewController else { return nil }
        if let gameVC = vc as? GameViewController { return gameVC }
        if let found = traverseGameViewController(from: vc.presentedViewController) { return found }
        return vc.children.lazy.compactMap { traverseGameViewController(from: $0) }.first
    }

    /// Deletes all auto-save states for the given game so the next launch loads from the save file.
    ///
    /// - Parameter game: The game whose auto-save states should be deleted.
    static func deleteAutoSaveStates(for game: Game) {
        let context = DatabaseManager.shared.newBackgroundContext()
        context.performAndWait {
            let bgGame = context.object(with: game.objectID) as! Game
            let autoSaves = (try? SaveState.fetchRequest(for: bgGame, type: .auto).execute()) ?? []
            autoSaves.forEach { context.delete($0) }
            try? context.save()
        }
    }
}
