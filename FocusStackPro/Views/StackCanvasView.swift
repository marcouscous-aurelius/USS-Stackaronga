import SwiftUI

struct StackCanvasView: View {
    @ObservedObject var viewModel: FocusStackViewModel
    let onExport: () -> Void
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            StackToolbar(viewModel: viewModel, onExport: onExport)
            Divider()
            GeometryReader { _ in
                ZStack {
                    Color.black.opacity(0.05)
                    if let resultImage = viewModel.resultImage {
                        Image(uiImage: resultImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { scale = lastScale * $0 }
                                    .onEnded { _ in lastScale = scale }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged {
                                        offset = CGSize(
                                            width: lastOffset.width + $0.translation.width,
                                            height: lastOffset.height + $0.translation.height
                                        )
                                    }
                                    .onEnded { _ in lastOffset = offset }
                            )
                    } else if viewModel.isProcessing {
                        VStack(spacing: 20) {
                            ProgressView(value: viewModel.progress)
                                .progressViewStyle(.linear)
                                .frame(width: 300)
                            Text(viewModel.statusMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(spacing: 20) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                            Text("Process images to see result")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if viewModel.resultImage != nil {
                VisualizationControls(viewModel: viewModel)
            }
        }
    }
}

struct StackToolbar: View {
    @ObservedObject var viewModel: FocusStackViewModel
    let onExport: () -> Void

    var body: some View {
        HStack {
            Button(action: viewModel.processStack) {
                Label("Process Stack", systemImage: "gearshape.2")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.sourceImages.count < 2 || viewModel.isProcessing)
            Spacer()
            Picker("Method", selection: $viewModel.stackingMethod) {
                ForEach(StackingMethod.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)
            .disabled(viewModel.isProcessing)
            Spacer()
            Button(action: onExport) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.resultImage == nil || viewModel.isProcessing)
        }
        .padding()
    }
}

struct VisualizationControls: View {
    @ObservedObject var viewModel: FocusStackViewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 30) {
                Picker("View", selection: $viewModel.visualizationMode) {
                    ForEach(VisualizationMode.allCases) {
                        Label($0.displayName, systemImage: $0.icon).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 500)
                if viewModel.visualizationMode != .composite {
                    HStack {
                        Text("Overlay")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Slider(value: $viewModel.overlayOpacity, in: 0...1)
                            .frame(width: 150)
                        Text("\(Int(viewModel.overlayOpacity * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
            .padding()
        }
    }
}
