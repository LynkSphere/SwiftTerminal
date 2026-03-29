import SwiftUI
import UniformTypeIdentifiers

struct PasteHandler: ViewModifier {
    let service: ClaudeService
    @State private var eventMonitor: Any?
    @State private var hostingView: NSView?

    func body(content: Content) -> some View {
        content
            .onAppear {
                eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
                        if shouldHandlePaste() && handleCommandV() {
                            return nil
                        }
                    }
                    return event
                }
            }
            .onDisappear {
                if let monitor = eventMonitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
            .background(HostingViewFinder(hostingView: $hostingView))
    }

    private func shouldHandlePaste() -> Bool {
        guard let keyWindow = NSApp.keyWindow,
              let hostingView,
              let viewWindow = unsafe hostingView.window else {
            return false
        }
        return viewWindow == keyWindow
    }

    private func handleCommandV() -> Bool {
        guard let pasteboardItems = NSPasteboard.general.pasteboardItems else {
            return false
        }

        let imageTypes: Set<NSPasteboard.PasteboardType> = [.png, .tiff]
        var handled = false

        for item in pasteboardItems {
            if !Set(item.types).intersection(imageTypes).isEmpty {
                if let data = item.data(forType: .png) ?? item.data(forType: .tiff) {
                    let (imageData, mime) = normalizeImageData(data)
                    service.imageAttachments.append(ImageAttachment(data: imageData, mediaType: mime))
                    handled = true
                }
            } else if item.types.contains(.fileURL),
                      let urlString = item.string(forType: .fileURL),
                      let url = URL(string: urlString) {
                let ext = url.pathExtension.lowercased()
                let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]
                if imageExtensions.contains(ext),
                   let data = try? Data(contentsOf: url) {
                    let (imageData, mime) = normalizeImageData(data)
                    service.imageAttachments.append(ImageAttachment(data: imageData, mediaType: mime))
                    handled = true
                }
            }
        }

        return handled
    }

    private func normalizeImageData(_ data: Data) -> (Data, String) {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return (data, "image/png") }
        if data.starts(with: [0x47, 0x49, 0x46]) { return (data, "image/gif") }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return (data, "image/jpeg") }
        if data.count > 11 && data[8...11] == Data([0x57, 0x45, 0x42, 0x50]) { return (data, "image/webp") }

        if let nsImage = NSImage(data: data),
           let tiff = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            return (jpeg, "image/jpeg")
        }

        return (data, "image/jpeg")
    }
}

struct HostingViewFinder: NSViewRepresentable {
    @Binding var hostingView: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            hostingView = view
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func imagePasteHandler(service: ClaudeService) -> some View {
        modifier(PasteHandler(service: service))
    }
}
