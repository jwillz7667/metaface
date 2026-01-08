//
//  Color+Extensions.swift
//  metaface
//
//  Color extensions for the app's design system.
//

import SwiftUI

extension Color {
    // MARK: - Brand Colors
    static let metaBlue = Color(hex: "0064E0")
    static let metaPurple = Color(hex: "833AB4")
    static let metaGreen = Color(hex: "00B956")

    // MARK: - Semantic Colors
    static let scanActive = Color.green
    static let scanInactive = Color.gray
    static let ageYoung = Color.green
    static let ageMiddle = Color.orange
    static let ageSenior = Color.purple

    // MARK: - Gradient Colors
    static let primaryGradient = LinearGradient(
        colors: [.metaBlue, .metaPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let successGradient = LinearGradient(
        colors: [.metaGreen, Color(hex: "00D4AA")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Age Group Colors
    static func ageGroupColor(for age: Double) -> Color {
        switch age {
        case 0..<13: return .green
        case 13..<20: return .blue
        case 20..<36: return .purple
        case 36..<56: return .orange
        default: return .red
        }
    }

    // MARK: - Confidence Colors
    static func confidenceColor(for confidence: Double) -> Color {
        switch confidence {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .blue
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }

    // MARK: - Hex Initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Extensions
extension View {
    func glassmorphicBackground() -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    func cardShadow() -> some View {
        self.shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }

    func pulseAnimation(_ isActive: Bool, scale: CGFloat = 1.05) -> some View {
        self
            .scaleEffect(isActive ? scale : 1.0)
            .animation(
                isActive ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: isActive
            )
    }
}

// MARK: - Shimmer Effect
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            .white.opacity(0.3),
                            .clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                }
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
