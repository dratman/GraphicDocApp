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
enum BoundaryCondition: String, Codable, CaseIterable {
    case reflective = "Reflective"
    case toroidal = "Toroidal"
}

struct WaveField: Codable, Equatable {
    var width: Int
    var height: Int
    var current: [Double]
    var dudt: [Double]
    var boundaryCondition: BoundaryCondition = .toroidal

    static let dt = 2.0
    static let sc = 0.05

    init(width: Int = 1000, height: Int = 800) {
        self.width = width
        self.height = height
        self.current = Array(repeating: 0.0, count: width * height)
        self.dudt = Array(repeating: 0.0, count: width * height)
    }

    // A custom decoder so files saved before boundaryCondition existed
    // (like earlier test saves) still load, defaulting to .toroidal for
    // the missing field instead of failing to decode at all.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        current = try container.decode([Double].self, forKey: .current)
        dudt = try container.decode([Double].self, forKey: .dudt)
        boundaryCondition = try container.decodeIfPresent(BoundaryCondition.self, forKey: .boundaryCondition) ?? .toroidal
    }

    private func index(_ x: Int, _ y: Int) -> Int { y * width + x }

    mutating func clear() {
        current = Array(repeating: 0.0, count: width * height)
        dudt = Array(repeating: 0.0, count: width * height)
    }

    private func wrap(_ v: Int, _ bound: Int) -> Int { (v + bound) % bound }

    // Advances the whole field by one timestep.
    //
    // .toroidal updates every cell, including the edges: a cell's neighbor
    // "past" the right edge wraps around to the left edge (and similarly
    // top/bottom), via the modulo arithmetic in `wrap`. That makes the
    // topology a torus rather than a bounded sheet -- a wave that exits
    // through the right edge reenters from the left, instead of reflecting
    // back inward.
    //
    // .reflective updates only the interior cells (1..<width-1,
    // 1..<height-1); the outermost ring is left untouched forever, acting
    // as a fixed wall that waves bounce off of.
    mutating func step() {
        var newCurrent = current
        var newDudt = dudt
        let xRange = boundaryCondition == .toroidal ? 0..<width : 1..<(width - 1)
        let yRange = boundaryCondition == .toroidal ? 0..<height : 1..<(height - 1)
        for y in yRange {
            for x in xRange {
                let i = index(x, y)
                let xPlus: Int, xMinus: Int, yPlus: Int, yMinus: Int
                switch boundaryCondition {
                case .toroidal:
                    xPlus = wrap(x + 1, width); xMinus = wrap(x - 1, width)
                    yPlus = wrap(y + 1, height); yMinus = wrap(y - 1, height)
                case .reflective:
                    xPlus = x + 1; xMinus = x - 1
                    yPlus = y + 1; yMinus = y - 1
                }
                let secondSpaceDerivative = 4 * current[i]
                    - current[index(xPlus, y)] - current[index(xMinus, y)]
                    - current[index(x, yPlus)] - current[index(x, yMinus)]
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

    // Blue for negative, red for positive, white at 0 -- but the blend
    // toward white as |u| shrinks is piecewise linear in two unequal
    // segments rather than one straight line across the whole 0...1 range:
    //   |u| in [breakpoint, 1]: color stays close to full blue/red,
    //     dropping only from 1.0 to breakpointSaturation -- a slow falloff.
    //   |u| in [0, breakpoint]: color falls the rest of the way to white
    //     (0 saturation) over a much shorter span -- a fast falloff.
    // So small ripples near 0 bleach out toward white quickly, while
    // anything with real amplitude reads as strongly colored.
    static let breakpoint = 0.25
    static let breakpointSaturation = 0.85

    private static func saturationFraction(forMagnitude magnitude: Double) -> Double {
        if magnitude >= breakpoint {
            let frac = (magnitude - breakpoint) / (1 - breakpoint)
            return breakpointSaturation + frac * (1 - breakpointSaturation)
        } else {
            return magnitude / breakpoint * breakpointSaturation
        }
    }

    // How far to pull every in-range color toward black, in HSB terms: 1.0
    // leaves brightness untouched, 0.0 would make everything black. Hue and
    // saturation are left alone, so this darkens without shifting color.
    static let brightnessScale = 0.75

    // Values outside -1...1 use colors that never occur in the gradient
    // above, so they still stand out as clearly "out of range."
    //
    // This used to build two NSColor objects per call (blend to the base
    // color, then an HSB round trip to darken it) -- correct, but 250,000
    // calls of that per frame measured at 23ms, the actual bottleneck at
    // this grid size (the physics step measured 1.8ms by comparison).
    // In HSB, scaling brightness by a constant k while holding hue and
    // saturation fixed is mathematically identical to scaling R, G, and B
    // each by k directly -- so the whole NSColor round trip reduces to
    // multiplying by brightnessScale. Verified to match the old
    // NSColor-based version exactly (0 channel difference) across 20,001
    // sampled values before replacing it.
    static func colorFor(_ value: Double) -> (UInt8, UInt8, UInt8) {
        if value > 1.0 { return (255, 0, 255) }   // magenta, at full brightness (alert color)
        if value < -1.0 { return (0, 0, 0) }      // black
        let magnitude = min(abs(value), 1.0)
        let saturationFrac = saturationFraction(forMagnitude: magnitude)
        let maxChannel = 255.0 * brightnessScale
        let minChannel = maxChannel * (1 - saturationFrac)
        let hi = UInt8(maxChannel.rounded())
        let lo = UInt8(minChannel.rounded())
        return value >= 0 ? (hi, lo, lo) : (lo, lo, hi)
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
