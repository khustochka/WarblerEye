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

    private static let zoomRange: ClosedRange<CGFloat> = 0.1...20

    var body: some View {
        content
            .frame(minWidth: 480, minHeight: 360)
            .navigationTitle(browser.current?.lastPathComponent ?? "PloceusView")
            .navigationSubtitle(browser.position ?? "")
            .toolbar { toolbar }
            // Reset zoom so a new image always arrives fitted to the window.
            .onChange(of: browser.current) { zoom = 1 }
    }

    @ViewBuilder
    private var content: some View {
        if let image = browser.image {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(
                            width: proxy.size.width * zoom,
                            height: proxy.size.height * zoom
                        )
                        // Keep the image centred while it is smaller than the viewport.
                        .frame(
                            minWidth: proxy.size.width,
                            minHeight: proxy.size.height
                        )
                }
                .background(.background)
            }
        } else {
            ContentUnavailableView {
                Label("No Image", systemImage: "photo")
            } description: {
                Text(browser.errorMessage ?? "Open a image, or double-click on one in Finder.")
            } actions: {
                Button("Open…") { browser.showOpenPanel() }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { browser.previous() } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(!browser.canGoPrevious)

            Button { browser.next() } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(!browser.canGoNext)
        }

        ToolbarItemGroup {
            Button { scale(by: 1 / 1.25) } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .disabled(browser.image == nil || zoom <= Self.zoomRange.lowerBound)

            Button { zoom = 1 } label: {
                Label("Fit to Window", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .disabled(browser.image == nil || zoom == 1)

            Button { scale(by: 1.25) } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .disabled(browser.image == nil || zoom >= Self.zoomRange.upperBound)
        }
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
