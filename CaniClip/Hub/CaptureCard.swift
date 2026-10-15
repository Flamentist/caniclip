import SwiftUI

struct CaptureCard: View {
    let record: CaptureRecord
    let thumbnail: NSImage?
    let isMissing: Bool
    let isSelected: Bool
    let relativeTime: String
    let actions: HubActions
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.secondary.opacity(0.15)
                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 4) {
                    if isMissing {
                        Label("Missing", systemImage: "exclamationmark.triangle.fill").labelStyle(.iconOnly)
                    }
                    Image(systemName: record.kind == .gif ? "film" : "camera")
                }
                .font(.caption.weight(.semibold))
                .padding(6)
                .background(.thinMaterial, in: Capsule())
                .padding(8)

                if hovering {
                    actionStrip
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            Text(relativeTime).font(.subheadline)
            Text("\(HubViewModel.dimensionsText(record)) · \(HubViewModel.sizeText(bytes: record.fileSizeBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
    }

    private var actionStrip: some View {
        HStack(spacing: 6) {
            if record.kind == .screenshot {
                stripButton("Open", "pencil") { actions.openRecord(record) }.disabled(isMissing)
            }
            stripButton("Copy", "doc.on.doc") { actions.copyRecord(record) }.disabled(isMissing)
            stripButton("Reveal", "folder") { actions.revealRecord(record) }.disabled(isMissing)
            stripButton("Delete", "trash") { actions.deleteRecord(record) }
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .padding(8)
    }

    private func stripButton(_ help: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 18, height: 18) }
            .buttonStyle(.borderless)
            .help(help)
    }

    @ViewBuilder private var menuItems: some View {
        if record.kind == .screenshot {
            Button("Open in Editor") { actions.openRecord(record) }.disabled(isMissing)
        } else {
            Button("Open") { actions.openRecord(record) }.disabled(isMissing)
        }
        Button("Copy") { actions.copyRecord(record) }.disabled(isMissing)
        Button("Reveal in Finder") { actions.revealRecord(record) }.disabled(isMissing)
        Divider()
        Button("Remove from History", role: .destructive) { actions.deleteRecord(record) }
    }
}
