import XCTest
import SwiftUI
@testable import CaniClip

/// Renders the README screenshots and demo GIF from the app's real views, filled
/// with made-up sample captures (never the developer's own history).
///
/// Skipped unless an output folder is given. xcodebuild passes TEST_RUNNER_*
/// variables to the test process without the prefix:
///
///     TEST_RUNNER_CANICLIP_README_ASSETS="$PWD/docs/media" xcodebuild test \
///       -project CaniClip.xcodeproj -scheme CaniClip -destination 'platform=macOS,arch=arm64' \
///       -only-testing:CaniClipTests/ReadmeAssetTests
@MainActor
final class ReadmeAssetTests: XCTestCase {
    private var out: URL!
    private var scratch: URL!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["CANICLIP_README_ASSETS"] else {
            throw XCTSkip("Set TEST_RUNNER_CANICLIP_README_ASSETS to render README assets")
        }
        out = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-readme-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
    }

    // MARK: - Screenshots

    func testRenderHub() throws {
        let library = try sampleLibrary()
        let vm = HubViewModel(library: library)
        let size = CGSize(width: 860, height: 600)
        let shot = try snapshot(HubView(viewModel: vm, actions: .noop), size: size)
        try save(Chrome(content: shot, size: size, title: nil), name: "hub")
    }

    func testRenderEditor() throws {
        let image = render(ChatSample(), size: CGSize(width: 800, height: 500))
        let doc = EditorDocument(image: image)
        let w = CGFloat(image.width), h = CGFloat(image.height)
        doc.style = AnnotationStyle(color: .red, strokeWidth: 8, fontSize: 44)
        // Positions measured from a render of ChatSample (fractions of the image).
        doc.add(Annotation(kind: .highlighter([CGPoint(x: 0.24 * w, y: 0.205 * h), CGPoint(x: 0.42 * w, y: 0.205 * h)]),
                           style: AnnotationStyle(color: .yellow, strokeWidth: 10, fontSize: 24)))
        doc.add(Annotation(kind: .rect(CGRect(x: 0.022 * w, y: 0.39 * h, width: 0.465 * w, height: 0.1 * h)), style: doc.style))
        doc.add(Annotation(kind: .arrow(from: CGPoint(x: 0.4 * w, y: 0.64 * h), to: CGPoint(x: 0.31 * w, y: 0.51 * h)),
                           style: doc.style))
        doc.add(Annotation(kind: .text(origin: CGPoint(x: 0.42 * w, y: 0.6 * h), string: "Bug is here"), style: doc.style))
        doc.add(Annotation(kind: .pixelate(CGRect(x: 0.072 * w, y: 0.87 * h, width: 0.45 * w, height: 0.06 * h), blockSize: 16),
                           style: doc.style))
        doc.tool = .arrow
        let size = CGSize(width: 1100, height: 733)
        let shot = try snapshot(EditorView(document: doc, actions: EditorActions(copy: {}, save: {}, saveAs: {})), size: size)
        try save(Chrome(content: shot, size: size, title: "Screenshot"), name: "editor")
    }

    func testRenderRecording() throws {
        let model = RecordingHUDModel()
        model.elapsed = 7
        let hud = try snapshot(RecordingHUDView(model: model, onStop: {}), size: RecordingHUDView.size)
        let backdrop = render(DashboardSample(), size: CGSize(width: 800, height: 500))
        try save(RecordingScene(backdrop: backdrop, hud: hud), name: "recording")
    }

    // MARK: - Demo GIF

    /// The capture flow as an animation, encoded by CaniClip's own GIF encoder.
    func testRenderDemoGif() throws {
        let fps = 15.0
        // 640 × 400: crisp enough for a README, light enough to load quickly.
        let frames = (0..<DemoScene.frameCount).map { render(DemoScene(frame: $0), size: DemoScene.size, scale: 0.8) }
        let summary = try encodeGif(frames: frames, fps: fps, to: out.appendingPathComponent("demo.gif"), hold: 1.5)
        XCTAssertLessThan(summary.fileSizeBytes, 5_000_000, "keep the README demo light")
        // Key moments as stills for the step-by-step section.
        for (frame, name) in [(30, "step-1-select"), (66, "step-2-annotate"), (84, "step-3-copied")] {
            try ImageExporter.writePNG(render(DemoScene(frame: frame), size: DemoScene.size, scale: 1),
                                       to: out.appendingPathComponent("\(name).png"))
        }
    }

    // MARK: - Sample library

    private func sampleLibrary() throws -> CaptureLibrary {
        let root = scratch.appendingPathComponent("library")
        let library = CaptureLibrary(rootURL: root)
        let samples: [(AnyView, TimeInterval)] = [
            (AnyView(ChatSample()), 3 * 60),
            (AnyView(DashboardSample()), 2 * 3600),
            (AnyView(CodeSample()), 26 * 3600),
            (AnyView(PaletteSample()), 30 * 3600),
        ]
        var ages: [UUID: TimeInterval] = [:]
        for (view, age) in samples.reversed() {
            let record = try library.addScreenshot(render(view, size: CGSize(width: 800, height: 500)))
            ages[record.id] = age
        }
        let gif = scratch.appendingPathComponent("sample.gif")
        try encodeGif(frames: (0..<8).map { render(DashboardSample(highlight: $0 % 7), size: CGSize(width: 800, height: 500), scale: 1) },
                      fps: 4, to: gif)
        let gifRecord = try library.addGif(url: gif, summary: nil)
        ages[gifRecord.id] = 45 * 60

        // Spread the samples over today and yesterday so the hub shows real sections.
        let index = root.appendingPathComponent("index.json")
        var records = try JSONDecoder().decode([CaptureRecord].self, from: Data(contentsOf: index))
        let now = Date()
        records = records.map { r in
            let age = ages[r.id] ?? 0
            return CaptureRecord(id: r.id, kind: r.kind, createdAt: now.addingTimeInterval(-age),
                                 pixelWidth: r.pixelWidth, pixelHeight: r.pixelHeight, fileSizeBytes: r.fileSizeBytes,
                                 savedPath: r.savedPath, hasLibraryAsset: r.hasLibraryAsset,
                                 durationSeconds: r.kind == .gif ? 4.2 : nil, frameCount: r.kind == .gif ? 63 : nil)
        }.sorted { $0.createdAt > $1.createdAt }
        try JSONEncoder().encode(records).write(to: index)
        return CaptureLibrary(rootURL: root)
    }

    // MARK: - Rendering helpers

    /// Pure SwiftUI scenes (no AppKit views inside) at 2× scale.
    private func render<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2) -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .light))
        renderer.scale = scale
        return renderer.cgImage!
    }

    /// App views that may contain AppKit (the annotation canvas), drawn by AppKit in an offscreen window at 2×.
    private func snapshot<V: View>(_ view: V, size: CGSize) throws -> NSImage {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private func save<V: View>(_ view: V, name: String) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        try ImageExporter.writePNG(image, to: out.appendingPathComponent("\(name).png"))
    }

    private func rgba(_ image: CGImage) -> Data {
        let w = image.width, h = image.height
        var data = Data(count: w * h * 4)
        data.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }

    @discardableResult
    private func encodeGif(frames: [CGImage], fps: Double, to url: URL, hold: Double = 0, maxWidth: UInt32? = nil) throws -> GifSummary {
        let encoder = try GifEncoder(settings: GifSettings(maxWidth: maxWidth, maxHeight: nil, quality: 100, fast: false, repeat: 0))
        for (i, frame) in frames.enumerated() {
            try encoder.addFrame(pixels: rgba(frame), width: UInt32(frame.width), height: UInt32(frame.height),
                                 format: .rgba, timestampSecs: Double(i) / fps)
        }
        let end = Double(frames.count) / fps + hold
        return try encoder.finish(outputPath: url.path, endTimestampSecs: end)
    }
}

