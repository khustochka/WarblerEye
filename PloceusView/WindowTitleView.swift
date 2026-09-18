//
//  WindowTitleView.swift
//  PloceusView
//

import AppKit
import SwiftUI

/// Centres the filename in the title bar.
///
/// AppKit left-aligns a window's own title, so the text is drawn as a separate
/// view pinned to the centre of the title bar and the real title is hidden.
struct WindowTitleView: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { install(from: view, context: context) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.label?.stringValue = title
        DispatchQueue.main.async { install(from: nsView, context: context) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var label: NSTextField?
    }

    /// Adds the label to the title bar once the view is in a window.
    private func install(from view: NSView, context: Context) {
        guard let window = view.window else { return }

        window.titleVisibility = .hidden

        guard context.coordinator.label == nil,
              // The theme frame is the title bar's superview; without it there
              // is nowhere to pin the label.
              let frameView = window.contentView?.superview else {
            context.coordinator.label?.stringValue = title
            return
        }

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        frameView.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: frameView.centerXAnchor),
            label.topAnchor.constraint(equalTo: frameView.topAnchor, constant: 6),
            // Leave room for the traffic lights on either side.
            label.leadingAnchor.constraint(
                greaterThanOrEqualTo: frameView.leadingAnchor, constant: 80
            ),
            label.trailingAnchor.constraint(
                lessThanOrEqualTo: frameView.trailingAnchor, constant: -80
            ),
        ])

        context.coordinator.label = label
    }
}
