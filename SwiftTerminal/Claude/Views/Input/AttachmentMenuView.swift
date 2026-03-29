import AppKit
import PhotosUI
import SwiftUI

struct AttachmentMenuView: View {
    let service: ClaudeService
    @State private var photosPickerItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false

    var body: some View {
        Menu {
            if service.queryActive {
                Button(role: .destructive) {
                    service.disconnectProcess()
                } label: {
                    Label("Stop Session", systemImage: "xmark")
                }
                Divider()
            }

            PhotosPicker(
                selection: $photosPickerItems,
                maxSelectionCount: 5,
                matching: .images
            ) {
                Label("Photos Library", systemImage: "photo.on.rectangle.angled")
            }

            Button {
                showFileImporter = true
            } label: {
                Label("Attach Files", systemImage: "paperclip")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.secondary, .clear)
                .font(.largeTitle).fontWeight(.semibold)
                .glassEffect()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .offset(y: -1)
        .onChange(of: photosPickerItems) { _, items in
            Task {
                await loadPhotos(items)
                photosPickerItems = []
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            loadFiles(result)
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let (imageData, mime) = normalizeImageData(data)
            service.imageAttachments.append(ImageAttachment(data: imageData, mediaType: mime))
        }
    }

    private func loadFiles(_ result: Result<[URL], Error>) {
        guard let urls = try? result.get() else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            let (imageData, mime) = normalizeImageData(data)
            service.imageAttachments.append(ImageAttachment(data: imageData, mediaType: mime))
        }
    }

    /// Detects format and converts HEIC/TIFF to JPEG. Returns (data, mimeType).
    private func normalizeImageData(_ data: Data) -> (Data, String) {
        // Check magic bytes for format detection
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return (data, "image/png") }
        if data.starts(with: [0x47, 0x49, 0x46]) { return (data, "image/gif") }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return (data, "image/jpeg") }
        if data.count > 11 && data[8...11] == Data([0x57, 0x45, 0x42, 0x50]) { return (data, "image/webp") }

        // HEIC/TIFF/other — convert to JPEG via NSImage
        if let nsImage = NSImage(data: data),
           let tiff = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            return (jpeg, "image/jpeg")
        }

        return (data, "image/jpeg")
    }
}
