import AppKit
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let traceNewBlankTrace = Self("traceNewBlankTrace")
    static let traceCaptureFrontmostApp = Self("traceCaptureFrontmostApp")
}

enum TraceGlobalShortcutAction: String, CaseIterable, Hashable {
    case newBlankTrace
    case captureFrontmostApp

    var title: String {
        switch self {
        case .newBlankTrace:
            return "New Blank Trace"
        case .captureFrontmostApp:
            return "Capture Frontmost App"
        }
    }

    var name: KeyboardShortcuts.Name {
        switch self {
        case .newBlankTrace:
            return .traceNewBlankTrace
        case .captureFrontmostApp:
            return .traceCaptureFrontmostApp
        }
    }
}

enum TraceGlobalShortcutActionDispatch {
    static func perform(
        _ action: TraceGlobalShortcutAction,
        newBlankTrace: () -> Void,
        captureFrontmostApp: () -> Void
    ) {
        switch action {
        case .newBlankTrace:
            newBlankTrace()
        case .captureFrontmostApp:
            captureFrontmostApp()
        }
    }
}

enum TraceGlobalShortcutPolicy {
    @MainActor
    static func validationResult(
        for shortcut: KeyboardShortcuts.Shortcut,
        action: TraceGlobalShortcutAction
    ) -> KeyboardShortcuts.ValidationResult {
        guard let duplicate = TraceGlobalShortcutAction.allCases.first(
            where: {
                $0 != action
                    && KeyboardShortcuts.getShortcut(for: $0.name) == shortcut
            }
        ) else {
            return .allow
        }

        return .disallow(
            reason: "Already assigned to \(duplicate.title)."
        )
    }
}

enum TraceGlobalShortcutLegacyStorage {
    private static let assignmentsKey = "TraceGlobalShortcutAssignments"

    static func remove(from defaults: UserDefaults) {
        defaults.removeObject(forKey: assignmentsKey)
    }
}

struct TraceGlobalShortcutActionState: Equatable {
    let assignment: KeyboardShortcuts.Shortcut?
    let isActive: Bool
    let message: String?

    var isUnassigned: Bool {
        assignment == nil
    }
}

struct TraceGlobalShortcutsSnapshot: Equatable {
    private var states:
        [TraceGlobalShortcutAction: TraceGlobalShortcutActionState]

    init(
        states:
            [TraceGlobalShortcutAction: TraceGlobalShortcutActionState] = [:]
    ) {
        self.states = states
    }

    func assignment(
        for action: TraceGlobalShortcutAction
    ) -> KeyboardShortcuts.Shortcut? {
        state(for: action).assignment
    }

    func state(
        for action: TraceGlobalShortcutAction
    ) -> TraceGlobalShortcutActionState {
        states[action] ?? TraceGlobalShortcutActionState(
            assignment: nil,
            isActive: false,
            message: nil
        )
    }
}

@MainActor
enum TraceGlobalShortcutMenuPresentation {
    static func apply(
        _ snapshot: TraceGlobalShortcutsSnapshot,
        to items: [TraceGlobalShortcutAction: [NSMenuItem]]
    ) {
        for action in TraceGlobalShortcutAction.allCases {
            guard let actionItems = items[action] else {
                continue
            }
            for item in actionItems {
                apply(
                    snapshot.assignment(for: action),
                    action: action,
                    to: item
                )
            }
        }
    }

    private static func apply(
        _ shortcut: KeyboardShortcuts.Shortcut?,
        action: TraceGlobalShortcutAction,
        to item: NSMenuItem
    ) {
        if let shortcut {
            guard let keyEquivalent = shortcut.nsMenuItemKeyEquivalent else {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
                return
            }
            item.keyEquivalent = keyEquivalent
            item.keyEquivalentModifierMask = shortcut.modifiers
            return
        }

        switch action {
        case .newBlankTrace:
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
        case .captureFrontmostApp:
            item.keyEquivalent = "n"
            item.keyEquivalentModifierMask = [.command]
        }
    }
}

@MainActor
final class TraceGlobalShortcutManager {
    var onAction: ((TraceGlobalShortcutAction) -> Void)?
    var onChange: ((TraceGlobalShortcutsSnapshot) -> Void)?

    private let legacyDefaults: UserDefaults
    private var started = false

    init(legacyDefaults: UserDefaults = .standard) {
        self.legacyDefaults = legacyDefaults
    }

    var snapshot: TraceGlobalShortcutsSnapshot {
        let duplicate = duplicateShortcut
        var states:
            [TraceGlobalShortcutAction: TraceGlobalShortcutActionState] = [:]

        for action in TraceGlobalShortcutAction.allCases {
            let assignment = KeyboardShortcuts.getShortcut(for: action.name)
            states[action] = TraceGlobalShortcutActionState(
                assignment: assignment,
                isActive:
                    started
                    && assignment != nil
                    && duplicate == nil
                    && KeyboardShortcuts.isEnabled(for: action.name),
                message: duplicate == nil
                    ? nil
                    : "Also assigned to another Trace action."
            )
        }

        return TraceGlobalShortcutsSnapshot(states: states)
    }

    func start() {
        guard !started else {
            return
        }
        TraceGlobalShortcutLegacyStorage.remove(from: legacyDefaults)
        started = true
        for action in TraceGlobalShortcutAction.allCases {
            KeyboardShortcuts.onKeyUp(for: action.name) {
                [weak self] in
                self?.onAction?(action)
            }
        }
        applyDuplicatePolicy()
        notifyChange()
    }

    func stop() {
        guard started else {
            return
        }
        for action in TraceGlobalShortcutAction.allCases {
            KeyboardShortcuts.removeHandler(for: action.name)
        }
        KeyboardShortcuts.enable(
            TraceGlobalShortcutAction.allCases.map(\.name)
        )
        started = false
        notifyChange()
    }

    func shortcutsDidChange() {
        applyDuplicatePolicy()
        notifyChange()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            [weak self] in
            self?.notifyChange()
        }
    }

    private var duplicateShortcut: KeyboardShortcuts.Shortcut? {
        let assignments = TraceGlobalShortcutAction.allCases.compactMap {
            KeyboardShortcuts.getShortcut(for: $0.name)
        }
        guard assignments.count == TraceGlobalShortcutAction.allCases.count,
              Set(assignments).count == 1
        else {
            return nil
        }
        return assignments[0]
    }

    private func applyDuplicatePolicy() {
        let names = TraceGlobalShortcutAction.allCases.map(\.name)
        KeyboardShortcuts.enable(names)
        if duplicateShortcut != nil {
            KeyboardShortcuts.disable(names)
        }
    }

    private func notifyChange() {
        onChange?(snapshot)
    }
}
