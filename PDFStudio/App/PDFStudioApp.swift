import SwiftUI

@main
struct PDFStudioApp: App {
    @State private var store = FileStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}
