import SwiftUI

struct MediaConnectionItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let typeLabel: String
    let sharedThemes: [String]
}

struct MediaConnectionsView: View {
    let title: String
    let items: [MediaConnectionItem]

    var body: some View {
        NavigationStack {
            List(items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(item.typeLabel.uppercased())
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(ConstellationPalette.accent.opacity(0.14))
                            .foregroundStyle(ConstellationPalette.accent)
                            .clipShape(Capsule())

                        Text(item.title)
                            .font(.headline)
                            .lineLimit(2)
                    }

                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 6) {
                        ForEach(item.sharedThemes.prefix(4), id: \.self) { theme in
                            Text(theme.replacingOccurrences(of: "-", with: " ").capitalized)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.14))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
