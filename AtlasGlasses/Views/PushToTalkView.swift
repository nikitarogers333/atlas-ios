import SwiftUI

struct PushToTalkView: View {
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var senses: SensesClient

    @State private var isSending = false
    @State private var lastSentText = ""
    @State private var showTranscript = false

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack {
                Circle()
                    .fill(senses.isConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(senses.isConnected ? "Relay connected" : "Connecting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !senses.lastEvent.isEmpty {
                    Text(senses.lastEvent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Spacer()

            // Live transcript
            if recorder.isRecording || showTranscript {
                VStack(spacing: 12) {
                    if recorder.isRecording {
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.white)
                                    .frame(width: 3, height: CGFloat.random(in: 8...24))
                                    .animation(
                                        .easeInOut(duration: 0.3)
                                            .repeatForever(autoreverses: true)
                                            .delay(Double(i) * 0.1),
                                        value: recorder.isRecording
                                    )
                            }
                        }
                        .frame(height: 28)

                        Text(String(format: "%.1fs", recorder.recordingDuration))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Text(recorder.transcribedText.isEmpty ? "Listening..." : recorder.transcribedText)
                        .font(.body)
                        .foregroundStyle(recorder.transcribedText.isEmpty ? .secondary : .primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity)

                    if !lastSentText.isEmpty && !recorder.isRecording {
                        Label("Sent to Atlas", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                )
                .padding(.horizontal)
            }

            Spacer()

            // Push-to-talk button
            VStack(spacing: 16) {
                if let error = recorder.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    handleTap()
                } label: {
                    ZStack {
                        Circle()
                            .fill(recorder.isRecording ? .red : .white)
                            .frame(width: 80, height: 80)
                            .shadow(color: recorder.isRecording ? .red.opacity(0.5) : .white.opacity(0.3),
                                    radius: recorder.isRecording ? 20 : 8)

                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(recorder.isRecording ? .white : .black)
                    }
                }
                .disabled(isSending)
                .scaleEffect(recorder.isRecording ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)

                Text(recorder.isRecording ? "Tap to send" : "Tap to talk")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)
        }
        .background(Color.black)
    }

    private func handleTap() {
        if recorder.isRecording {
            let result = recorder.stopRecording()
            guard !result.text.isEmpty else {
                showTranscript = false
                return
            }

            lastSentText = result.text
            showTranscript = true
            isSending = true

            Task {
                try? await senses.pushAudioEvent(text: result.text, duration: result.duration)
                isSending = false

                try? await Task.sleep(for: .seconds(3))
                withAnimation { showTranscript = false }
            }
        } else {
            Task {
                if !recorder.hasPermission {
                    let granted = await recorder.requestPermissions()
                    guard granted else { return }
                }
                showTranscript = true
                recorder.startRecording()
            }
        }
    }
}
