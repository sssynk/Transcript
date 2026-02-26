import SwiftUI

struct PillView: View {
    var state: AppState

    var body: some View {
        VStack {
            Spacer()

            if state.isVisible {
                pillContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            Spacer().frame(height: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.isVisible)
    }

    @ViewBuilder
    private var pillContent: some View {
        HStack(spacing: 10) {
            Group {
                switch state.phase {
                case .recording:
                    HStack(spacing: 10) {
                        RecordingDot()
                        WaveformView(levels: state.audioLevels)
                    }

                case .processing:
                    HStack(spacing: 9) {
                        SpinnerView()
                        Text("Transcribing")
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                case .success(let msg):
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(red: 0.2, green: 0.83, blue: 0.6))
                        Text(msg)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                case .error(let msg):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.orange.opacity(0.8))
                        Text(msg)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }

                case .idle:
                    EmptyView()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.15), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.phase)
    }
}

// MARK: - Recording indicator

private struct RecordingDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 8, height: 8)
            .shadow(color: .red.opacity(pulse ? 0.7 : 0.2), radius: pulse ? 6 : 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Waveform

private struct WaveformView: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.85))
                    .frame(width: 3.5, height: max(4, level * 20))
            }
        }
        .frame(height: 20)
        .animation(.easeOut(duration: 0.08), value: levels)
    }
}

// MARK: - Loading spinner

private struct SpinnerView: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.65)
            .stroke(
                AngularGradient(
                    colors: [
                        Color(red: 0.02, green: 0.71, blue: 0.83),
                        Color(red: 0.49, green: 0.23, blue: 0.93),
                        Color(red: 0.02, green: 0.71, blue: 0.83).opacity(0.2),
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: 18, height: 18)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
