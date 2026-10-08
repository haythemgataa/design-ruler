import AppKit
import DesignRulerCore
import KeyboardShortcuts

final class HotkeyController {
    /// Which command is currently active (nil if no overlay running)
    private var activeCommand: Command?

    var onLaunchMeasure: (() -> Void)?
    var onLaunchAlignmentGuides: (() -> Void)?
    var onSetActive: ((Bool) -> Void)?

    @MainActor  // KeyboardShortcuts 3 is main-actor isolated
    func registerHandlers() {
        for command in Command.allCases {
            KeyboardShortcuts.onKeyUp(for: command.shortcutName) { [weak self] in
                self?.handleHotkey(command: command)
            }
        }
    }

    /// Called by AppDelegate when an overlay session starts via any trigger (menu bar or hotkey)
    func sessionStarted(command: Command) {
        activeCommand = command
    }

    /// Called by AppDelegate when onSessionEnd fires
    func sessionEnded() {
        activeCommand = nil
    }

    private func handleHotkey(command: Command) {
        if command == activeCommand {
            // Same command: toggle off (instant dismiss, same as ESC)
            switch command {
            case .measure:
                MeasureCoordinator.shared.handleExit()
            case .alignmentGuides:
                AlignmentGuidesCoordinator.shared.handleExit()
            }
        } else if let currentCommand = activeCommand {
            // Cross-command switch: close current, then launch other
            switch currentCommand {
            case .measure:
                MeasureCoordinator.shared.handleExit()
            case .alignmentGuides:
                AlignmentGuidesCoordinator.shared.handleExit()
            }
            // Use DispatchQueue.main.async for autorelease pool drainage
            // per research pitfall #3
            DispatchQueue.main.async { [weak self] in
                self?.launchCommand(command)
            }
        } else {
            // No overlay active: normal launch
            launchCommand(command)
        }
    }

    private func launchCommand(_ command: Command) {
        guard !OverlayCoordinator.anySessionActive else { return }
        onSetActive?(true)
        switch command {
        case .measure:
            onLaunchMeasure?()
        case .alignmentGuides:
            onLaunchAlignmentGuides?()
        }
    }
}
