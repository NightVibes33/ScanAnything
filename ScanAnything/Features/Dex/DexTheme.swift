import SwiftUI

extension Color {
    static let dexRed = Color(red: 0.83, green: 0.08, blue: 0.12)
    static let dexRedDark = Color(red: 0.50, green: 0.025, blue: 0.04)
    static let dexPanel = Color(red: 0.07, green: 0.075, blue: 0.085)
    static let dexScreen = Color(red: 0.82, green: 0.94, blue: 0.91)
}

struct DexHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 54, height: 54)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, .cyan, .blue],
                            center: .topLeading,
                            startRadius: 1,
                            endRadius: 28
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 2))
            }

            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 12, height: 12)
                Circle().fill(.yellow).frame(width: 12, height: 12)
                Circle().fill(.green).frame(width: 12, height: 12)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(.title2, design: .monospaced, weight: .black))
                if let subtitle {
                    Text(subtitle.uppercased())
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [.dexRed, .dexRedDark],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(.black.opacity(0.65)).frame(height: 3)
        }
    }
}

struct DexPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.dexPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
    }
}
