# WarblerEye

A fast, keyboard-driven image viewer for macOS. Open one photo and page through
every image in its folder, zoom in on detail, check the metadata, and trash the
rejects as you go. It's built for culling a burst of shots from a shoot.

## Features

- **Folder browsing.** Opening an image loads its whole folder, sorted the way
  Finder sorts it. Neighbouring images are prefetched, so paging is instant.
- **Jump navigation.** Step one image at a time, or skip 10 or 100 at once.
- **Zoom and pan.** Fit to window or view at actual size. Zooming keeps the
  point at the centre of the view in place. Pan by dragging or with the arrow
  keys. Images smaller than the window are never enlarged.
- **Keep Zoom and Position.** Hold the same zoom and spot while you page, so
  you can compare one detail, such as an eye or a feather, across a burst.
- **Quick culling.** Move the current image to the Trash with ⌘⌫ and go
  straight to the next one. ⌘Z brings it back.
- **Metadata at a glance.** The status bar shows position, zoom, dimensions,
  color model, format, file size and capture time. Press `I` for a panel with
  every property the file holds (EXIF, GPS, TIFF and more).
- **One window per image.** Each file you open from Finder gets its own window.
- **Neutral backdrop.** Images sit on a fixed dark grey, so colors look the
  same in light and dark mode and the edges of dark photos stay visible.

Supported formats: JPEG, PNG, HEIC/HEIF, GIF, TIFF, BMP and WebP.

## Requirements

macOS 26.5 or later.

## Installation

There are no prebuilt releases yet, so you build WarblerEye from source with
Xcode:

1. Clone the repository and open `WarblerEye.xcodeproj` in Xcode.
2. Choose **Product › Archive**, then **Distribute App › Custom › Copy App**,
   and move `WarblerEye.app` into `/Applications`.

   For a quick try instead, press ⌘R to build and run it in place.

The project builds and runs without any setup. To sign with your own Apple
developer team, create `Config/Local.xcconfig` containing
`DEVELOPMENT_TEAM = <your team ID>`.

To make WarblerEye your default viewer, select an image in Finder, press ⌘I,
pick WarblerEye under **Open with**, and click **Change All…**.

## Usage

Open an image by double-clicking it in Finder (if WarblerEye is the default),
dragging it onto the app icon, or with **File › Open…** (⌘O). The rest of its
folder is then a keypress away.

### Keyboard shortcuts

| Action                       | Shortcut                |
| ---------------------------- | ----------------------- |
| Next / previous image        | ⌘→ / ⌘← (or Space for next) |
| Forward / back 10 images     | ⌥⌘→ / ⌥⌘←               |
| Forward / back 100 images    | ⌃⌘→ / ⌃⌘←               |
| Pan the image                | Arrow keys, or drag     |
| Zoom in / out                | ⌘+ / ⌘− (or `+` / `-`)  |
| Actual size                  | ⌘0 (or `0`)             |
| Fit to window                | ⌘/ (or `/`)             |
| Keep zoom and position       | ⌘L (or `L`)             |
| Show / hide metadata panel   | `I`                     |
| Move to Trash                | ⌘⌫                      |
| Undo Move to Trash           | ⌘Z                      |
| Open a file                  | ⌘O                      |

Zoom commands are in the **View** menu and navigation is in the **Image**
menu, in case you forget a shortcut.

## License

WarblerEye is released under the [MIT License](LICENSE).

The app icon and its source photo (`Tools/icon-source.jpg`) are
© 2026 Vitalii Khustochka, all rights reserved, and are not covered by the MIT
License.
