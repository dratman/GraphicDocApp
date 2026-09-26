import SwiftUI
import UniformTypeIdentifiers
import CoreGraphics

// The simulated field: a 2D grid of real-valued displacements, updated by
// a semi-implicit (symplectic) Euler integration of the wave equation.
// Instead of storing "current" and "previous" position grids, this stores
// "current" (u) and its time derivative "dudt" (du/dt) directly, and
// advances them in two steps each timestep:
//     dudt[x,y] += dt * (-sc) * (2nd space derivative of u[x,y])
//     u[x,y]    += dt * dudt[x,y]
// The second line uses the just-updated dudt, not the old one -- that's
// what makes this "semi-implicit" rather than plain Euler.
struct WaveField: Codable, Equatable {
    var width: Int
    var height: Int
    var current: [Double]
    var dudt: [Double]

    static let dt = 1.0
    static let sc = 0.2

    init(width: Int = 200, height: Int = 200) {
        self.width = width
        self.height = height
        self.current = Array(repeating: 0.0, count: width * height)
        self.dudt = Array(repeating: 0.0, count: width * height)
    }

    private func index(_ x: Int, _ y: Int) -> Int { y * width + x }

    // Advances the whole field by one timestep. The outermost ring of
    // cells is never updated here, so it stays at 0 forever -- a fixed
    // boundary that reflects waves back inward rather than absorbing them.
    mutating func step() {
        var newCurrent = current
        var newDudt = dudt
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = index(x, y)
                let secondSpaceDerivative = 4 * current[i]
                    - current[index(x + 1, y)] - current[index(x - 1, y)]
                    - current[index(x, y + 1)] - current[index(x, y - 1)]
                newDudt[i] = dudt[i] + Self.dt * (-Self.sc) * secondSpaceDerivative
                newCurrent[i] = current[i] + Self.dt * newDudt[i]
            }
        }
        current = newCurrent
        dudt = newDudt
    }

    // Sets every point within `radius` grid cells of (centerX, centerY) to
    // `value`, resetting its "dudt" value to 0 too -- so a freshly painted
    // point starts at rest (zero velocity) instead of snapping into motion
    // the instant the simulation resumes.
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
                dudt[i] = 0
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
