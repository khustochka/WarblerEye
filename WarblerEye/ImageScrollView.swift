//
//  ImageScrollView.swift
//  WarblerEye
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

    /// Called for an arrow key that should page rather than pan, with the
    /// direction (-1 left, 1 right) and the modifiers held.
    var onPage: ((Int, NSEvent.ModifierFlags) -> Void)?

    /// Called for a key the image view does not consume, so the owning view can
    /// act on zoom and paging shortcuts.
    var onKey: ((String, NSEvent.ModifierFlags) -> Bool)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()
        let imageView = DraggableImageView()
        imageView.scrollViewProvider = { [weak scrollView] in scrollView }
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
        guard let imageView = scrollView.documentView as? DraggableImageView else { return }
        imageView.onDrag = { [weak scrollView] delta in
            guard let scrollView else { return }
            Coordinator.pan(scrollView, by: delta)
        }
        imageView.onPage = onPage
        imageView.onKey = onKey

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
        if let window = scrollView.window, window.firstResponder !== imageView {
            window.makeFirstResponder(imageView)
        }

        // The document is exactly the drawn image; the clip view centres it
        // when it is smaller than the viewport.
        if imageView.frame.size != drawnSize {
            imageView.frame = CGRect(origin: .zero, size: drawnSize)
            scrollView.window?.invalidateCursorRects(for: imageView)
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
        /// Scrolls by a delta in points, clamped so the image cannot be pushed
        /// past its own edges.
        static func pan(_ scrollView: NSScrollView, by delta: CGSize) {
            guard let document = scrollView.documentView else { return }
            let viewport = scrollView.contentView.bounds.size
            let content = document.frame.size
            let origin = scrollView.contentView.bounds.origin

            // An axis that fits is centred by the clip view; leave it alone.
            let x = content.width > viewport.width
                ? min(max(origin.x + delta.width, 0), content.width - viewport.width)
                : origin.x
            let y = content.height > viewport.height
                ? min(max(origin.y + delta.height, 0), content.height - viewport.height)
                : origin.y

            scrollView.contentView.scroll(to: CGPoint(x: x, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

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

/// An image view that pans its scroll view when dragged or arrowed.
///
/// Key handling lives here rather than in SwiftUI: the scroll view sits ahead
/// of SwiftUI's focusable wrapper in the responder chain, so `onKeyPress` never
/// sees the arrow keys.
final class DraggableImageView: NSImageView {
    var onDrag: ((CGSize) -> Void)?
    var onPage: ((Int, NSEvent.ModifierFlags) -> Void)?
    var onKey: ((String, NSEvent.ModifierFlags) -> Bool)?
    var scrollViewProvider: (() -> NSScrollView?)?

    override var acceptsFirstResponder: Bool { true }

    /// Take keyboard focus as soon as the view is in a window, so the bare-key
    /// shortcuts work on a freshly opened image without a click first.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // The window is not key yet at this point in the open sequence.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        // Arrow keys carry .numericPad (and sometimes .function) from the
        // system, so those are not part of what the user actually held.
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function])
        let bare = modifiers.isEmpty

        switch Int(event.keyCode) {
        case 123, 124, 125, 126:  // left, right, down, up
            // Bare arrows always move within the image; paging lives on the
            // Command-modified shortcuts.
            if bare {
                onDrag?(Self.panDelta(keyCode: event.keyCode))
                return
            }
            if event.keyCode == 123 || event.keyCode == 124 {
                onPage?(event.keyCode == 123 ? -1 : 1, modifiers)
                return
            }
        default:
            break
        }

        if let characters = event.charactersIgnoringModifiers,
           onKey?(characters, modifiers) == true {
            return
        }
        super.keyDown(with: event)
    }

    /// How far one arrow press pans, in points.
    private static func panDelta(keyCode: UInt16) -> CGSize {
        let stride: CGFloat = 80
        switch keyCode {
        case 123: return CGSize(width: -stride, height: 0)
        case 124: return CGSize(width: stride, height: 0)
        // The scroll origin grows upward, so a down arrow decreases it.
        case 125: return CGSize(width: 0, height: -stride)
        default: return CGSize(width: 0, height: stride)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard canPan else { return }
        NSCursor.closedHand.set()
        // Dragging the image right should reveal content to its left, so the
        // scroll origin moves opposite to the cursor.
        onDrag?(CGSize(width: -event.deltaX, height: event.deltaY))
    }

    override func mouseUp(with event: NSEvent) {
        // Restore the resting cursor after a drag.
        window?.invalidateCursorRects(for: self)
    }

    /// Whether any part of the image lies outside the viewport.
    private var canPan: Bool {
        guard let clip = (enclosingScrollView ?? scrollViewProvider?())?.contentView else {
            return false
        }
        return frame.width > clip.bounds.width + 1
            || frame.height > clip.bounds.height + 1
    }

    override func resetCursorRects() {
        // Only advertise dragging when there is somewhere to drag to.
        guard canPan else { return }
        addCursorRect(bounds, cursor: .openHand)
    }
}
