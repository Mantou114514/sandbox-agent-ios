//  WebSocketManager.swift
//  SandboxAgent
//
//  WebSocket connection to Sandbox Agent server
//  Handles: audio streaming, text commands, responses

import Foundation
import Combine

class WebSocketManager: ObservableObject {
    static let shared = WebSocketManager()
    
    // Connection state
    @Published var isConnected = false
    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastError: String?
    
    // Response handling
    @Published var receivedText: String = ""
    @Published var receivedAudio: Data = Data()
    @Published var asrResult: String = ""
    
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed(Error)
    }
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession
    private var reconnectTimer: Timer?
    private let serverURL: String
    private var pingTimer: Timer?
    
    // Audio streaming
    private var audioSendQueue: [Data] = []
    private var isSendingAudio = false
    
    private init() {
        // Load server URL from config (UserDefaults or Config.plist)
        if let url = UserDefaults.standard.string(forKey: "serverURL"),
           !url.isEmpty {
            self.serverURL = url
        } else {
            // Default - change to your server IP
            self.serverURL = "ws://192.168.1.100:8765/ws/agent"
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    func connect() {
        guard connectionState != .connecting, connectionState != .connected else { return }
        
        connectionState = .connecting
        print("Connecting to \(serverURL)...")
        
        guard let url = URL(string: serverURL) else {
            connectionState = .failed(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        
        webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTask?.resume()
        
        receiveMessage()
        startPing()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.connectionState == .connecting {
                self?.connectionState = .failed(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection timeout"]))
            }
        }
    }
    
    func disconnect() {
        stopPing()
        stopReconnect()
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.connectionState = .disconnected
        }
    }
    
    func sendAudioChunk(_ data: Data) {
        // Send PCM audio chunk as base64
        let message = [
            "type": "audio_chunk",
            "data": data.base64EncodedString()
        ]
        sendJSON(message)
    }
    
    func sendAudioEnd() {
        let message = ["type": "audio_end"]
        sendJSON(message)
    }
    
    func sendTextCommand(_ text: String) {
        let message = [
            "type": "text_command",
            "data": text
        ]
        sendJSON(message)
    }
    
    func updateServerURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: "serverURL")
        // Reconnect with new URL
        disconnect()
        // Note: serverURL is immutable, would need to recreate manager
        // For simplicity, app restart needed
    }
    
    // MARK: - Private
    
    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else { return }
        
        let message = URLSessionWebSocketTask.Message.string(string)
        webSocketTask?.send(message) { error in
            if let error = error {
                print("Send failed: \(error)")
            }
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("Receive error: \(error)")
                DispatchQueue.main.async {
                    self?.handleDisconnection(error: error)
                }
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage() // Continue listening
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleTextMessage(text)
        case .data(let data):
            handleBinaryMessage(data)
        @unknown default:
            break
        }
    }
    
    private func handleTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        
        DispatchQueue.main.async { [weak self] in
            switch type {
            case "welcome":
                self?.isConnected = true
                self?.connectionState = .connected
                self?.receivedText = json["data"] as? String ?? ""
                
            case "asr_result":
                self?.asrResult = json["data"] as? String ?? ""
                self?.receivedText = "识别: \(self?.asrResult ?? "")"
                
            case "vn_response":
                self?.receivedText = json["data"] as? String ?? ""
                
            case "thinking":
                self?.receivedText = json["data"] as? String ?? ""
                
            case "error":
                self?.lastError = json["data"] as? String ?? ""
                
            case "pong":
                break // Heartbeat response
                
            default:
                print("Unknown message type: \(type)")
            }
        }
    }
    
    private func handleBinaryMessage(_ data: Data) {
        // Binary audio data from server (TTS output)
        DispatchQueue.main.async { [weak self] in
            self?.receivedAudio = data
            // Notify AudioManager to play
            NotificationCenter.default.post(name: .receivedAudioData, object: data)
        }
    }
    
    private func handleDisconnection(error: Error) {
        isConnected = false
        connectionState = .failed(error)
        stopPing()
        
        // Auto-reconnect after 3 seconds
        startReconnect()
    }
    
    private func startPing() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }
    
    private func stopPing() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func sendPing() {
        let message = URLSessionWebSocketTask.Message.string("ping")
        webSocketTask?.send(message) { error in
            if let error = error {
                print("Ping failed: \(error)")
            }
        }
    }
    
    private func startReconnect() {
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
    
    private func stopReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
}

// Notification names
extension Notification.Name {
    static let receivedAudioData = Notification.Name("receivedAudioData")
}