import Foundation
import Combine

/// Relay command sent from senses server to this device.
struct RelayRequest: Decodable {
    let id: Int
    let request: RequestPayload

    struct RequestPayload: Decodable {
        let type: String
        let seconds: Double?
        let count: Int?
        let interval_ms: Int?
        let text: String?
    }
}

/// Connection state observable by SwiftUI views.
@MainActor
final class SensesClient: ObservableObject {

    static let shared = SensesClient()

    @Published var isConnected = false
    @Published var lastEvent: String = ""
    @Published var pendingRequest: RelayRequest?

    private let baseURL: URL
    private let phoneToken: String?
    private var sseTask: URLSessionDataTask?
    private var sseSession: URLSession?
    private var reconnectWork: DispatchWorkItem?

    init(
        baseURL: URL = URL(string: "https://senses.up.railway.app")!,
        phoneToken: String? = nil
    ) {
        self.baseURL = baseURL
        self.phoneToken = phoneToken
    }

    // MARK: - SSE Connection

    func connect() {
        disconnect()

        let url = baseURL.appendingPathComponent("phone/events")
        var request = URLRequest(url: url)
        request.timeoutInterval = .infinity
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let token = phoneToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = .infinity
        config.timeoutIntervalForResource = .infinity

        let delegate = SSEDelegate { [weak self] eventName, data in
            Task { @MainActor in
                self?.handleSSE(event: eventName, data: data)
            }
        } onDisconnect: { [weak self] in
            Task { @MainActor in
                self?.isConnected = false
                self?.scheduleReconnect()
            }
        }

        sseSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        sseTask = sseSession?.dataTask(with: request)
        sseTask?.resume()
    }

    func disconnect() {
        reconnectWork?.cancel()
        sseTask?.cancel()
        sseTask = nil
        sseSession?.invalidateAndCancel()
        sseSession = nil
        isConnected = false
    }

    private func scheduleReconnect() {
        reconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.connect()
            }
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func handleSSE(event: String, data: String) {
        switch event {
        case "hello":
            isConnected = true
            lastEvent = "Connected to relay"

        case "ping":
            break

        case "request":
            guard let jsonData = data.data(using: .utf8) else { return }
            do {
                let req = try JSONDecoder().decode(RelayRequest.self, from: jsonData)
                pendingRequest = req
                lastEvent = "Request: \(req.request.type) (#\(req.id))"
            } catch {
                lastEvent = "Parse error: \(error.localizedDescription)"
            }

        default:
            lastEvent = "[\(event)] \(data.prefix(100))"
        }
    }

    // MARK: - Respond to relay

    func respond(id: Int, type: String, result: Any) async throws {
        let url = baseURL.appendingPathComponent("phone/respond")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = phoneToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "id": id,
            "response": [
                "type": type,
                "result": result
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    /// Send a transcription result back through the relay.
    func sendTranscription(id: Int, text: String, duration: Double) async {
        let result: [String: Any] = [
            "text": text,
            "duration_seconds": duration,
            "confidence": 0.95
        ]
        try? await respond(id: id, type: "transcribeAudio", result: result)
        await MainActor.run { pendingRequest = nil }
    }

    /// Send an audio transcription as an event (push-to-talk, no relay request needed).
    func pushAudioEvent(text: String, duration: Double) async throws {
        let url = baseURL.appendingPathComponent("events")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "type": "audio_transcription",
            "data": [
                "text": text,
                "duration_seconds": duration,
                "source": "phone_mic"
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
}

// MARK: - SSE URLSession Delegate

private final class SSEDelegate: NSObject, URLSessionDataDelegate {
    private let onEvent: (String, String) -> Void
    private let onDisconnect: () -> Void
    private var buffer = ""

    init(onEvent: @escaping (String, String) -> Void, onDisconnect: @escaping () -> Void) {
        self.onEvent = onEvent
        self.onDisconnect = onDisconnect
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk

        while let range = buffer.range(of: "\n\n") {
            let block = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            parseSSEBlock(block)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onDisconnect()
    }

    private func parseSSEBlock(_ block: String) {
        var event = "message"
        var data = ""

        for line in block.components(separatedBy: "\n") {
            if line.hasPrefix("event:") {
                event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                data += data.isEmpty ? value : "\n\(value)"
            }
        }

        if !data.isEmpty || event != "message" {
            onEvent(event, data)
        }
    }
}
