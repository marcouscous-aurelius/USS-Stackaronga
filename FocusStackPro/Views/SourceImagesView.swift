import SwiftUI
import UniformTypeIdentifiers

struct SourceImagesView: View {
    @ObservedObject var viewModel: FocusStackViewModel
    @State private var showingImporter = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Source Images")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.sourceImages.count)")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .padding()
            Divider()
            if viewModel.sourceImages.isEmpty {
                ContentUnavailableView(
                    "No Images",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Import RAW images to start")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(viewModel.sourceImages.enumerated()), id: \.offset) { index, imageData in
                            SourceImageRow(
                                imageData: imageData,
                                index: index,
                                isSelected: viewModel.selectedImageIndex == index
                            )
                            .onTapGesture { viewModel.selectedImageIndex = index }
                        }
                    }
                    .padding()
                }
            }
            Divider()
            HStack {
                Button(action: { showingImporter = true }) {
                    Label("Import", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(action: viewModel.clearImages) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(viewModel.sourceImages.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 250, idealWidth: 300)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.image, .rawImage],
            allowsMultipleSelection: true
        ) { result in
            viewModel.importImages(result: result)
        }
    }
}

struct SourceImageRow: View {
    let imageData: SourceImageData
    let index: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail = imageData.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay { ProgressView() }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Image \(index + 1)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let filename = imageData.filename {
                    Text(filename)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let focusDistance = imageData.focusDistance {
                    Text(String(format: "Focus: %.2fm", focusDistance))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