// MARK: - Window chrome and scenes

private extension HubActions {
    static let noop = HubActions(captureArea: {}, captureFullScreen: {}, recordArea: {}, openSettings: {}, openSaveFolder: {},
                                 openRecord: { _ in }, copyRecord: { _ in }, revealRecord: { _ in }, deleteRecord: { _ in })
}

private struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34))
            Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18))
            Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25))
        }
        .frame(width: 52, height: 12)
    }
}

/// A macOS-style window around a rendered view, with a soft shadow.
private struct Chrome: View {
    let content: NSImage
    let size: CGSize
    let title: String?

    var body: some View {
        VStack(spacing: 0) {
            if let title {
                ZStack {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    HStack { TrafficLights(); Spacer() }.padding(.leading, 14)
                }
                .frame(width: size.width, height: 30)
                .background(Color(white: 0.93))
            }
            Image(nsImage: content).resizable().frame(width: size.width, height: size.height)
        }
        .overlay(alignment: .topLeading) {
            if title == nil { TrafficLights().padding(.leading, 18).padding(.top, 16) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.black.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
        .padding(44)
    }
}

/// A wallpaper with a sample window being recorded: red region frame and the recording HUD.
private struct RecordingScene: View {
    let backdrop: CGImage
    let hud: NSImage

    var body: some View {
        ZStack(alignment: .topLeading) {
            Wallpaper()
            Image(decorative: backdrop, scale: 2)
                .resizable()
                .frame(width: 640, height: 400)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
                .offset(x: 80, y: 50)
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.red, lineWidth: 3)
                .frame(width: 330, height: 200)
                .offset(x: 112, y: 138)
            Image(nsImage: hud)
                .resizable()
                .frame(width: RecordingHUDView.size.width, height: RecordingHUDView.size.height)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.94)))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .offset(x: 182, y: 352)
        }
        .frame(width: 800, height: 500)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(24)
    }
}

