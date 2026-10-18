import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Lets the File menu find the Save action of whichever window is in front.
struct SaveFieldActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var saveFieldAction: (() -> Void)? {
        get { self[SaveFieldActionKey.self] }
        set { self[SaveFieldActionKey.self] = newValue }
    }
}

enum Tool {
    case arrow, negativeDot, positiveDot
}

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var field = WaveField()
    @State private var isRunning = false
    @State private var selectedTool: Tool = .arrow
    @State private var hoverLocation: CGPoint?
    @State private var isSystemCursorHidden = false
    @State private var simTimer: Timer?
    @State private var stepsThisSecond = 0
    @State private var measuredStepsPerSecond = 0
    @State private var fpsSamplerTimer: Timer?
    @State private var dotRadiusCells = 30

    // How many screen points each grid cell occupies. Recomputed from the
    // window size so the whole grid always fits; the grid itself never changes.
    @State private var pixelScale: CGFloat = 1
    private let dotRadiusChoices = [5, 10, 20, 30]
    private let peakDomeValue = 0.9
    private let dampingOnValue = 0.001


    private var displayWidth: CGFloat { CGFloat(field.width) * pixelScale }
    private var displayHeight: CGFloat { CGFloat(field.height) * pixelScale }

    // The largest scale at which the whole grid fits in the given space,
    // keeping the grid's aspect ratio.
    private func fitScale(in size: CGSize) -> CGFloat {
        guard field.width > 0, field.height > 0 else { return 1 }
        return max(0.1, min(size.width / CGFloat(field.width), size.height / CGFloat(field.height)))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                GeometryReader { geo in
                    let scale = fitScale(in: geo.size)
                    ZStack {
                        canvasImage
                        brushPreview
                    }
                    .frame(width: CGFloat(field.width) * scale, height: CGFloat(field.height) * scale)
                    .clipped()
                    .border(Color.gray)
                    .gesture(paintGesture)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverLocation = location
                        case .ended:
                            hoverLocation = nil
                        }
                        updateSystemCursorVisibility()
                    }
                    .onDisappear {
                        if isSystemCursorHidden {
                            NSCursor.unhide()
                            isSystemCursorHidden = false
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .onAppear { pixelScale = scale }
                    .onChange(of: scale) { _, newScale in pixelScale = newScale }
                }

                HStack(spacing: 16) {
                    toolButton(.arrow, systemImage: "arrow.up.left")
                    toolButton(.negativeDot)
                    toolButton(.positiveDot)

                    Picker("Radius", selection: $dotRadiusCells) {
                        ForEach(dotRadiusChoices, id: \.self) { radius in
                            Text("\(radius)").tag(radius)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    Picker("", selection: $field.boundaryCondition) {
                        ForEach(BoundaryCondition.allCases, id: \.self) { condition in
                            Text(condition.rawValue).tag(condition)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    Toggle("Damping", isOn: Binding(
                        get: { field.damping > 0 },
                        set: { field.damping = $0 ? dampingOnValue : 0 }
                    ))

                    Spacer()

                    Button("Clear") {
                        field.clear()
                    }

                    Button(isRunning ? "Stop" : "Run") {
                        isRunning.toggle()
                    }

                    Text("\(measuredStepsPerSecond) steps/sec")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
            .padding()

            // Middle-right of the whole window, not just the toolbar row --
            // an overlay on the outer ZStack rather than part of the VStack's
            // own vertical flow.
            VStack(alignment: .trailing, spacing: 2) {
                Text("Build: \(BuildInfo.timestamp)")
                Text("Grid: \(field.width) x \(field.height)")
            }
            .font(.caption2)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 8)
        }
        // Resizable by dragging the window edges or the green button; the grid
        // is scaled to fit. The ideal size is the grid at 1 point per cell.
        .frame(minWidth: 900, idealWidth: CGFloat(field.width) + 40,
               minHeight: 400, idealHeight: CGFloat(field.height) + 120)
        .onChange(of: isRunning) { _, running in
            if running {
                // TEMPORARY: uncapped, to see the actual max rate -- normally 1.0 / 30.0.
                simTimer = Timer.scheduledTimer(withTimeInterval: 0.0, repeats: true) { _ in
                    field.step()
                    stepsThisSecond += 1
                }
            } else {
                simTimer?.invalidate()
                simTimer = nil
            }
        }
        // File > Save… / Save As… (GraphicDocAppMain.swift) call this action
        // on the frontmost window only. Open and New always create a new
        // window; that window picks up appModel.pendingField when it appears.
        .focusedSceneValue(\.saveFieldAction, { saveField() })
        .onDisappear {
            simTimer?.invalidate()
            fpsSamplerTimer?.invalidate()
        }
        .onAppear {
            takePendingField()
            // Samples and resets the step counter once a second, independent
            // of isRunning, so it reads 0 while stopped and the actual
            // achieved rate (which can fall short of the 30/sec target under
            // load) while running.
            fpsSamplerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                measuredStepsPerSecond = stepsThisSecond
                stepsThisSecond = 0
            }
        }
    }

    private var canvasImage: some View {
        Group {
            if let cgImage = field.makeCGImage() {
                Image(decorative: cgImage, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
            } else {
                Rectangle().fill(Color.gray)
            }
        }
    }

    // Drawn as a normal SwiftUI view rather than a custom NSCursor -- a
    // custom NSCursor image has a practical maximum size on macOS, and this
    // brush (180pt across) is well past it: past that limit the system
    // doesn't scale the image down, it just shows an unscaled corner of it,
    // which is what was producing a quarter-disk instead of a full one no
    // matter how the underlying bitmap's pixel/point math was adjusted. A
    // plain view has no such limit and guarantees an exact size match with
    // the real paint radius, since it's rendered by the same pipeline.
    @ViewBuilder
    private var brushPreview: some View {
        if let hoverLocation, selectedTool != .arrow {
            let diameter = CGFloat(dotRadiusCells) * 2 * pixelScale
            Circle()
                .fill(selectedTool == .negativeDot ? Color.blue : Color.red)
                .frame(width: diameter, height: diameter)
                .position(hoverLocation)
                .allowsHitTesting(false)
        }
    }

    private func updateSystemCursorVisibility() {
        let shouldHide = selectedTool != .arrow && hoverLocation != nil
        if shouldHide && !isSystemCursorHidden {
            NSCursor.hide()
            isSystemCursorHidden = true
        } else if !shouldHide && isSystemCursorHidden {
            NSCursor.unhide()
            isSystemCursorHidden = false
        }
    }

    private var paintGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard selectedTool != .arrow else { return }
                paint(at: value.location)
            }
    }

    private func paint(at location: CGPoint) {
        let gridX = Int(location.x / pixelScale)
        let gridY = Int(location.y / pixelScale)
        guard gridX >= 0, gridX < field.width, gridY >= 0, gridY < field.height else { return }
        let value = (selectedTool == .negativeDot) ? -peakDomeValue : peakDomeValue
        field.paintDot(centerX: gridX, centerY: gridY, radius: dotRadiusCells, value: value)
    }

    private func takePendingField() {
        guard let loaded = appModel.pendingField else { return }
        field = loaded
        appModel.pendingField = nil
    }

    // Manual load/save via file panels, deliberately not SwiftUI's
    // DocumentGroup: DocumentGroup's automatic "unsaved changes" review runs
    // ahead of anything our app delegate can intercept, which is what was
    // forcing the save prompt on every quit. With no NSDocument in the
    // picture at all, there's nothing for that review to ask about.
    private func saveField() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Untitled.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try JSONEncoder().encode(field)
            try data.write(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @ViewBuilder
    private func toolButton(_ tool: Tool, systemImage: String? = nil) -> some View {
        Button {
            selectedTool = tool
            updateSystemCursorVisibility()
        } label: {
            toolIcon(tool, systemImage: systemImage)
                .padding(6)
                .background(selectedTool == tool ? Color.accentColor.opacity(0.25) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func toolIcon(_ tool: Tool, systemImage: String?) -> some View {
        switch tool {
        case .arrow:
            Image(systemName: systemImage ?? "arrow.up.left")
                .font(.system(size: 18))
                .frame(width: 24, height: 24)
        case .negativeDot:
            Circle()
                .fill(Color.blue)
                .frame(width: 18, height: 18)
        case .positiveDot:
            Circle()
                .fill(Color.red)
                .frame(width: 18, height: 18)
        }
    }

}
