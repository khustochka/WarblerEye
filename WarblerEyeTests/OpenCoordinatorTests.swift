//
//  OpenCoordinatorTests.swift
//  WarblerEyeTests
//

import Foundation
import Testing
@testable import WarblerEye

/// Routing files from Finder to empty windows. These cover the case before
/// the scene can open windows of its own, so every file waits for an offer.
@MainActor
struct OpenCoordinatorTests {

    /// Stands in for a window: something with an identity that records the
    /// files it is shown.
    @MainActor
    private final class Window {
        var shown: [String] = []
        var token: ObjectIdentifier { ObjectIdentifier(self) }
        func offer(to coordinator: OpenCoordinator) {
            coordinator.offerIdle(token) { [unowned self] in shown.append($0.lastPathComponent) }
        }
    }

    private let coordinator = OpenCoordinator()
    private let a = URL(fileURLWithPath: "/tmp/a.jpg")
    private let b = URL(fileURLWithPath: "/tmp/b.jpg")

    @Test func fileGoesToAWaitingWindow() {
        let window = Window()
        window.offer(to: coordinator)
        coordinator.receive([a])
        #expect(window.shown == ["a.jpg"])
    }

    @Test func filesWaitForWindowsInOrder() {
        coordinator.receive([a, b])
        let first = Window()
        let second = Window()
        first.offer(to: coordinator)
        second.offer(to: coordinator)
        #expect(first.shown == ["a.jpg"])
        #expect(second.shown == ["b.jpg"])
    }

    @Test func eachOfferTakesOneFile() {
        let window = Window()
        window.offer(to: coordinator)
        coordinator.receive([a, b])
        #expect(window.shown == ["a.jpg"])
    }

    @Test func reofferingAWindowDoesNotQueueItTwice() {
        let window = Window()
        let other = Window()
        window.offer(to: coordinator)
        window.offer(to: coordinator)
        other.offer(to: coordinator)
        coordinator.receive([a, b])
        #expect(window.shown == ["a.jpg"])
        #expect(other.shown == ["b.jpg"])
    }

    @Test func withdrawnWindowGetsNothing() {
        let window = Window()
        window.offer(to: coordinator)
        coordinator.withdraw(window.token)
        coordinator.receive([a])
        #expect(window.shown.isEmpty)
    }
}
