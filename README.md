# FocusStackPro

Professional focus stacking for iPadOS. Import RAW images (.ARW, .CR3, .NEF, .DNG), auto-align, generate depth map, blend with 3 methods, export TIFF/JPEG.

Requires iPadOS 17.0+. Built with SwiftUI, Core Image, Vision, Accelerate.

MIT License.

## Features

- Import multiple RAW/images via fileImporter (Files app, USB-C, cloud)
- Thumbnails + EXIF focus distance display + auto-sort by focus
- Align images (Vision translational registration, middle image as reference)
- Depth map (Laplacian sharpness per pixel, argmax → source index)
- 3 stacking methods: Quick (weighted avg), Depth Map (mask blend), Pyramid (simplified)
- Split view UI: sidebar + canvas, pinch zoom, drag pan
- Progress bar + status messages during processing
- Export TIFF/JPEG via fileExporter

## Build (no Mac required)

This project builds on GitHub Actions using free macOS runners for public repos.

```bash
# Local build (requires Xcode on macOS)
xcodebuild build \
  -project FocusStackPro.xcodeproj \
  -scheme FocusStackPro \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  CODE_SIGNING_ALLOWED=NO
```

## Requirements

- iPadOS 17.0+
- iPad only (not iPhone)
- No external dependencies

## License

MIT — see [LICENSE](LICENSE).
