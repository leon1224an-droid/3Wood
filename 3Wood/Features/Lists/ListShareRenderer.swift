import SwiftUI
import UIKit

@MainActor
enum ListShareRenderer {
    /// Renders `ListShareCard` off-screen to a PNG-ready image. `ImageRenderer`
    /// lays the view out from its own fixed frame — it doesn't need to be
    /// mounted anywhere visible.
    static func render(list: CustomList, courses: [ListCourse]) -> UIImage? {
        let renderer = ImageRenderer(content: ListShareCard(list: list, courses: courses))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// `UIImage` isn't `Transferable` on its own — this wraps it as PNG data so
/// `ShareLink` can hand it to the system share sheet.
struct ShareableImage: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { shareable in
            shareable.image.pngData() ?? Data()
        }
    }
}
