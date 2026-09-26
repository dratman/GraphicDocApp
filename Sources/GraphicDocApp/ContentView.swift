import SwiftUI
import AppKit

enum Tool {
    case arrow, blackDot, whiteDot
}

struct ContentView: View {
    @Binding var document: GraphicDocument
    @State private var isRunning = false
    @State private var selectedTool: Tool = .arrow
    @State private var isHoveringCanvas = false
    @State private var simTimer: Timer?

    private let pixelScale: CGFloat = 1
    private let dotRadiusCells = 4

    private var displayWidth: CGFloat { CGFloat(document.field.width) * pixelScale }
    private var displayHeight: CGFloat { CGFloat(document.field.height) * pixelScale }

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
                toolButton(.blackDot)
                toolButton(.whiteDot)

                Spacer()

                Button(isRunning ? "Stop" : "Run") {
                    isRunning.toggle()
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(minWidth: displayWidth + 40, minHeight: displayHeight + 120)
        .onChange(of: isRunning) { _, running in
            if running {
                simTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                    document.field.step()
                }
            } else {
                simTimer?.invalidate()
                simTimer = nil
            }
        }
    }

    private var canvasImage: some View {
        Group {
            if let cgImage = document.field.makeCGImage() {
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
        guard gridX >= 0, gridX < document.field.width, gridY >= 0, gridY < document.field.height else { return }
        let value = (selectedTool == .blackDot) ? -0.75 : 0.75
        document.field.paintDot(centerX: gridX, centerY: gridY, radius: dotRadiusCells, value: value)
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
        case .blackDot:
            Circle()
                .fill(Color.black)
                .frame(width: 18, height: 18)
        case .whiteDot:
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                .frame(width: 18, height: 18)
        }
    }

    private func updateCursor() {
        switch selectedTool {
        case .arrow:
            NSCursor.arrow.set()
        case .blackDot:
            Self.makeDotCursor(diameter: CGFloat(dotRadiusCells) * 2 * pixelScale, fill: .black, strokeColor: nil)
                .set()
        case .whiteDot:
            Self.makeDotCursor(diameter: CGFloat(dotRadiusCells) * 2 * pixelScale, fill: .white, strokeColor: .systemBlue)
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
