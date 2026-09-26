import SwiftUI
import UniformTypeIdentifiers
import CoreGraphics

// The simulated field: a 2D grid of real-valued displacements, updated by
// a discrete version of the wave equation
//     u_tt = c^2 * (u_xx + u_yy)
// Discretized with a 5-point Laplacian and dx = dy = dt = 1, the update
// rule becomes:
//     u_next[x,y] = 2*u[x,y] - u_prev[x,y]
//                   + r * (u[x+1,y] + u[x-1,y] + u[x,y+1] + u[x,y-1] - 4*u[x,y])
// where r = (wave speed)^2. This is second-order in time, which is why we
// need to keep both "current" and "previous" grids -- the new value at a
// point depends on where that point is now AND where it was one step ago
// (that difference is what encodes its velocity).
struct WaveField: Codable, Equatable {
    var width: Int
    var height: Int
    var current: [Double]
    var previous: [Double]

    // r must stay <= 0.5 for this stencil to remain numerically stable
    // (the discrete equivalent of the Courant-Friedrichs-Lewy condition).
    // Above that, rounding/propagation errors amplify each step instead of
    // damping, and the field blows up instead of oscillating.
    static let waveSpeedSquared = 0.2

    init(width: Int = 100, height: Int = 80) {
        self.width = width
        self.height = height
        self.current = Array(repeating: 0.0, count: width * height)
        self.previous = Array(repeating: 0.0, count: width * height)
    }

    private func index(_ x: Int, _ y: Int) -> Int { y * width + x }

    // Advances the whole field by one timestep. The outermost ring of
    // cells is never updated here, so it stays at 0 forever -- a fixed
    // boundary that reflects waves back inward rather than absorbing them.
    mutating func step() {
        var next = current
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = index(x, y)
                let laplacian = current[index(x + 1, y)] + current[index(x - 1, y)]
                    + current[index(x, y + 1)] + current[index(x, y - 1)]
                    - 4 * current[i]
                next[i] = 2 * current[i] - previous[i] + Self.waveSpeedSquared * laplacian
            }
        }
        previous = current
        current = next
    }

    // Sets every point within `radius` grid cells of (centerX, centerY) to
    // `value`, resetting its "previous" value to match too -- so a freshly
    // painted point starts at rest (zero velocity) instead of snapping
    // into motion the instant the simulation resumes.
    mutating func paintDot(centerX: Int, centerY: Int, radius: Int, value: Double) {
        let minX = max(0, centerX - radius), maxX = min(width - 1, centerX + radius)
        let minY = max(0, centerY - radius), maxY = min(height - 1, centerY + radius)
        guard minX <= maxX, minY <= maxY else { return }
        for y in minY...maxY {
            for x in minX...maxX {
                let dx = x - centerX, dy = y - centerY
                guard dx * dx + dy * dy <= radius * radius else { continue }
                let i = index(x, y)
                current[i] = value
                previous[i] = value
            }
        }
    }

    // Renders the field to a small bitmap: -1...1 maps linearly to
    // black...white (0 is 50% gray), above 1 is red, below -1 is yellow.
    func makeCGImage() -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            let v = current[i]
            let r: UInt8, g: UInt8, b: UInt8
            if v > 1.0 {
                (r, g, b) = (255, 0, 0)
            } else if v < -1.0 {
                (r, g, b) = (255, 255, 0)
            } else {
                let gray = UInt8((min(max(v, -1), 1) + 1) / 2 * 255)
                (r, g, b) = (gray, gray, gray)
            }
            pixels[i * 4] = r
            pixels[i * 4 + 1] = g
            pixels[i * 4 + 2] = b
            pixels[i * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

struct GraphicDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var field: WaveField

    init(field: WaveField = WaveField()) {
        self.field = field
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        field = try JSONDecoder().decode(WaveField.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(field)
        return FileWrapper(regularFileWithContents: data)
    }
}
