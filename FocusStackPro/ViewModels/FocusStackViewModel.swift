import SwiftUI
import CoreImage
import UniformTypeIdentifiers

class FocusStackViewModel: ObservableObject {
    @Published var sourceImages: [SourceImageData] = []
    @Published var resultImage: UIImage?
    @Published var depthMap: CIImage?
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var statusMessage = ""
    @Published var selectedImageIndex: Int?
    @Published var stackingMethod: StackingMethod = .depthMap
    @Published var visualizationMode: VisualizationMode = .composite
    @Published var overlayOpacity: Double = 0.5

    private let stackEngine = FocusStackEngine()
    var exportDocument: ImageDocument?

    func importImages(result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            Task { await loadImages(from: urls) }
        }
    }

    @MainActor
    private func loadImages(from urls: [URL]) async {
        statusMessage = "Loading images..."
        isProcessing = true
        progress = 0
        var loaded: [SourceImageData] = []
        for (index, url) in urls.enumerated() {
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = await loadImageData(from: url) {
                    loaded.append(data)
                }
            }
            progress = Double(index + 1) / Double(urls.count)
        }
        sourceImages.append(contentsOf: loaded)
        sortImagesByFocus()
        isProcessing = false
        statusMessage = "Loaded \(loaded.count) images"
    }

    private func loadImageData(from url: URL) async -> SourceImageData? {
        guard let ciImage = CIImage(contentsOf: url) else { return nil }
        return SourceImageData(
            url: url,
            image: ciImage,
            thumbnail: await generateThumbnail(from: ciImage),
            filename: url.lastPathComponent,
            focusDistance: extractFocusDistance(from: ciImage)
        )
    }

    private func generateThumbnail(from image: CIImage) async -> UIImage? {
        let ctx = CIContext()
        let scale = 120 / max(image.extent.width, image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func extractFocusDistance(from image: CIImage) -> Double? {
        guard let exif = image.properties["Exif"] as? [String: Any] else { return nil }
        return exif["SubjectDistance"] as? Double
    }

    private func sortImagesByFocus() {
        sourceImages.sort { ($0.focusDistance ?? 0) < ($1.focusDistance ?? 0) }
    }

    func processStack() {
        guard sourceImages.count >= 2 else { return }
        Task { await performStacking() }
    }

    @MainActor
    private func performStacking() async {
        isProcessing = true
        progress = 0
        statusMessage = "Aligning images..."
        let images = sourceImages.map { $0.image }
        let aligned = await stackEngine.alignImages(images) { p in
            Task { @MainActor in
                self.progress = p * 0.4
                self.statusMessage = "Aligning... \(Int(p * 100))%"
            }
        }
        statusMessage = "Generating depth map..."
        let depthResult = await stackEngine.generateDepthMap(aligned) { p in
            Task { @MainActor in
                self.progress = 0.4 + p * 0.3
                self.statusMessage = "Depth map... \(Int(p * 100))%"
            }
        }
        depthMap = depthResult.depthMap
        statusMessage = "Blending stack..."
        let blended = await stackEngine.blendStack(aligned, depthMap: depthResult, method: stackingMethod) { p in
            Task { @MainActor in
                self.progress = 0.7 + p * 0.3
                self.statusMessage = "Blending... \(Int(p * 100))%"
            }
        }
        resultImage = await convertToUIImage(blended)
        progress = 1.0
        statusMessage = "Complete!"
        isProcessing = false
        if let result = resultImage {
            exportDocument = ImageDocument(image: result)
        }
    }

    private func convertToUIImage(_ ciImage: CIImage) async -> UIImage? {
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    func clearImages() {
        sourceImages.removeAll()
        resultImage = nil
        depthMap = nil
        selectedImageIndex = nil
    }
}

struct SourceImageData {
    let url: URL
    let image: CIImage
    let thumbnail: UIImage?
    let filename: String?
    let focusDistance: Double?
}

enum StackingMethod: String, CaseIterable, Identifiable {
    case weightedAverage = "weighted"
    case depthMap = "depth"
    case pyramid = "pyramid"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weightedAverage: return "Quick"
        case .depthMap: return "Depth Map"
        case .pyramid: return "Pyramid"
        }
    }
}

enum VisualizationMode: String, CaseIterable, Identifiable {
    case composite
    case depthMap
    case sourceAttribution

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .composite: return "Result"
        case .depthMap: return "Depth Map"
        case .sourceAttribution: return "Sources"
        }
    }

    var icon: String {
        switch self {
        case .composite: return "photo"
        case .depthMap: return "map"
        case .sourceAttribution: return "square.stack.3d.up"
        }
    }
}
