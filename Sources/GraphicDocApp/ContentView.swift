import SwiftUI

struct ContentView: View {
    @Binding var document: GraphicDocument
    @State private var isPlaying = false

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
                        x: isPlaying ? document.shape.toX : document.shape.x,
                        y: isPlaying ? document.shape.toY : document.shape.y
                    )
                    .animation(
                        isPlaying
                            ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
                            : .default,
                        value: isPlaying
                    )
                    .gesture(
                        DragGesture().onChanged { value in
                            guard !isPlaying else { return }
                            document.shape.x = value.location.x
                            document.shape.y = value.location.y
                        }
                    )
            }
            .frame(width: canvasWidth, height: canvasHeight)

            HStack {
                Button(isPlaying ? "Stop" : "Play") {
                    isPlaying.toggle()
                }
                Text(isPlaying
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
            .disabled(isPlaying)
            .padding(.horizontal)
        }
        .padding()
        .frame(minWidth: 560, minHeight: 520)
    }
}