struct Wallpaper: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.16, green: 0.17, blue: 0.27), Color(red: 0.36, green: 0.26, blue: 0.47),
                                Color(red: 0.96, green: 0.62, blue: 0.36)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Demo animation

/// One frame of the README demo: shortcut → dimmed screen → selection → editor
/// with an arrow drawn in → "Copied" toast. 15 fps, 800 × 500.
private struct DemoScene: View {
    let frame: Int
    static let frameCount = 96
    static let size = CGSize(width: 800, height: 500)

    // Sample window and the selection drawn over it (scene coordinates).
    private let window = CGRect(x: 120, y: 70, width: 560, height: 350)
    private let selectionStart = CGPoint(x: 150, y: 150)
    private let selectionEnd = CGPoint(x: 470, y: 340)

    private func progress(_ from: Int, _ to: Int) -> CGFloat {
        let t = CGFloat(frame - from) / CGFloat(max(1, to - from))
        let c = min(1, max(0, t))
        return c * c * (3 - 2 * c)   // ease in-out
    }

    private var selection: CGRect {
        let p = progress(18, 36)
        let end = CGPoint(x: selectionStart.x + (selectionEnd.x - selectionStart.x) * p,
                          y: selectionStart.y + (selectionEnd.y - selectionStart.y) * p)
        return CGRect(x: selectionStart.x, y: selectionStart.y,
                      width: max(1, end.x - selectionStart.x), height: max(1, end.y - selectionStart.y))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Wallpaper()
            menuBar
            sampleWindow
            if frame >= 12 && frame < 40 { overlay }
            if frame >= 40 { editor }
            if frame >= 4 && frame < 24 { keyHint }
            if frame >= 70 { toast }
            cursor
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    private var menuBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "applelogo")
            Text("Finder").fontWeight(.semibold)
            Spacer()
            Image(systemName: "questionmark.square.dashed").foregroundStyle(clipYellow)
            Image(systemName: "wifi")
            Text("9:41")
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(width: Self.size.width, height: 24)
        .background(Color.black.opacity(0.25))
    }

    private var sampleWindow: some View {
        DashboardSample()
            .frame(width: 800, height: 500)
            .scaleEffect(window.width / 800, anchor: .topLeading)
            .frame(width: window.width, height: window.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
            .offset(x: window.minX, y: window.minY)
    }

    private var overlay: some View {
        let sel = selection
        let selecting = frame >= 18
        let flash = frame >= 37 ? Double(40 - frame) / 4 : 0
        return ZStack(alignment: .topLeading) {
            ForEach(Array(dimStrips(around: selecting ? sel : nil).enumerated()), id: \.offset) { _, r in
                Color.black.opacity(0.35)
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
            }
            if selecting {
                Rectangle().stroke(Color.white, lineWidth: 1.5)
                    .frame(width: sel.width, height: sel.height)
                    .offset(x: sel.minX, y: sel.minY)
                Text("\(Int(sel.width * 2)) × \(Int(sel.height * 2))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.7)))
                    .offset(x: sel.minX, y: sel.maxY + 6)
            }
            Color.white.opacity(flash)
        }
    }

    /// The dimmed area as up to four rectangles leaving `hole` clear.
    private func dimStrips(around hole: CGRect?) -> [CGRect] {
        let full = CGRect(origin: .zero, size: Self.size)
        guard let h = hole else { return [full] }
        return [
            CGRect(x: 0, y: 0, width: full.width, height: h.minY),
            CGRect(x: 0, y: h.maxY, width: full.width, height: full.height - h.maxY),
            CGRect(x: 0, y: h.minY, width: h.minX, height: h.height),
            CGRect(x: h.maxX, y: h.minY, width: full.width - h.maxX, height: h.height),
        ].filter { $0.width > 0 && $0.height > 0 }
    }

    private var editor: some View {
        let appear = progress(40, 47)
        let arrow = progress(50, 62)
        let sel = CGRect(origin: selectionStart, size: CGSize(width: selectionEnd.x - selectionStart.x,
                                                              height: selectionEnd.y - selectionStart.y))
        return VStack(spacing: 0) {
            ZStack {
                Text("Screenshot").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                HStack { TrafficLights(); Spacer() }.padding(.leading, 12)
            }
            .frame(height: 28)
            .background(Color(white: 0.93))
            HStack(spacing: 10) {
                ForEach(["cursorarrow", "arrow.up.right", "rectangle", "circle", "pencil.tip", "highlighter", "textformat"], id: \.self) { name in
                    Image(systemName: name)
                        .frame(width: 26, height: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(name == "arrow.up.right" ? Color.accentColor.opacity(0.25) : Color(white: 0.9)))
                }
                Spacer()
                Text("Copy").font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.9)))
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Color(white: 0.97))
            ZStack(alignment: .topLeading) {
                // The captured area of the sample window, shown 1.3× in the editor.
                sampleWindow
                    .offset(x: -sel.minX, y: -sel.minY)
                    .frame(width: sel.width, height: sel.height, alignment: .topLeading)
                    .clipped()
                    .scaleEffect(zoom, anchor: .topLeading)
                    .frame(width: sel.width * zoom, height: sel.height * zoom, alignment: .topLeading)
                ArrowShape(from: CGPoint(x: 175, y: 205), to: CGPoint(x: 330, y: 70))
                    .trim(from: 0, to: arrow)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                if frame >= 62 {
                    Text("Ship it!")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(.red)
                        .offset(x: 40, y: 192)
                }
            }
            .frame(width: sel.width * zoom, height: sel.height * zoom)
            .background(Color.white)
        }
        .frame(width: sel.width * zoom)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
        .scaleEffect(0.92 + 0.08 * appear)
        .opacity(Double(appear))
        .offset(x: (Self.size.width - sel.width * zoom) / 2, y: 50)
    }

    private let zoom: CGFloat = 1.3

    private var keyHint: some View {
        HStack(spacing: 6) {
            ForEach(["⇧", "⌘", "7"], id: \.self) { key in
                Text(key)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            }
        }
        .foregroundStyle(ink)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.35)))
        .padding(.bottom, 26)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .bottom)
    }

    private var toast: some View {
        Label("Copied to clipboard", systemImage: "checkmark.circle.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(ink.opacity(0.9)))
            .padding(.bottom, 24)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .bottom)
            .opacity(Double(progress(70, 74)))
    }

    @ViewBuilder private var cursor: some View {
        if frame >= 12 && frame < 40 {
            // Crosshair at the corner being dragged.
            let p = frame >= 18 ? CGPoint(x: selection.maxX, y: selection.maxY) : selectionStart
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 1)
                .offset(x: p.x - 11, y: p.y - 13)
        } else if frame < 12 {
            Image(systemName: "cursorarrow")
                .font(.system(size: 22))
                .foregroundStyle(.black)
                .shadow(color: .white, radius: 1)
                .offset(x: 600 - CGFloat(frame) * 8, y: 300 - CGFloat(frame) * 4)
        }
    }
}

