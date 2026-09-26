import SwiftUI
import UniformTypeIdentifiers

// The graphic content of a document: one circle, with a start position
// (where it sits when not animating) and an end position (where the
// animation carries it to). This is the whole "document model" for now —
// more shapes and more keyframes would each just be another entry in an
// array, following this same pattern.
struct Shape2D: Codable, Equatable {
    var x: Double
    var y: Double
    var toX: Double
    var toY: Double
    var radius: Double
    var colorRed: Double
    var colorGreen: Double
    var colorBlue: Double
}

struct GraphicDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var shape: Shape2D

    init(shape: Shape2D = Shape2D(
        x: 120, y: 120,
        toX: 380, toY: 280,
        radius: 40,
        colorRed: 0.2, colorGreen: 0.5, colorBlue: 0.9
    )) {
        self.shape = shape
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        shape = try JSONDecoder().decode(Shape2D.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(shape)
        return FileWrapper(regularFileWithContents: data)
    }
}
