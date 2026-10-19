import AppKit
import UniformTypeIdentifiers

/// Reads what was dropped on the hub: a file to open, or image data (say, an
/// image dragged out of a browser). Only the first item is used.
enum HubDrop {
    enum Content: Equatable {
        case urls([URL])
        case data(Data)
    }

    static let acceptedTypes: [UTType] = [.fileURL, .image]

    static func load(_ providers: [NSItemProvider], completion: @escaping @MainActor (Content?) -> Void) {
        func finish(_ content: Content?) {
            Task { @MainActor in completion(content) }
        }
        guard let provider = providers.first else { return finish(nil) }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = object as? URL, url.isFileURL else { return finish(nil) }
                finish(.urls([url]))
            }
            return
        }
        guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
            return finish(nil)
        }
        _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
            finish(data.map(Content.data))
        }
    }
}
