import SwiftUI

struct TTSDiagnosticsView: View {
    @ObservedObject var viewModel: TTSDiagnosticsViewModel
    var onToggle: () -> Void
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Audio level meter
            audioLevelMeter

            VStack(alignment: .leading, spacing: 4) {
                // Controls
                HStack {
                    Button(action: onToggle) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(viewModel.isPlaying ? Color.orange : Color.green)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")

                    Text("The Raven")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityLabel("Stop")
                }

                // Raven text with word highlighting
                ScrollView {
                    highlightedText
                        .padding(.horizontal, 4)
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.85))
        .cornerRadius(8)
    }

    // MARK: - Audio Level Meter

    private var audioLevelMeter: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let fillHeight = CGFloat(viewModel.audioLevel) * height
            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(audioLevelColor)
                    .frame(width: 6, height: max(fillHeight, 2))
            }
        }
        .frame(width: 10)
    }

    private var audioLevelColor: Color {
        if viewModel.audioLevel > 0.8 {
            return .red
        } else if viewModel.audioLevel > 0.5 {
            return .yellow
        } else {
            return .green
        }
    }

    // MARK: - Highlighted Text

    private var highlightedText: some View {
        let text = viewModel.text
        if let range = viewModel.highlightRange,
           let swiftRange = Range(range, in: text) {
            let before = text[text.startIndex..<swiftRange.lowerBound]
            let highlighted = text[swiftRange]
            let after = text[swiftRange.upperBound..<text.endIndex]
            return Text(before)
                .font(.system(size: 11, design: .serif))
                .foregroundColor(.gray)
            + Text(highlighted)
                .font(.system(size: 11, design: .serif))
                .foregroundColor(.white)
                .bold()
            + Text(after)
                .font(.system(size: 11, design: .serif))
                .foregroundColor(.gray)
        } else {
            return Text(text)
                .font(.system(size: 11, design: .serif))
                .foregroundColor(.gray)
            + Text("")
            + Text("")
        }
    }
}
