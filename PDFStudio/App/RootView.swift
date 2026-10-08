import SwiftUI

struct RootView: View {
    @Environment(FileStore.self) private var store
    @State private var tab: Tab = .tools

    enum Tab: Hashable { case tools, files, settings }

    var body: some View {
        TabView(selection: $tab) {
            ToolsHomeView()
                .tabItem { Label("Tools", systemImage: "square.grid.2x2.fill") }
                .tag(Tab.tools)
            FilesView()
                .tabItem { Label("My Files", systemImage: "folder.fill") }
                .tag(Tab.files)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .onOpenURL { url in
            // "Open in PDF Studio" from other apps: keep a copy in My Files.
            if store.importFiles([url]) > 0 { tab = .files }
        }
    }
}
