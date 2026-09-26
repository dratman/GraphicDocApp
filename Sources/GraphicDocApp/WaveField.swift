import Foundation
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
    static let sc = 0.1

    init(width: Int = 175, height: Int = 175) {
        self.width = width
        self.height = height
        self.current = Array(repeating: 0.0, count: width * height)
        self.dudt = Array(repeating: 0.0, count: width * height)
    }

    private func index(_ x: Int, _ y: Int) -> Int { y * width + x }

    mutating func clear() {
        current = Array(repeating: 0.0, count: width * height)
        dudt = Array(repeating: 0.0, count: width * height)
    }

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
        guard minX <= maxX, minY <= maxY, radius > 0 else { return }
        let radiusSquared = Double(radius * radius)
        for y in minY...maxY {
            for x in minX...maxX {
                let dx = x - centerX, dy = y - centerY
                let distanceSquared = Double(dx * dx + dy * dy)
                guard distanceSquared <= radiusSquared else { continue }
                // Dome profile: cos(t * pi/2), t = distance/radius, so u
                // (treated as the z axis) reaches `value` at the center and
                // tapers to 0 at the rim. Unlike a literal hemisphere
                // (sqrt(1-t^2), which stays near its peak for most of the
                // radius and only drops steeply right at the rim -- the same
                // "limb darkening" effect you see in a photo of a sphere),
                // this falls off gradually across the whole radius, so the
                // gradient reads clearly as shading rather than a flat top.
                let t = distanceSquared.squareRoot() / radiusSquared.squareRoot()
                let heightFraction = cos(t * .pi / 2)
                let i = index(x, y)
                current[i] = value * heightFraction
                dudt[i] = 0
            }
        }
    }

    // False-color stops for the -1...1 range: blue - cyan - white - yellow -
    // red, evenly spaced, with white sitting right at 0 for maximum contrast
    // against the saturated colors on either side. Interpolating through all
    // three channels along this path gives well over a thousand
    // distinguishable colors, not just the 256 steps a single grayscale
    // channel could show.
    static let colorStops: [(t: Double, r: Double, g: Double, b: Double)] = [
        (0.00,   0,   0, 255), // blue
        (0.25,   0, 255, 255), // cyan
        (0.50, 255, 255, 255), // white
        (0.75, 255, 255,   0), // yellow
        (1.00, 255,   0,   0), // red
    ]

    // Values outside -1...1 use colors that never occur in the gradient
    // above, so they still stand out as clearly "out of range." White now
    // sits at 0, so the old "<-1 = white" alert moved to black instead --
    // every stop above keeps at least one channel pinned at 255, so pure
    // black (0,0,0) never occurs naturally in the gradient.
    static func colorFor(_ value: Double) -> (UInt8, UInt8, UInt8) {
        if value > 1.0 { return (255, 0, 255) }   // magenta
        if value < -1.0 { return (0, 0, 0) }      // black
        let t = (value + 1) / 2
        for i in 0..<(colorStops.count - 1) {
            let a = colorStops[i], b = colorStops[i + 1]
            guard t <= b.t else { continue }
            let frac = (t - a.t) / (b.t - a.t)
            func lerp(_ x: Double, _ y: Double) -> UInt8 {
                UInt8(max(0, min(255, x + frac * (y - x))).rounded())
            }
            return (lerp(a.r, b.r), lerp(a.g, b.g), lerp(a.b, b.b))
        }
        return (255, 0, 0)
    }

    // Renders the field to a small bitmap using the false-color scheme above.
    func makeCGImage() -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            let (r, g, b) = Self.colorFor(current[i])
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
