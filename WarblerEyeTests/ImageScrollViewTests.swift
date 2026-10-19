//
//  ImageScrollViewTests.swift
//  WarblerEyeTests
//

import AppKit
import Testing
@testable import WarblerEye

/// The scroll arithmetic behind zooming about the centre and panning.
@MainActor
struct ImageScrollViewTests {

    private let coordinator = ImageScrollView.Coordinator()
    private let viewport = CGSize(width: 100, height: 100)

    /// A scroll view laid out as the app builds it, with a document of `size`.
    private func scrollView(document size: CGSize) -> NSScrollView {
        let scrollView = NSScrollView(frame: CGRect(origin: .zero, size: viewport))
        scrollView.contentView = CenteringClipView()
        scrollView.documentView = NSView(frame: CGRect(origin: .zero, size: size))
        return scrollView
    }

    private func origin(_ scrollView: NSScrollView) -> CGPoint {
        scrollView.contentView.bounds.origin
    }

    @Test func anchorIsTheCentreAsAFraction() {
        let anchor = coordinator.anchor(
            origin: CGPoint(x: 150, y: 100),
            contentSize: CGSize(width: 400, height: 300),
            viewport: viewport
        )
        #expect(anchor == CGPoint(x: 0.5, y: 0.5))
    }

    @Test func anchorOfEmptyContentIsTheMiddle() {
        let anchor = coordinator.anchor(origin: .zero, contentSize: .zero, viewport: viewport)
        #expect(anchor == CGPoint(x: 0.5, y: 0.5))
    }

    @Test func restoreKeepsTheAnchorCentredAcrossAZoom() {
        let before = CGSize(width: 400, height: 300)
        let anchor = coordinator.anchor(
            origin: CGPoint(x: 50, y: 25), contentSize: before, viewport: viewport
        )

        let after = CGSize(width: 800, height: 600)
        let scrollView = scrollView(document: after)
        coordinator.restore(anchor: anchor, in: scrollView, contentSize: after, viewport: viewport)

        #expect(origin(scrollView) == CGPoint(x: 150, y: 100))
        let restored = coordinator.anchor(
            origin: origin(scrollView), contentSize: after, viewport: viewport
        )
        #expect(restored == anchor)
    }

    @Test func restoreClampsToTheContentEdges() {
        let content = CGSize(width: 400, height: 300)
        let scrollView = scrollView(document: content)
        coordinator.restore(
            anchor: CGPoint(x: 1, y: 0), in: scrollView, contentSize: content, viewport: viewport
        )
        #expect(origin(scrollView) == CGPoint(x: 300, y: 0))
    }

    @Test func restoreLeavesAFittingAxisCentred() {
        let content = CGSize(width: 50, height: 300)
        let scrollView = scrollView(document: content)
        coordinator.restore(
            anchor: CGPoint(x: 0.5, y: 0.5), in: scrollView, contentSize: content, viewport: viewport
        )
        #expect(origin(scrollView) == CGPoint(x: -25, y: 100))
    }

    @Test func panMovesWithinTheContent() {
        let scrollView = scrollView(document: CGSize(width: 400, height: 300))
        ImageScrollView.Coordinator.pan(scrollView, by: CGSize(width: 30, height: 40))
        #expect(origin(scrollView) == CGPoint(x: 30, y: 40))
    }

    @Test func panStopsAtTheEdges() {
        let scrollView = scrollView(document: CGSize(width: 400, height: 300))
        ImageScrollView.Coordinator.pan(scrollView, by: CGSize(width: 1000, height: -1000))
        #expect(origin(scrollView) == CGPoint(x: 300, y: 0))
    }

    @Test func panLeavesAFittingAxisAlone() {
        let scrollView = scrollView(document: CGSize(width: 50, height: 300))
        ImageScrollView.Coordinator.pan(scrollView, by: CGSize(width: 30, height: 30))
        #expect(origin(scrollView) == CGPoint(x: -25, y: 30))
    }
}
