import SwiftUI
import KeyboardShortcuts

struct HubView: View {
    @ObservedObject var viewModel: HubViewModel
    let actions: HubActions

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 12)]
    private let sideInset: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, sideInset)
                .padding(.top, 38)   // below the transparent title bar's traffic lights
            actionRow
                .padding(.horizontal, sideInset)
                .padding(.top, 12)
            filterBar
                .padding(.horizontal, sideInset)
                .padding(.vertical, 10)
            Divider()
            if viewModel.visibleRecords.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text("CaniClip")
                .font(.title2.weight(.semibold))
            Spacer()
            Button(action: actions.openSaveFolder) {
                Image(systemName: "folder")
            }
            .help("Open save folder")
            Button(action: actions.openSettings) {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            ActionTile(title: "Capture Area", symbol: "viewfinder", shortcutName: .captureArea, tint: .blue, action: actions.captureArea)
            ActionTile(title: "Full Screen", symbol: "macwindow", shortcutName: .captureFullScreen, tint: .indigo, action: actions.captureFullScreen)
            ActionTile(title: "Record GIF", symbol: "record.circle", shortcutName: .recordArea, tint: .red, action: actions.recordArea)
        }
    }

    private var filterBar: some View {
        HStack {
            Picker("", selection: $viewModel.filter) {
                ForEach(HubViewModel.Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 240)
            Spacer()
            Text("\(viewModel.visibleRecords.count) item\(viewModel.visibleRecords.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                ForEach(viewModel.sections()) { section in
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, sideInset)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(section.records) { record in
                            let missing = viewModel.isMissing(record)
                            CaptureCard(record: record,
                                        thumbnail: viewModel.thumbnail(for: record),
                                        isMissing: missing,
                                        isSelected: viewModel.selection == record.id,
                                        relativeTime: HubViewModel.relativeTime(record.createdAt, now: viewModel.now),
                                        actions: actions)
                                .onTapGesture(count: 2) { if !missing { actions.openRecord(record) } }
                                .onTapGesture { viewModel.selection = record.id }
                        }
                    }
                    .padding(.horizontal, sideInset)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private var shortcutLabels: HubViewModel.ShortcutLabels {
        HubViewModel.ShortcutLabels(
            area: KeyboardShortcuts.getShortcut(for: .captureArea)?.description ?? "Not set",
            fullScreen: KeyboardShortcuts.getShortcut(for: .captureFullScreen)?.description ?? "Not set",
            record: KeyboardShortcuts.getShortcut(for: .recordArea)?.description ?? "Not set")
    }

    private var emptyState: some View {
        let labels = shortcutLabels
        let hasAny = !viewModel.library.records.isEmpty
        let text = HubViewModel.emptyStateText(filter: viewModel.filter, hasAnyRecords: hasAny, shortcuts: labels)
        return VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(text.title)
                .font(.headline)
            Text(text.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if !hasAny {
                HStack(spacing: 14) {
                    shortcutHint("viewfinder", labels.area)
                    shortcutHint("macwindow", labels.fullScreen)
                    shortcutHint("record.circle", labels.record)
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shortcutHint(_ symbol: String, _ key: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(.secondary).font(.caption)
            KeyCap(text: key)
        }
    }
}
