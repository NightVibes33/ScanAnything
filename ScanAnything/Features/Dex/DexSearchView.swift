import SwiftUI

struct DexSearchView: View {
    @Environment(DexStore.self) private var store
    @State private var query = ""

    var filtered: [DexEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.name.localizedCaseInsensitiveContains(needle) ||
            $0.dexNumber.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        List(filtered) { entry in
            NavigationLink(value: entry.id) {
                HStack(spacing: 12) {
                    if let image = store.image(for: entry) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name.uppercased())
                            .font(.system(.headline, design: .monospaced, weight: .black))
                        Text(entry.dexNumber)
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Search Dex")
        .searchable(text: $query, prompt: "Name or number")
        .navigationDestination(for: UUID.self) { id in
            DexDetailView(entryID: id)
        }
    }
}