private struct ArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: from)
        p.addLine(to: to)
        let angle = atan2(to.y - from.y, to.x - from.x)
        let head: CGFloat = 18
        for side in [CGFloat.pi * 0.82, -CGFloat.pi * 0.82] {
            p.move(to: to)
            p.addLine(to: CGPoint(x: to.x + head * cos(angle + side), y: to.y + head * sin(angle + side)))
        }
        return p
    }
}

// MARK: - Made-up sample captures

private let ink = Color(red: 0.086, green: 0.086, blue: 0.10)
private let clipYellow = Color(red: 1.0, green: 0.784, blue: 0.239)

struct DashboardSample: View {
    var highlight: Int = 4
    private let values: [CGFloat] = [0.42, 0.55, 0.48, 0.7, 0.86, 0.64, 0.92]
    private let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly downloads").font(.system(size: 26, weight: .bold))
                    Text("Oct 8 – Oct 14").font(.system(size: 15)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("+24%").font(.system(size: 15, weight: .bold)).foregroundStyle(.green)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
            }
            HStack(alignment: .bottom, spacing: 22) {
                ForEach(values.indices, id: \.self) { i in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(i == highlight ? clipYellow : Color.blue.opacity(0.75))
                            .frame(height: 220 * values[i])
                        Text(days[i]).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            HStack(spacing: 14) {
                stat("Captures", "1,284")
                stat("GIFs", "312")
                stat("Avg. size", "1.2 MB")
            }
        }
        .padding(32)
        .background(Color.white)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.96)))
    }
}

