import SwiftUI
import UIKit

struct DexLibraryView: View {
    @Environment(DexStore.self) private var store
    @Binding var selectedTab: DexTab
    @State private var settingsShown = false

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 3
    )

    var body: some View {
        VStack(spacing: 0) {
            DexHeader(
                title: "Scan Dex",
                subtitle: "\(store.entries.count) registered"
            )

            if store.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(store.entries) { entry in
                            NavigationLink(value: entry.id) {
                                DexEntryCard(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                .background(.black)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: UUID.self) { id in
            DexDetailView(entryID: id)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                settingsShown = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .padding(.top, 18)
            .padding(.trailing, 14)
            .accessibilityLabel("Settings")
        }
        .sheet(isPresented: $settingsShown) {
            NavigationStack {
                GenerationSettingsView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "viewfinder.circle")
                .font(.system(size: 86, weight: .thin))
                .foregroundStyle(.dexRed)

            Text("NO ENTRIES")
                .font(.system(.title, design: .monospaced, weight: .black))

            Text("Take one photo. The finished 3D object becomes a new Dex entry.")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button("CAPTURE FIRST ENTRY") {
                selectedTab = .capture
            }
            .buttonStyle(.borderedProminent)
            .tint(.dexRed)
            .font(.system(.headline, design: .monospaced, weight: .bold))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}

struct DexEntryCard: View {
    @Environment(DexStore.self) private var store
    let entry: DexEntry

    var body: some View {
        ZStack {
            Color.dexPanel

            if let image = store.image(for: entry) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Text(entry.dexNumber)
                        .font(.system(.caption2, design: .monospaced, weight: .black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                }

                Spacer()

                Text(entry.name.uppercased())
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .lineLimit(1)

                if entry.status == .generating {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.65, anchor: .leading)
                } else if entry.status == .failed {
                    Label("FAILED", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(.yellow)
                }
            }
            .foregroundStyle(.white)
            .padding(7)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}
