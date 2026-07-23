import SwiftUI

@main
struct ThreeWoodApp: App {
    @State private var session = SessionStore()

    init() {
        BrandFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}
