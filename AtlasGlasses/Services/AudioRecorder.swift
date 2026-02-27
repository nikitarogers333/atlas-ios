import AVFoundation
import Speech
import SwiftUI

@MainActor
final class AudioRecorder: ObservableObject {

    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var recordingDuration: Double = 0
    @Published var audioLevel: Float = 0
    @Published var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var startTime: Date?
    private var levelTimer: Timer?

    var hasPermission: Bool {
        AVAudioApplication.shared.recordPermission == .granted &&
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestPermissions() async -> Bool {
        let micGranted = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        guard micGranted else {
            errorMessage = "Microphone permission denied"
            return false
        }

        let speechGranted = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else {
            errorMessage = "Speech recognition permission denied"
            return false
        }

        return true
    }

    func startRecording() {
        guard !isRecording else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognizer unavailable"
            return
        }

        transcribedText = ""
        errorMessage = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Audio session error: \(error.localizedDescription)"
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    self?.transcribedText = result.bestTranscription.formattedString
                }
                if let error {
                    // Don't abort the entire app; surface the error and stop recording cleanly.
                    self?.errorMessage = "Speech recognition error: \(error.localizedDescription)"
                    self?.stopEngine()
                    return
                }
                if result?.isFinal == true {
                    self?.stopEngine()
                }
            }
        }

        do {
            try engine.start()
        } catch {
            errorMessage = "Engine start error: \(error.localizedDescription)"
            return
        }

        audioEngine = engine
        recognitionRequest = request
        startTime = Date()
        isRecording = true

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.recordingDuration = Date().timeIntervalSince(self.startTime ?? Date())
            }
        }
    }

    func stopRecording() -> (text: String, duration: Double) {
        let text = transcribedText
        let duration = Date().timeIntervalSince(startTime ?? Date())

        recognitionRequest?.endAudio()
        stopEngine()

        return (text, duration)
    }

    private func stopEngine() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
