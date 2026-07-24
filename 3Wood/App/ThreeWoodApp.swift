import SwiftUI

@main
struct ThreeWoodApp: App {
    @State private var session = SessionStore()
    @State private var nav = AppNavigation()

    init() {
        BrandFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(nav)
        }
    }
}
