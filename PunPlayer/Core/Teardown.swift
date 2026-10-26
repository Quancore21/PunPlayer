//
//  PunPlayer — Core/Teardown.swift
//  Collects the "undo" step of everything a long-lived object registers (notification observers,
//  time observers, remote-command targets) and runs each exactly once, in reverse order.
//  PunPlayer is licensed under GPLv3.
//

import Foundation

final class TeardownBag {
    private var actions: [() -> Void] = []
    private(set) var isTornDown = false

    var count: Int { actions.count }

    /// Registers an undo action. If the bag was already torn down the action runs immediately,
    /// so a late registration cannot leak.
    func add(_ action: @escaping () -> Void) {
        if isTornDown {
            action()
        } else {
            actions.append(action)
        }
    }

    /// Runs every registered action once, newest first. Calling it again does nothing.
    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        let pending = actions
        actions.removeAll()
        for action in pending.reversed() { action() }
    }

    deinit { tearDown() }
}