struct CodeSample: View {
    private let lines: [[(String, Color)]] = [
        [("func ", .pink), ("capture", .cyan), ("(area: CGRect) ", .white), ("async throws", .pink), (" -> CGImage {", .white)],
        [("    let ", .pink), ("content = ", .white), ("try await ", .pink), ("SCShareableContent", .mint), (".current", .white)],
        [("    let ", .pink), ("filter = ", .white), ("SCContentFilter", .mint), ("(display: display)", .white)],
        [("    // Exclude our own windows so they never appear", .gray)],
        [("    config", .white), (".sourceRect = ", .white), ("area", .orange)],
        [("    return try await ", .pink), ("SCScreenshotManager", .mint), (".captureImage(…)", .white)],
        [("}", .white)],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TrafficLights()
                Text("Capture.swift").font(.system(size: 13, weight: .medium)).foregroundStyle(.gray).padding(.leading, 10)
                Spacer()
            }
            .padding(14)
            .background(Color(red: 0.14, green: 0.14, blue: 0.17))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lines.indices, id: \.self) { i in
                    HStack(spacing: 18) {
                        Text("\(i + 1)").foregroundStyle(.gray.opacity(0.6)).frame(width: 22, alignment: .trailing)
                        lines[i].reduce(Text("")) { $0 + Text($1.0).foregroundColor($1.1) }
                    }
                }
            }
            .font(.system(size: 17, design: .monospaced))
            .padding(24)
            Spacer()
        }
        .background(Color(red: 0.11, green: 0.11, blue: 0.13))
    }
}

struct ChatSample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Circle().fill(Color.purple.opacity(0.8)).frame(width: 36, height: 36)
                    .overlay(Text("M").font(.system(size: 17, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Maria · Design").font(.system(size: 17, weight: .semibold))
                    Text("online").font(.system(size: 13)).foregroundStyle(.green)
                }
            }
            bubble("The export button is greyed out again 😕", mine: false)
            bubble("Can you send me a screenshot?", mine: true)
            bubble("Here you go, it only happens after saving.", mine: false)
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
                Text("maria.lopez@example.com · +1 555 0134").font(.system(size: 15, design: .monospaced))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.95)))
        }
        .padding(28)
        .background(Color.white)
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        HStack {
            if mine { Spacer() }
            Text(text)
                .font(.system(size: 17))
                .foregroundStyle(mine ? .white : .primary)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(mine ? Color.blue : Color(white: 0.92)))
            if !mine { Spacer() }
        }
    }
}

struct PaletteSample: View {
    private let swatches: [(String, Color)] = [
        ("Clip Yellow", clipYellow), ("Ink", ink), ("Sky", Color(red: 0.35, green: 0.62, blue: 0.98)),
        ("Mint", Color(red: 0.4, green: 0.84, blue: 0.68)), ("Coral", Color(red: 0.99, green: 0.47, blue: 0.4)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Brand colours").font(.system(size: 26, weight: .bold))
            HStack(spacing: 14) {
                ForEach(swatches.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(swatches[i].1).frame(height: 240)
                        Text(swatches[i].0).font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            Spacer()
        }
        .padding(32)
        .background(Color(white: 0.98))
    }
}
