import XCTest
@testable import PunCore

/// P3: callbacks registered by a long-lived object must be released with it.
final class TeardownTests: XCTestCase {

    func testRunsEveryActionOnceNewestFirst() {
        let bag = TeardownBag()
        var order: [Int] = []
        bag.add { order.append(1) }
        bag.add { order.append(2) }
        bag.add { order.append(3) }
        bag.tearDown()
        XCTAssertEqual(order, [3, 2, 1])
        XCTAssertEqual(bag.count, 0)
    }

    func testTearingDownTwiceDoesNothing() {
        let bag = TeardownBag()
        var runs = 0
        bag.add { runs += 1 }
        bag.tearDown()
        bag.tearDown()
        XCTAssertEqual(runs, 1)
        XCTAssertTrue(bag.isTornDown)
    }

    func testDeinitRunsTheActions() {
        var runs = 0
        do {
            let bag = TeardownBag()
            bag.add { runs += 1 }
            withExtendedLifetime(bag) { XCTAssertEqual(runs, 0, "nothing runs while the owner is alive") }
        }
        XCTAssertEqual(runs, 1)
    }

    func testARegistrationAfterTearDownRunsImmediately() {
        let bag = TeardownBag()
        bag.tearDown()
        var runs = 0
        bag.add { runs += 1 }
        XCTAssertEqual(runs, 1, "a late registration must not leak")
    }

    // MARK: the scenario from the report: recreating the owner must not duplicate callbacks

    /// Same pattern as PlayerEngine.observe(_:handler:): register on the notification center,
    /// remember how to unregister.
    private final class Listener {
        private let teardown = TeardownBag()

        init(name: Notification.Name, onEvent: @escaping () -> Void) {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
                onEvent()
            }
            teardown.add { NotificationCenter.default.removeObserver(token) }
        }

        func stop() { teardown.tearDown() }
    }

    func testRecreatingTheOwnerDoesNotMultiplyCallbacks() {
        let name = Notification.Name("pun.test.\(UUID().uuidString)")
        var handled = 0

        // three owners come and go (for example the engine being rebuilt)
        for _ in 0..<3 {
            var listener: Listener? = Listener(name: name) { handled += 1 }
            listener = nil
            _ = listener
        }
        let current = Listener(name: name) { handled += 1 }
        defer { current.stop() }

        NotificationCenter.default.post(name: name, object: nil)

        XCTAssertEqual(handled, 1, "exactly one callback for one event, from the live owner only")
    }

    func testAStoppedOwnerReceivesNothingMore() {
        let name = Notification.Name("pun.test.\(UUID().uuidString)")
        var handled = 0
        let listener = Listener(name: name) { handled += 1 }

        NotificationCenter.default.post(name: name, object: nil)
        listener.stop()
        NotificationCenter.default.post(name: name, object: nil)

        XCTAssertEqual(handled, 1)
    }
}
