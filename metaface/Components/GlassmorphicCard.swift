//
//  GlassmorphicCard.swift
//  metaface
//
//  A reusable glassmorphic card component.
//

import SwiftUI

struct GlassmorphicCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
            )
    }
}

// MARK: - Card Variants
struct GradientCard<Content: View>: View {
    let gradient: [Color]
    let content: Content

    init(gradient: [Color] = [.blue, .purple], @ViewBuilder content: () -> Content) {
        self.gradient = gradient
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: gradient.map { $0.opacity(0.8) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: gradient.first?.opacity(0.3) ?? .clear, radius: 10, x: 0, y: 5)
            )
    }
}

struct OutlineCard<Content: View>: View {
    let color: Color
    let content: Content

    init(color: Color = .accentColor, @ViewBuilder content: () -> Content) {
        self.color = color
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(color.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(color.opacity(0.3), lineWidth: 1.5)
                    )
            )
    }
}

// MARK: - Neumorphic Card
struct NeumorphicCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(
                        color: colorScheme == .dark ? .black.opacity(0.5) : .black.opacity(0.1),
                        radius: 10,
                        x: 5,
                        y: 5
                    )
                    .shadow(
                        color: colorScheme == .dark ? .white.opacity(0.05) : .white.opacity(0.7),
                        radius: 10,
                        x: -5,
                        y: -5
                    )
            )
    }
}

// MARK: - Preview
#Preview {
    ScrollView {
        VStack(spacing: 20) {
            GlassmorphicCard {
                VStack(alignment: .leading) {
                    Text("Glassmorphic Card")
                        .font(.headline)
                    Text("A frosted glass effect card")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GradientCard(gradient: [.blue, .purple]) {
                VStack(alignment: .leading) {
                    Text("Gradient Card")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("A gradient background card")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            OutlineCard(color: .green) {
                VStack(alignment: .leading) {
                    Text("Outline Card")
                        .font(.headline)
                    Text("A card with an outline border")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            NeumorphicCard {
                VStack(alignment: .leading) {
                    Text("Neumorphic Card")
                        .font(.headline)
                    Text("A soft shadow effect card")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
