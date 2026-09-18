//
//  ContentView.swift
//  PloceusView
//
//  Created by Vitalii Khustochka on 2026-09-18.
//

import SwiftUI

struct ContentView: View {
    let browser: ImageBrowser

    /// How the image is sized: scaled to the window, or at an explicit scale
    /// where 1 is one image pixel per point.
    enum ZoomMode: Equatable {
        case fit
        case scale(CGFloat)
    }

    @State private var zoomMode: ZoomMode = .fit

    /// Viewport and image size, mirrored into state so the menu commands can
    /// zoom relative to the current on-screen size.
    @State private var viewportSize: CGSize = .zero
    @State private var imageSize: CGSize = .zero

    /// Size the image is actually drawn at, used to report the zoom percentage
    /// relative to the file's pixel dimensions.
    @State private var displayedWidth: CGFloat = 0

    /// Whether the image area holds keyboard focus, which is what lets the
    /// arrow keys page through the folder.
    @FocusState private var imageFocused: Bool

    private static let zoomRange: ClosedRange<CGFloat> = 0.1...20

    /// Neutral surround for the image. Deliberately not pure black, which would
    /// hide the edges of a dark photo, and fixed rather than theme-dependent so
    /// colors are judged against a constant ground.
    private static let backdrop = Color(white: 0.12)

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Self.backdrop)

            statusBar
        }
        .frame(minWidth: 620, minHeight: 400)
        .navigationTitle(browser.current?.lastPathComponent ?? "PloceusView")
        .background(
            WindowTitleView(title: browser.current?.lastPathComponent ?? "PloceusView")
                .frame(width: 0, height: 0)
        )
        .onAppear { imageFocused = true }
        .onChange(of: browser.current) {
            // Reset zoom so a new image always arrives fitted to the window.
            zoomMode = .fit
            imageFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
            scale(by: 1.25, in: viewportSize, image: imageSize)
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
            scale(by: 1 / 1.25, in: viewportSize, image: imageSize)
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomActual)) { _ in
            zoomMode = .scale(1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomFit)) { _ in
            zoomMode = .fit
        }
        // The title bar blends with the dark backdrop behind it, so the window
        // chrome has to draw its title as if on a dark surface.
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if let image = browser.image {
            GeometryReader { proxy in
                let drawn = Self.drawnSize(of: image.size, in: proxy.size, mode: zoomMode)

                ImageScrollView(image: image, drawnSize: drawn)
                .focusable()
                .focusEffectDisabled()
                .focused($imageFocused)
                .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                    let direction = press.key == .leftArrow ? -1 : 1
                    browser.advance(by: direction * Self.step(for: press.modifiers))
                    return .handled
                }
                .onKeyPress(.space) {
                    browser.next()
                    return .handled
                }
                .onKeyPress(keys: ["+", "=", "-", "0", "/"]) { press in
                    switch press.key.character {
                    case "+", "=": scale(by: 1.25, in: proxy.size, image: image.size)
                    case "-": scale(by: 1 / 1.25, in: proxy.size, image: image.size)
                    case "/": zoomMode = .fit
                    default: zoomMode = .scale(1)
                    }
                    return .handled
                }
                .onChange(of: drawn.width, initial: true) { displayedWidth = drawn.width }
                .onChange(of: proxy.size, initial: true) { viewportSize = proxy.size }
                .onChange(of: image.size, initial: true) { imageSize = image.size }
            }
        } else {
            ContentUnavailableView {
                Label("No Image", systemImage: "photo")
            } description: {
                Text(browser.errorMessage ?? "Open an image, or double-click one in Finder.")
            } actions: {
                Button("Open…") { browser.showOpenPanel() }
            }
        }
    }

    /// The status bar, mirroring the fields a photo viewer conventionally shows.
    private var statusBar: some View {
        HStack(spacing: 16) {
            if let position = browser.position {
                Text(position)
            }
            if let percent = zoomPercent {
                Text(percent)
            }
            if let info = browser.info {
                Text(info.dimensions)
                Text(info.colorModel)
                Text(info.format)
                Text(info.fileSize)
                if let timestamp = info.timestamp {
                    Text(timestamp)
                }
            }
            if let name = browser.current?.lastPathComponent {
                Text(name)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11).monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }

    /// Scale of the drawn image against the file's true pixel width.
    private var zoomPercent: String? {
        guard let pixelWidth = browser.info?.pixelSize.width, pixelWidth > 0,
              displayedWidth > 0 else { return nil }
        return "\(Int((displayedWidth / pixelWidth * 100).rounded()))%"
    }

    /// The size an image is drawn at under the current mode.
    private static func drawnSize(
        of image: CGSize,
        in viewport: CGSize,
        mode: ZoomMode
    ) -> CGSize {
        guard image.width > 0, image.height > 0 else { return .zero }
        let factor: CGFloat
        switch mode {
        case .fit:
            factor = fitScale(of: image, in: viewport)
        case .scale(let scale):
            factor = scale
        }
        return CGSize(width: image.width * factor, height: image.height * factor)
    }

    /// The scale at which the image exactly fits the viewport.
    private static func fitScale(of image: CGSize, in viewport: CGSize) -> CGFloat {
        guard image.width > 0, image.height > 0 else { return 1 }
        return min(viewport.width / image.width, viewport.height / image.height)
    }

    /// How far an arrow key jumps, given the modifiers held with it.
    private static func step(for modifiers: EventModifiers) -> Int {
        if modifiers.contains(.control) && modifiers.contains(.command) { return 100 }
        if modifiers.contains(.option) && modifiers.contains(.command) { return 10 }
        return 1
    }

    /// Zooms relative to whatever is on screen now, so the first step out of
    /// fit mode continues from the size the user is looking at.
    private func scale(by factor: CGFloat, in viewport: CGSize, image: CGSize) {
        let current: CGFloat
        switch zoomMode {
        case .fit:
            current = Self.fitScale(of: image, in: viewport)
        case .scale(let scale):
            current = scale
        }
        zoomMode = .scale((current * factor).clamped(to: Self.zoomRange))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    ContentView(browser: ImageBrowser())
}
