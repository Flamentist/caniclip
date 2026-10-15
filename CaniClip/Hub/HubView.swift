import SwiftUI
import KeyboardShortcuts

struct HubView: View {
    @ObservedObject var viewModel: HubViewModel
    let actions: HubActions

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 20).padding(.top, 16)
            actionRow.padding(.horizontal, 20).padding(.top, 12)
            filterBar.padding(.horizontal, 20).padding(.vertical, 12)
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
        HStack {
            Text("CaniClip").font(.largeTitle.weight(.semibold))
            Spacer()
            Button(action: actions.openSaveFolder) { Image(systemName: "folder") }.help("Open save folder")
            Button(action: actions.openSettings) { Image(systemName: "gearshape") }.help("Settings")
        }
        .buttonStyle(.bordered)
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            ActionTile(title: "Capture Area", symbol: "viewfinder", shortcutName: .captureArea, tint: .blue, action: actions.captureArea)
            ActionTile(title: "Capture Full Screen", symbol: "macwindow", shortcutName: .captureFullScreen, tint: .indigo, action: actions.captureFullScreen)
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
            .frame(width: 280)
            Spacer()
            Text("\(viewModel.visibleRecords.count) item\(viewModel.visibleRecords.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                ForEach(viewModel.sections()) { section in
                    Text(section.title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
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
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 16)
        }
    }

    private var emptyState: some View {
        let labels = HubViewModel.ShortcutLabels(
            area: KeyboardShortcuts.getShortcut(for: .captureArea)?.description ?? "the area shortcut",
            fullScreen: KeyboardShortcuts.getShortcut(for: .captureFullScreen)?.description ?? "the full-screen shortcut",
            record: KeyboardShortcuts.getShortcut(for: .recordArea)?.description ?? "the record shortcut")
        let text = HubViewModel.emptyStateText(filter: viewModel.filter,
                                               hasAnyRecords: !viewModel.library.records.isEmpty,
                                               shortcuts: labels)
        return VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 42)).foregroundStyle(.secondary)
            Text(text.title).font(.title3.weight(.medium))
            Text(text.message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
