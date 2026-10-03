import SwiftUI

@main
struct ScanAnythingApp: App {
    @State private var dexStore = DexStore()

    var body: some Scene {
        WindowGroup {
            DexRootView()
                .environment(dexStore)
                .preferredColorScheme(.dark)
        }
    }
}
