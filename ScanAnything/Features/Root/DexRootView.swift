import SwiftUI

enum DexTab: Hashable {
    case dex
    case capture
    case search
}

struct DexRootView: View {
    @State private var selectedTab: DexTab = .dex

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dex", systemImage: "square.grid.3x3.fill", value: DexTab.dex) {
                NavigationStack {
                    DexLibraryView(selectedTab: $selectedTab)
                }
            }

            Tab("Capture", systemImage: "viewfinder.circle.fill", value: DexTab.capture) {
                NavigationStack {
                    OnePhotoCaptureView(selectedTab: $selectedTab)
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: DexTab.search, role: .search) {
                NavigationStack {
                    DexSearchView()
                }
            }
        }
        .tint(Color.dexRed)
    }
}
