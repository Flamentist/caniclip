import SwiftUI

struct QuickAccessView: View {
    let thumbnail: NSImage?
    let fileName: String
    let detail: String
    let onCopy: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 260, maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Text(fileName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Copy", action: onCopy)
                Button("Reveal in Finder", action: onReveal)
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 284)
    }
}
