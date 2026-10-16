import SwiftUI

struct EditorActions {
    var copy: () -> Void
    var save: () -> Void
    var saveAs: () -> Void
}

/// The editor's keyboard shortcuts, matched from the key event itself so they
/// behave the same whichever toolbar layout is showing.
enum EditorCommand: Equatable {
    case undo, redo, copy, save, saveAs

    init?(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let shift = modifiers == [.command, .shift]
        guard modifiers == .command || shift else { return nil }
        switch (event.charactersIgnoringModifiers?.lowercased(), shift) {
        case ("z", false): self = .undo
        case ("z", true): self = .redo
        case ("c", true): self = .copy
        case ("s", false): self = .save
        case ("s", true): self = .saveAs
        default: return nil
        }
    }
}

/// Hosts the editor and handles its shortcuts before SwiftUI sees them.
final class EditorHostingView: NSHostingView<EditorView> {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, let command = EditorCommand(event) else {
            return super.performKeyEquivalent(with: event)
        }
        rootView.perform(command)
        return true
    }
}

struct EditorView: View {
    @ObservedObject var document: EditorDocument
    let actions: EditorActions

    static let swatches: [RGBAColor] = [.red, .orange, .yellow, .green, .blue, .black, .white]

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(red: document.style.color.r, green: document.style.color.g, blue: document.style.color.b, opacity: document.style.color.a) },
            set: { newValue in
                let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? .red
                document.style.color = RGBAColor(r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent, a: ns.alphaComponent)
            }
        )
    }

    static let strokeWidths: [CGFloat] = [2, 4, 6, 8, 10, 14]

    @State private var showingColours = false

    var body: some View {
        VStack(spacing: 0) {
            // The first layout that fits the window's width wins.
            ViewThatFits(in: .horizontal) {
                wideToolbar
                compactToolbar
                twoRowToolbar
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            Divider()
            AnnotationCanvas(document: document)
                .frame(minWidth: 320, minHeight: 200)
        }
    }

    func perform(_ command: EditorCommand) {
        switch command {
        case .undo: document.undoManager.undo()
        case .redo: document.undoManager.redo()
        case .copy: actions.copy()
        case .save: actions.save()
        case .saveAs: actions.saveAs()
        }
    }

    // MARK: Layouts

    private var wideToolbar: some View {
        HStack(spacing: 6) {
            tools
            separator
            ColorPicker("Colour", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .help("Colour")
            swatches(size: 14)
            Slider(value: $document.style.strokeWidth, in: 1...14, step: 1)
                .frame(width: 90)
                .help("Stroke width")
            Text("\(Int(document.style.strokeWidth))")
                .monospacedDigit()
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            history
            separator
            Button("Copy", action: actions.copy)
                .help("Copy (⇧⌘C)")
            Button("Save", action: actions.save)
                .buttonStyle(.borderedProminent)
                .help("Save (⌘S)")
            Button("Save As…", action: actions.saveAs)
                .help("Save As… (⇧⌘S)")
        }
    }

    private var compactToolbar: some View {
        HStack(spacing: 6) {
            tools
            separator
            colourButton
            strokeMenu
            Spacer(minLength: 12)
            history
            separator
            iconActions
        }
    }

    private var twoRowToolbar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                tools
                Spacer(minLength: 8)
                history
            }
            HStack(spacing: 8) {
                colourButton
                strokeMenu
                Spacer(minLength: 8)
                iconActions
            }
        }
    }

    // MARK: Pieces

    private var tools: some View {
        HStack(spacing: 6) {
            ForEach(EditorTool.allCases) { tool in
                Button {
                    document.tool = tool
                    document.selectedID = nil
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
                .tint(document.tool == tool ? .accentColor : .secondary)
                .help("\(tool.title) (\(String(tool.key).uppercased()))")
            }
        }
    }

    private var separator: some View {
        Divider().frame(height: 20).padding(.horizontal, 4)
    }

    private func swatches(size: CGFloat) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(Self.swatches.enumerated()), id: \.offset) { _, swatch in
                Button { document.style.color = swatch } label: {
                    Circle().fill(Color(cgColor: swatch.cgColor)).frame(width: size, height: size)
                        .overlay(Circle().stroke(Color.primary.opacity(0.25)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The current colour; click for the swatches and a custom colour well.
    private var colourButton: some View {
        Button { showingColours.toggle() } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(cgColor: document.style.color.cgColor))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.primary.opacity(0.25)))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .frame(height: 22)
        }
        .buttonStyle(.bordered)
        .help("Colour")
        .popover(isPresented: $showingColours, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                swatches(size: 22)
                ColorPicker("Custom colour", selection: colorBinding, supportsOpacity: false)
            }
            .padding(12)
        }
    }

    private var strokeMenu: some View {
        Menu {
            ForEach(Self.strokeWidths, id: \.self) { width in
                Button {
                    document.style.strokeWidth = width
                } label: {
                    if document.style.strokeWidth == width {
                        Label("\(Int(width)) pt", systemImage: "checkmark")
                    } else {
                        Text("\(Int(width)) pt")
                    }
                }
            }
        } label: {
            Label("\(Int(document.style.strokeWidth))", systemImage: "lineweight")
        }
        .fixedSize()
        .help("Stroke width")
    }

    private var history: some View {
        HStack(spacing: 6) {
            Button { perform(.undo) } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!document.undoManager.canUndo)
                .help("Undo (⌘Z)")
            Button { perform(.redo) } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!document.undoManager.canRedo)
                .help("Redo (⇧⌘Z)")
        }
    }

    private var iconActions: some View {
        HStack(spacing: 6) {
            Button(action: actions.copy) { Image(systemName: "doc.on.doc") }
                .help("Copy (⇧⌘C)")
            Button(action: actions.save) { Image(systemName: "square.and.arrow.down") }
                .buttonStyle(.borderedProminent)
                .help("Save (⌘S)")
            Button(action: actions.saveAs) { Image(systemName: "square.and.arrow.down.on.square") }
                .help("Save As… (⇧⌘S)")
        }
    }
}
