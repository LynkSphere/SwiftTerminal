import Foundation
import Observation
import Sparkle

/// Observable wrapper around Sparkle's `SPUStandardUpdaterController` so that SwiftUI views
/// can drive Sparkle's updater and react to its state.
///
/// One instance is created at app launch and injected via `.environment(...)`. The standard
/// controller starts the updater immediately (`startingUpdater: true`) which schedules
/// background update checks according to the user's preferences.
@MainActor
@Observable
final class UpdaterManager {
    /// Mirrors `SPUUpdater.canCheckForUpdates`. Used to disable the menu/button while a
    /// check is already in flight.
    private(set) var canCheckForUpdates: Bool = false

    /// Two-way bound from the Settings UI. Writes through to the underlying updater.
    var automaticallyChecksForUpdates: Bool = true {
        didSet {
            guard controller.updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates else { return }
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// Update check interval in seconds. Sparkle enforces a 1-hour minimum.
    var updateCheckInterval: TimeInterval = 86_400 {
        didSet {
            guard controller.updater.updateCheckInterval != updateCheckInterval else { return }
            controller.updater.updateCheckInterval = updateCheckInterval
        }
    }

    @ObservationIgnored let controller: SPUStandardUpdaterController
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Seed local state from the updater. didSet won't fire from init, so this won't
        // create a feedback loop.
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        updateCheckInterval = controller.updater.updateCheckInterval

        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in
                self?.canCheckForUpdates = value
            }
        }
    }

    /// Triggered by the menu bar and Settings "Check Now" button. Shows Sparkle's standard UI.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
