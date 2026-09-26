import SwiftUI

struct ContentView: View {
    @Binding var document: GraphicDocument
    @State private var isRunning = false

    private let canvasWidth: CGFloat = 500
    private let canvasHeight: CGFloat = 400

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Rectangle()
                    .fill(Color.white)
                    .border(Color.gray)

                Circle()
                    .fill(Color(
                        red: document.shape.colorRed,
                        green: document.shape.colorGreen,
                        blue: document.shape.colorBlue
                    ))
                    .frame(width: document.shape.radius * 2, height: document.shape.radius * 2)
                    .position(
                        x: isRunning ? document.shape.toX : document.shape.x,
                        y: isRunning ? document.shape.toY : document.shape.y
                    )
                    .animation(
                        isRunning
                            ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
                            : .default,
                        value: isRunning
                    )
                    .gesture(
                        DragGesture().onChanged { value in
                            guard !isRunning else { return }
                            document.shape.x = value.location.x
                            document.shape.y = value.location.y
                        }
                    )
            }
            .frame(width: canvasWidth, height: canvasHeight)

            HStack {
                Button(isRunning ? "Stop" : "Run") {
                    isRunning.toggle()
                }
                Text(isRunning
                     ? "Animating between start and end position."
                     : "Drag the circle to set its start position.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("End position:")
                Slider(value: $document.shape.toX, in: 0...canvasWidth) { Text("X") }
                Slider(value: $document.shape.toY, in: 0...canvasHeight) { Text("Y") }
            }
            .disabled(isRunning)
            .padding(.horizontal)
        }
        .padding()
        .frame(minWidth: 560, minHeight: 520)
    }
}
