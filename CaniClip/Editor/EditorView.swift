import SwiftUI

struct EditorActions {
    var copy: () -> Void
    var save: () -> Void
    var saveAs: () -> Void
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

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.bar)
            Divider()
            AnnotationCanvas(document: document)
                .frame(minWidth: 320, minHeight: 200)
        }
    }

    private var toolbar: some View {
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

            Divider().frame(height: 20).padding(.horizontal, 4)

            ColorPicker("Colour", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .help("Colour")
            ForEach(Array(Self.swatches.enumerated()), id: \.offset) { _, swatch in
                Button { document.style.color = swatch } label: {
                    Circle().fill(Color(cgColor: swatch.cgColor)).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.primary.opacity(0.25)))
                }
                .buttonStyle(.plain)
            }

            Slider(value: $document.style.strokeWidth, in: 1...14, step: 1)
                .frame(width: 90)
                .help("Stroke width")
            Text("\(Int(document.style.strokeWidth))")
                .monospacedDigit()
                .frame(width: 18)
                .foregroundStyle(.secondary)

            Spacer()

            Button { document.undoManager.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!document.undoManager.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo")
            Button { document.undoManager.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!document.undoManager.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("Redo")

            Divider().frame(height: 20).padding(.horizontal, 4)

            Button("Copy", action: actions.copy)
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Save", action: actions.save)
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
            Button("Save As…", action: actions.saveAs)
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}
