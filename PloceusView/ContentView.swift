//
//  ContentView.swift
//  PloceusView
//
//  Created by Vitalii Khustochka on 2026-09-18.
//

import SwiftUI

struct ContentView: View {
    let browser: ImageBrowser

    /// Zoom factor applied on top of the fit-to-window size. 1 means "fit".
    @State private var zoom: CGFloat = 1

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
        .toolbar { toolbar }
        .onAppear { imageFocused = true }
        .onChange(of: browser.current) {
            // Reset zoom so a new image always arrives fitted to the window.
            zoom = 1
            imageFocused = true
        }
        // The toolbar blends with the dark backdrop behind it, so the window
        // chrome has to draw its title and controls as if on a dark surface.
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if let image = browser.image {
            GeometryReader { proxy in
                let drawn = Self.fittedSize(of: image.size, in: proxy.size, zoom: zoom)

                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: drawn.width, height: drawn.height)
                        // Keep the image centred while it is smaller than the viewport.
                        .frame(
                            minWidth: proxy.size.width,
                            minHeight: proxy.size.height
                        )
                }
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
                .onChange(of: drawn.width, initial: true) { displayedWidth = drawn.width }
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { navigate(browser.previous) } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(!browser.canGoPrevious)

            Button { navigate(browser.next) } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(!browser.canGoNext)
        }

        ToolbarItemGroup {
            Button { navigate { scale(by: 1 / 1.25) } } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .disabled(browser.image == nil || zoom <= Self.zoomRange.lowerBound)

            Button { navigate { zoom = 1 } } label: {
                Label("Fit to Window", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .disabled(browser.image == nil || zoom == 1)

            Button { navigate { scale(by: 1.25) } } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .disabled(browser.image == nil || zoom >= Self.zoomRange.upperBound)
        }
    }

    /// The size an image is drawn at: fitted to the viewport, times the zoom.
    private static func fittedSize(
        of image: CGSize,
        in viewport: CGSize,
        zoom: CGFloat
    ) -> CGSize {
        guard image.width > 0, image.height > 0 else { return .zero }
        let fit = min(viewport.width / image.width, viewport.height / image.height)
        return CGSize(
            width: image.width * fit * zoom,
            height: image.height * fit * zoom
        )
    }

    /// How far an arrow key jumps, given the modifiers held with it.
    private static func step(for modifiers: EventModifiers) -> Int {
        if modifiers.contains(.control) && modifiers.contains(.command) { return 100 }
        if modifiers.contains(.option) && modifiers.contains(.command) { return 10 }
        return 1
    }

    /// Runs a toolbar action and returns keyboard focus to the image, so the
    /// arrow keys keep working after a click.
    private func navigate(_ action: () -> Void) {
        action()
        imageFocused = true
    }

    private func scale(by factor: CGFloat) {
        zoom = (zoom * factor).clamped(to: Self.zoomRange)
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
