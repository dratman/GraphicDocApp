import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum Tool {
    case arrow, negativeDot, positiveDot
}

struct ContentView: View {
    @State private var field = WaveField()
    @State private var isRunning = false
    @State private var selectedTool: Tool = .arrow
    @State private var isHoveringCanvas = false
    @State private var simTimer: Timer?
    @State private var stepsThisSecond = 0
    @State private var measuredStepsPerSecond = 0
    @State private var fpsSamplerTimer: Timer?

    private let pixelScale: CGFloat = 3
    private let dotRadiusCells = 30

    private var displayWidth: CGFloat { CGFloat(field.width) * pixelScale }
    private var displayHeight: CGFloat { CGFloat(field.height) * pixelScale }

    var body: some View {
        VStack(spacing: 12) {
            canvasImage
                .frame(width: displayWidth, height: displayHeight)
                .border(Color.gray)
                .gesture(paintGesture)
                .onHover { hovering in
                    isHoveringCanvas = hovering
                    if hovering {
                        updateCursor()
                    } else {
                        NSCursor.arrow.set()
                    }
                }

            HStack(spacing: 16) {
                toolButton(.arrow, systemImage: "arrow.up.left")
                toolButton(.negativeDot)
                toolButton(.positiveDot)

                Spacer()

                Button("Open…") { openField() }
                Button("Save As…") { saveField() }

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
        .frame(minWidth: displayWidth + 40, minHeight: displayHeight + 120)
        .onChange(of: isRunning) { _, running in
            if running {
                simTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                    field.step()
                    stepsThisSecond += 1
                }
            } else {
                simTimer?.invalidate()
                simTimer = nil
            }
        }
        .onAppear {
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
        let value = (selectedTool == .negativeDot) ? -0.9 : 0.9
        field.paintDot(centerX: gridX, centerY: gridY, radius: dotRadiusCells, value: value)
    }

    // Manual load/save via file panels, deliberately not SwiftUI's
    // DocumentGroup: DocumentGroup's automatic "unsaved changes" review runs
    // ahead of anything our app delegate can intercept, which is what was
    // forcing the save prompt on every quit. With no NSDocument in the
    // picture at all, there's nothing for that review to ask about.
    private func openField() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            field = try JSONDecoder().decode(WaveField.self, from: data)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

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
            if isHoveringCanvas { updateCursor() }
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

    private func updateCursor() {
        switch selectedTool {
        case .arrow:
            NSCursor.arrow.set()
        case .negativeDot:
            Self.makeDotCursor(diameter: CGFloat(dotRadiusCells) * 2 * pixelScale, fill: .blue, strokeColor: nil)
                .set()
        case .positiveDot:
            Self.makeDotCursor(diameter: CGFloat(dotRadiusCells) * 2 * pixelScale, fill: .red, strokeColor: nil)
                .set()
        }
    }

    private static func makeDotCursor(diameter: CGFloat, fill: NSColor, strokeColor: NSColor?) -> NSCursor {
        let strokeWidth: CGFloat = strokeColor == nil ? 0 : 2
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        let inset = strokeWidth / 2
        let rect = NSRect(x: inset, y: inset, width: diameter - strokeWidth, height: diameter - strokeWidth)
        let path = NSBezierPath(ovalIn: rect)
        fill.setFill()
        path.fill()
        if let strokeColor {
            strokeColor.setStroke()
            path.lineWidth = strokeWidth
            path.stroke()
        }
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: diameter / 2, y: diameter / 2))
    }
}
