//
//  ImageScrollView.swift
//  PloceusView
//

import AppKit
import SwiftUI

/// A scrolling image that stays centred and holds its centre point when the
/// zoom changes.
///
/// SwiftUI's ScrollView cannot read or set its content offset, which is what
/// preserving the centre requires, so this wraps NSScrollView directly.
struct ImageScrollView: NSViewRepresentable {
    let image: NSImage
    let drawnSize: CGSize

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()
        let imageView = NSImageView()
        // The frame is set to the drawn size, so the image fills it exactly.
        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = false
        scrollView.documentView = imageView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        // The image itself is the focus; scrollers should not frame it.
        scrollView.scrollerStyle = .overlay
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let imageView = scrollView.documentView as? NSImageView else { return }

        let viewport = scrollView.contentView.bounds.size
        let oldSize = imageView.frame.size
        // Where the centre of the viewport sits in the image, as a fraction.
        let anchor = context.coordinator.anchor(
            origin: scrollView.contentView.bounds.origin,
            contentSize: oldSize,
            viewport: viewport
        )

        if imageView.image !== image {
            imageView.image = image
        }

        // The document is exactly the drawn image; the clip view centres it
        // when it is smaller than the viewport.
        if imageView.frame.size != drawnSize {
            imageView.frame = CGRect(origin: .zero, size: drawnSize)
        }

        // Restoring the anchor is only meaningful while the image overflows
        // the viewport. Once it fits on an axis, CenteringClipView centres it
        // with a negative origin that a clamped scroll would fight, so the
        // clip view is left to position that axis itself.
        let overflows = drawnSize.width > viewport.width
            || drawnSize.height > viewport.height
        if viewport.width > 0, oldSize != .zero, oldSize != drawnSize, overflows {
            context.coordinator.restore(
                anchor: anchor,
                in: scrollView,
                contentSize: drawnSize,
                viewport: viewport
            )
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        /// The point of the content at the viewport's centre, as a fraction of
        /// the content size.
        func anchor(origin: CGPoint, contentSize: CGSize, viewport: CGSize) -> CGPoint {
            guard contentSize.width > 0, contentSize.height > 0 else {
                return CGPoint(x: 0.5, y: 0.5)
            }
            return CGPoint(
                x: (origin.x + viewport.width / 2) / contentSize.width,
                y: (origin.y + viewport.height / 2) / contentSize.height
            )
        }

        /// Scrolls so that `anchor` is back at the viewport's centre.
        func restore(
            anchor: CGPoint,
            in scrollView: NSScrollView,
            contentSize: CGSize,
            viewport: CGSize
        ) {
            let target = CGPoint(
                x: anchor.x * contentSize.width - viewport.width / 2,
                y: anchor.y * contentSize.height - viewport.height / 2
            )
            // An axis that fits is centred by the clip view, so leave its
            // current origin alone rather than clamping it to zero.
            let current = scrollView.contentView.bounds.origin
            let x = contentSize.width > viewport.width
                ? min(max(target.x, 0), contentSize.width - viewport.width)
                : current.x
            let y = contentSize.height > viewport.height
                ? min(max(target.y, 0), contentSize.height - viewport.height)
                : current.y
            scrollView.contentView.scroll(to: CGPoint(x: x, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

/// Keeps a document smaller than the viewport centred rather than pinned to a
/// corner, which is the standard AppKit idiom for a centred canvas.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }

        let document = documentView.frame
        if rect.width > document.width {
            rect.origin.x = (document.width - rect.width) / 2
        }
        if rect.height > document.height {
            rect.origin.y = (document.height - rect.height) / 2
        }
        return rect
    }
}
