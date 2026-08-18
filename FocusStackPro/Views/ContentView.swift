import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var stackViewModel = FocusStackViewModel()
    @State private var showingImporter = false
    @State private var showingExporter = false

    var body: some View {
        NavigationSplitView {
            SourceImagesView(viewModel: stackViewModel)
        } detail: {
            if stackViewModel.sourceImages.isEmpty {
                EmptyStateView(onImport: { showingImporter = true })
            } else {
                StackCanvasView(viewModel: stackViewModel, onExport: { showingExporter = true })
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.image, .rawImage],
            allowsMultipleSelection: true
        ) { result in
            stackViewModel.importImages(result: result)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: stackViewModel.exportDocument,
            contentType: .tiff,
            defaultFilename: "FocusStack.tiff"
        ) { result in
            if case .success = result { print("Export successful") }
        }
    }
}

struct EmptyStateView: View {
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "photo.stack")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
            VStack(spacing: 12) {
                Text("No Images Loaded")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Import RAW images to begin focus stacking")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: onImport) {
                Label("Import Images", systemImage: "square.and.arrow.down")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(60)
    }
}
