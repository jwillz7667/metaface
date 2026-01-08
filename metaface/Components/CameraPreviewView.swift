//
//  CameraPreviewView.swift
//  metaface
//
//  View for displaying camera stream from Meta glasses.
//

import SwiftUI
import AVFoundation
import CoreImage

struct CameraPreviewView: View {
    let image: CGImage?
    let showOverlay: Bool
    let overlayOpacity: Double

    init(image: CGImage?, showOverlay: Bool = false, overlayOpacity: Double = 0.3) {
        self.image = image
        self.showOverlay = showOverlay
        self.overlayOpacity = overlayOpacity
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black

                // Camera image
                if let image = image {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    placeholderView
                }

                // Optional overlay
                if showOverlay {
                    Color.black.opacity(overlayOpacity)
                }
            }
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 50))
                .foregroundStyle(.gray)

            Text("No Video Feed")
                .font(.headline)
                .foregroundStyle(.gray)

            Text("Waiting for camera stream")
                .font(.subheadline)
                .foregroundStyle(.gray.opacity(0.7))
        }
    }
}

// MARK: - Face Overlay View
struct FaceOverlayView: View {
    let faces: [DetectedFace]
    let imageSize: CGSize
    let showLabels: Bool
    let boxColor: Color

    init(
        faces: [DetectedFace],
        imageSize: CGSize,
        showLabels: Bool = true,
        boxColor: Color = .green
    ) {
        self.faces = faces
        self.imageSize = imageSize
        self.showLabels = showLabels
        self.boxColor = boxColor
    }

    var body: some View {
        GeometryReader { geometry in
            ForEach(faces) { face in
                let bounds = face.normalizedBounds(for: geometry.size)

                FaceBoundingBox(
                    bounds: bounds,
                    color: boxColor,
                    showLabel: showLabels,
                    confidence: face.confidence
                )
            }
        }
    }
}

struct FaceBoundingBox: View {
    let bounds: CGRect
    let color: Color
    let showLabel: Bool
    let confidence: Float

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bounding box
            RoundedRectangle(cornerRadius: 8)
                .stroke(color, lineWidth: 2)
                .frame(width: bounds.width, height: bounds.height)

            // Confidence label
            if showLabel {
                Text(String(format: "%.0f%%", confidence * 100))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .offset(y: -20)
            }

            // Corner accents
            cornerAccents
        }
        .position(x: bounds.midX, y: bounds.midY)
    }

    private var cornerAccents: some View {
        GeometryReader { _ in
            // Top-left
            CornerAccent(rotation: 0, color: color)
                .position(x: 0, y: 0)

            // Top-right
            CornerAccent(rotation: 90, color: color)
                .position(x: bounds.width, y: 0)

            // Bottom-right
            CornerAccent(rotation: 180, color: color)
                .position(x: bounds.width, y: bounds.height)

            // Bottom-left
            CornerAccent(rotation: 270, color: color)
                .position(x: 0, y: bounds.height)
        }
        .frame(width: bounds.width, height: bounds.height)
    }
}

struct CornerAccent: View {
    let rotation: Double
    let color: Color
    let size: CGFloat = 15

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: size, y: 0))
        }
        .stroke(color, lineWidth: 3)
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
    }
}

// MARK: - Scanning Animation
struct ScanningAnimationView: View {
    @State private var animating = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Scanning line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .green.opacity(0.5), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 4)
                    .offset(y: animating ? geometry.size.height / 2 : -geometry.size.height / 2)
                    .animation(
                        .linear(duration: 2).repeatForever(autoreverses: true),
                        value: animating
                    )

                // Corner brackets
                VStack {
                    HStack {
                        ScanningCorner(position: .topLeft)
                        Spacer()
                        ScanningCorner(position: .topRight)
                    }
                    Spacer()
                    HStack {
                        ScanningCorner(position: .bottomLeft)
                        Spacer()
                        ScanningCorner(position: .bottomRight)
                    }
                }
                .padding(20)
            }
        }
        .onAppear {
            animating = true
        }
    }
}

struct ScanningCorner: View {
    enum Position {
        case topLeft, topRight, bottomLeft, bottomRight

        var rotation: Double {
            switch self {
            case .topLeft: return 0
            case .topRight: return 90
            case .bottomRight: return 180
            case .bottomLeft: return 270
            }
        }
    }

    let position: Position
    @State private var pulsing = false

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 30))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 30, y: 0))
        }
        .stroke(Color.green, lineWidth: 3)
        .frame(width: 30, height: 30)
        .rotationEffect(.degrees(position.rotation))
        .opacity(pulsing ? 1 : 0.5)
        .animation(
            .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
            value: pulsing
        )
        .onAppear {
            pulsing = true
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        CameraPreviewView(image: nil, showOverlay: false)

        ScanningAnimationView()
    }
    .frame(height: 400)
}
