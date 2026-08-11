//  AudioManager.swift
//  SandboxAgent
//
//  Handles audio recording (mic) and playback (TTS)
//  Uses AVAudioEngine for low-latency audio I/O

import Foundation
import AVFoundation
import Combine

class AudioManager: ObservableObject {
    static let shared = AudioManager()
    
    // Recording state
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    
    // Playback state
    @Published var isPlaying = false
    
    // Audio engine
    private let engine = AVAudioEngine()
    private let inputNode: AVAudioInputNode
    private let playerNode = AVAudioPlayerNode()
    private var audioFormat: AVAudioFormat!
    
    // Recording buffer
    private var recordingBuffers: [AVAudioPCMBuffer] = []
    private let bufferQueue = DispatchQueue(label: "audio.buffer.queue")
    
    // Playback
    private var playbackBuffer: AVAudioPCMBuffer?
    private var playbackCompletion: (() -> Void)?
    
    // WebSocket audio sending
    private var sendTimer: Timer?
    private let chunkDuration: Double = 0.1 // 100ms chunks
    
    private init() {
        self.inputNode = engine.inputNode
        setupAudioSession()
        observeNotifications()
    }
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowAirPlay])
            try session.setPreferredSampleRate(16000)
            try session.setPreferredIOBufferDuration(0.01) // 10ms
            try session.setActive(true)
            
            // Get native format (16kHz mono)
            audioFormat = inputNode.inputFormat(forBus: 0)
            print("Audio format: \(audioFormat)")
            
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReceivedAudio(_:)),
            name: .receivedAudioData,
            object: nil
        )
        
        // Handle interruptions (phone calls, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
    
    @objc private func handleReceivedAudio(_ notification: Notification) {
        guard let data = notification.object as? Data else { return }
        playAudioData(data)
    }
    
    @objc private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        if type == .began {
            // Pause recording/playback
            if isRecording { pauseRecording() }
            if isPlaying { pausePlayback() }
        } else if type == .ended {
            // Resume if needed
            if let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                if isRecording { resumeRecording() }
            }
        }
    }
    
    // MARK: - Recording (Microphone -> WebSocket)
    
    func startRecording() {
        guard !isRecording else { return }
        
        recordingBuffers.removeAll()
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: audioFormat) { [weak self] buffer, time in
            self?.processInputBuffer(buffer)
        }
        
        do {
            try engine.start()
            isRecording = true
            
            // Start sending chunks periodically
            startSendTimer()
            
            print("Recording started")
        } catch {
            print("Engine start failed: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        stopSendTimer()
        inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        
        // Send any remaining audio
        sendRemainingAudio()
        
        // Signal audio end to server
        WebSocketManager.shared.sendAudioEnd()
        
        print("Recording stopped")
    }
    
    func pauseRecording() {
        guard isRecording else { return }
        stopSendTimer()
        inputNode.removeTap(onBus: 0)
        engine.pause()
        print("Recording paused")
    }
    
    func resumeRecording() {
        guard !isRecording, engine.isRunning == false else { return }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: audioFormat) { [weak self] buffer, time in
            self?.processInputBuffer(buffer)
        }
        
        do {
            try engine.start()
            isRecording = true
            startSendTimer()
            print("Recording resumed")
        } catch {
            print("Resume failed: \(error)")
        }
    }
    
    private func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        // Calculate audio level for UI
        let level = calculateAudioLevel(buffer)
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = level
        }
        
        // Queue buffer for sending
        bufferQueue.async { [weak self] in
            self?.recordingBuffers.append(buffer)
        }
    }
    
    private func calculateAudioLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += abs(channelData[i])
        }
        return sum / Float(frameLength) * 10 // Scale for UI
    }
    
    private func startSendTimer() {
        sendTimer = Timer.scheduledTimer(withTimeInterval: chunkDuration, repeats: true) { [weak self] _ in
            self?.sendAudioChunk()
        }
    }
    
    private func stopSendTimer() {
        sendTimer?.invalidate()
        sendTimer = nil
    }
    
    private func sendAudioChunk() {
        let buffers = bufferQueue.sync { () -> [AVAudioPCMBuffer] in
            let copy = recordingBuffers
            recordingBuffers.removeAll()
            return copy
        }
        
        for buffer in buffers {
            // Convert to PCM Data (16-bit)
            let pcmData = bufferToPCMData(buffer)
            if !pcmData.isEmpty {
                WebSocketManager.shared.sendAudioChunk(pcmData)
            }
        }
    }
    
    private func sendRemainingAudio() {
        let buffers = bufferQueue.sync { () -> [AVAudioPCMBuffer] in
            let copy = recordingBuffers
            recordingBuffers.removeAll()
            return copy
        }
        
        for buffer in buffers {
            let pcmData = bufferToPCMData(buffer)
            if !pcmData.isEmpty {
                WebSocketManager.shared.sendAudioChunk(pcmData)
            }
        }
    }
    
    private func bufferToPCMData(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let channelData = buffer.floatChannelData?[0] else { return Data() }
        let frameLength = Int(buffer.frameLength)
        
        var data = Data()
        data.reserveCapacity(frameLength * 2)
        
        for i in 0..<frameLength {
            let sample = channelData[i]
            // Convert float (-1.0 to 1.0) to int16
            let int16 = Int16(max(-32768, min(32767, Int(sample * 32767))))
            withUnsafeBytes(of: int16.littleEndian) { data.append(contentsOf: $0) }
        }
        
        return data
    }
    
    // MARK: - Playback (TTS -> Speaker)
    
    func playAudioData(_ data: Data) {
        // Server sends MP3, decode and play
        decodeAndPlayMP3(data)
    }
    
    private func decodeAndPlayMP3(_ data: Data) {
        // Write to temp file and use AVAudioFile to decode
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("tts_\(UUID().uuidString).mp3")
        
        do {
            try data.write(to: tempURL)
            
            let audioFile = try AVAudioFile(forReading: tempURL)
            let format = audioFile.processingFormat
            let frameCount = UInt32(audioFile.length)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                print("Failed to create buffer")
                return
            }
            
            try audioFile.read(into: buffer)
            
            playBuffer(buffer)
            
        } catch {
            print("MP3 decode/play failed: \(error)")
        }
    }
    
    private func playBuffer(_ buffer: AVAudioPCMBuffer) {
        // Attach player if not already
        if !engine.attachedNodes.contains(playerNode) {
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: buffer.format)
        }
        
        // Stop any current playback
        playerNode.stop()
        
        isPlaying = true
        playerNode.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                self?.isPlaying = false
                self?.playbackCompletion?()
            }
        }
        
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("Engine start for playback failed: \(error)")
                isPlaying = false
                return
            }
        }
        
        playerNode.play()
    }
    
    func pausePlayback() {
        playerNode.pause()
        isPlaying = false
    }
    
    func resumePlayback() {
        playerNode.play()
        isPlaying = true
    }
    
    func setMuted(_ muted: Bool) {
        engine.mainMixerNode.outputVolume = muted ? 0 : 1
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopRecording()
        playerNode.stop()
        engine.stop()
        NotificationCenter.default.removeObserver(self)
    }
}