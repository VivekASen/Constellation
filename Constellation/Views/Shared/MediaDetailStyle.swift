import SwiftUI

enum ConstellationTypeScale {
    static let heroTitle = Font.custom("AvenirNext-Bold", size: 30, relativeTo: .title2)
    static let cardTitle = Font.custom("AvenirNext-DemiBold", size: 24, relativeTo: .title3)
    static let sectionTitle = Font.custom("AvenirNext-DemiBold", size: 18, relativeTo: .headline)
    static let body = Font.custom("AvenirNext-Regular", size: 17, relativeTo: .body)
    static let supporting = Font.custom("AvenirNext-Medium", size: 15, relativeTo: .subheadline)
    static let caption = Font.custom("AvenirNext-Medium", size: 13, relativeTo: .caption)
}

struct ConstellationHeroMetric: Identifiable {
    let id = UUID()
    let value: String
    let label: String
    let icon: String?
    let key: String?

    init(value: String, label: String, icon: String?, key: String? = nil) {
        self.value = value
        self.label = label
        self.icon = icon
        self.key = key
    }
}

struct ConstellationStarHeroHeader: View {
    let posterURL: String?
    let symbol: String
    let title: String
    let subtitle: String?
    let metrics: [ConstellationHeroMetric]
    let posterSize: CGSize
    let posterContentMode: ContentMode
    let onMetricTap: ((ConstellationHeroMetric) -> Void)?

    init(
        posterURL: String?,
        symbol: String,
        title: String,
        subtitle: String?,
        metrics: [ConstellationHeroMetric],
        posterSize: CGSize = CGSize(width: 142, height: 206),
        posterContentMode: ContentMode = .fill,
        onMetricTap: ((ConstellationHeroMetric) -> Void)? = nil
    ) {
        self.posterURL = posterURL
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.metrics = metrics
        self.posterSize = posterSize
        self.posterContentMode = posterContentMode
        self.onMetricTap = onMetricTap
    }

    var body: some View {
        GeometryReader { proxy in
            // In some scroll/nav configurations safeAreaInsets.top can resolve to 0.
            // Clamp to a practical minimum so the poster never collides with the status bar / Dynamic Island.
            let topInset = max(proxy.safeAreaInsets.top, 52)

            ZStack {
                starBackground

                VStack(spacing: 14) {
                    ConstellationPosterView(
                        imageURL: posterURL,
                        symbol: symbol,
                        width: posterSize.width,
                        height: posterSize.height,
                        cornerRadius: 18,
                        contentMode: posterContentMode
                    )

                    if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(spacing: 4) {
                            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(title)
                                    .font(ConstellationTypeScale.cardTitle)
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.85)
                            }

                            if let subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(ConstellationTypeScale.supporting)
                                    .foregroundStyle(.white.opacity(0.78))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 14) {
                        ForEach(metrics) { metric in
                            heroMetric(metric)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, topInset + 28)
                .padding(.bottom, 22)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(440, posterSize.height + 250))
    }

    private func heroMetric(_ metric: ConstellationHeroMetric) -> some View {
        let content = VStack(spacing: 4) {
            HStack(spacing: 5) {
                if let icon = metric.icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Text(metric.value)
                    .font(ConstellationTypeScale.supporting.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Text(metric.label)
                .font(ConstellationTypeScale.caption)
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }

        return Group {
            if metric.key != nil, onMetricTap != nil {
                Button {
                    onMetricTap?(metric)
                } label: {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var starBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.24),
                    Color(red: 0.08, green: 0.10, blue: 0.30),
                    Color(red: 0.10, green: 0.09, blue: 0.27)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                let stars = 44
                for index in 0..<stars {
                    let fx = CGFloat((index * 67 + 19) % 100) / 100
                    let fy = CGFloat((index * 43 + 7) % 100) / 100
                    let x = fx * size.width
                    let y = fy * size.height
                    let radius = CGFloat(1.1 + Double(index % 3) * 0.6)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                        with: .color(Color.white.opacity(0.14 + Double(index % 4) * 0.06))
                    )
                }
            }
            .blendMode(.screen)
        }
    }
}

struct ConstellationDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(ConstellationTypeScale.sectionTitle)
            content
        }
    }
}

struct ConstellationDetailCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder var content: Content

    init(padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(ConstellationPalette.cardStrong)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(ConstellationPalette.border.opacity(0.55), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
    }
}

struct ConstellationPosterView: View {
    let imageURL: String?
    let symbol: String
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let contentMode: ContentMode

    init(imageURL: String?, symbol: String, width: CGFloat = 128, height: CGFloat = 186, cornerRadius: CGFloat = 18, contentMode: ContentMode = .fill) {
        self.imageURL = imageURL
        self.symbol = symbol
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if imageURL != nil {
                RemotePosterImageView(imageURL: imageURL, contentMode: contentMode) {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [ConstellationPalette.deepIndigo, ConstellationPalette.cosmicPurple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
        }
    }
}

struct ConstellationMetricPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(ConstellationTypeScale.caption.weight(.semibold))
            Text(text)
                .font(ConstellationTypeScale.caption.weight(.semibold))
        }
        .foregroundStyle(ConstellationPalette.deepIndigo)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.86))
        .clipShape(Capsule())
    }
}

struct ConstellationTagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(ConstellationTypeScale.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(ConstellationPalette.accent.opacity(0.16))
            .foregroundStyle(ConstellationPalette.accent)
            .clipShape(Capsule())
    }
}
