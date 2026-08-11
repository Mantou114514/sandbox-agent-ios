//  CallManager.swift
//  SandboxAgent
//
//  Manages CallKit integration for native phone call experience

import Foundation
import CallKit
import Combine

class CallManager: ObservableObject {
    static let shared = CallManager()
    
    let callController = CXCallController()
    let provider: CXProvider
    var providerDelegate: ProviderDelegate?
    
    // Track active call
    @Published var activeCallUUID: UUID?
    @Published var callState: CallState = .idle
    var pendingCallUUID: UUID?
    
    enum CallState {
        case idle
        case connecting
        case active
        case held
        case ending
    }
    
    private init() {
        // Configure CXProvider for native call experience
        let configuration = CXProviderConfiguration(localizedName: "Sandbox Agent")
        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = true
        
        // Custom ringtone (optional - add to bundle)
        // configuration.ringtoneSound = "ringtone.caf"
        
        self.provider = CXProvider(configuration: configuration)
        self.providerDelegate = ProviderDelegate(callManager: self)
        self.provider.setDelegate(self.providerDelegate, queue: DispatchQueue.main)
    }
    
    func configureProvider() {
        // Additional configuration if needed
    }
    
    // MARK: - Outgoing Call (User initiates)
    
    func startCall() {
        let uuid = UUID()
        let handle = CXHandle(type: .generic, value: "Sandbox Agent")
        let startAction = CXStartCallAction(call: uuid, handle: handle)
        let transaction = CXTransaction(actions: [startAction])
        
        callState = .connecting
        activeCallUUID = uuid
        
        callController.request(transaction) { [weak self] error in
            if let error = error {
                print("Start call failed: \(error)")
                self?.callState = .idle
                self?.activeCallUUID = nil
            } else {
                print("Call started successfully")
                self?.callState = .active
                // Connect WebSocket and start audio
                WebSocketManager.shared.connect()
                AudioManager.shared.startRecording()
            }
        }
    }
    
    // MARK: - Incoming Call (VoIP Push)
    
    func reportIncomingCall(uuid: UUID, handle: String, completion: @escaping (Error?) -> Void) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle)
        update.hasVideo = false
        update.supportsHolding = true
        update.supportsGrouping = false
        update.supportsUngrouping = false
        
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            completion(error)
        }
    }
    
    // MARK: - Call Actions
    
    func answerCall(uuid: UUID) {
        let action = CXAnswerCallAction(call: uuid)
        let transaction = CXTransaction(action: action)
        
        callController.request(transaction) { [weak self] error in
            if error == nil {
                self?.callState = .active
                self?.activeCallUUID = uuid
                WebSocketManager.shared.connect()
                AudioManager.shared.startRecording()
            }
        }
    }
    
    func endCall(uuid: UUID) {
        let action = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: action)
        
        callState = .ending
        
        callController.request(transaction) { [weak self] error in
            if error == nil {
                self?.callState = .idle
                self?.activeCallUUID = nil
                WebSocketManager.shared.disconnect()
                AudioManager.shared.stopRecording()
            }
        }
    }
    
    func holdCall(uuid: UUID, onHold: Bool) {
        let action = CXSetHeldCallAction(call: uuid, onHold: onHold)
        let transaction = CXTransaction(action: action)
        
        callController.request(transaction) { [weak self] error in
            if error == nil {
                self?.callState = onHold ? .held : .active
                if onHold {
                    AudioManager.shared.pauseRecording()
                } else {
                    AudioManager.shared.resumeRecording()
                }
            }
        }
    }
    
    // MARK: - Audio Session
    
    func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
    }
    
    func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Provider Delegate

import AVFoundation

class ProviderDelegate: NSObject, CXProviderDelegate {
    weak var callManager: CallManager?
    
    init(callManager: CallManager) {
        self.callManager = callManager
        super.init()
    }
    
    func providerDidReset(_ provider: CXProvider) {
        callManager?.callState = .idle
        callManager?.activeCallUUID = nil
    }
    
    func provider(
        _ provider: CXProvider,
        perform action: CXStartCallAction
    ) {
        callManager?.activateAudioSession()
        action.fulfill()
    }
    
    func provider(
        _ provider: CXProvider,
        perform action: CXAnswerCallAction
    ) {
        callManager?.activateAudioSession()
        action.fulfill()
    }
    
    func provider(
        _ provider: CXProvider,
        perform action: CXEndCallAction
    ) {
        callManager?.deactivateAudioSession()
        action.fulfill()
    }
    
    func provider(
        _ provider: CXProvider,
        perform action: CXSetHeldCallAction
    ) {
        action.fulfill()
    }
    
    func provider(
        _ provider: CXProvider,
        perform action: CXSetMutedCallAction
    ) {
        AudioManager.shared.setMuted(action.isMuted)
        action.fulfill()
    }
    
    func provider(
        _ provider: CXProvider,
        timedOutPerforming action: CXAction
    ) {
        print("Action timed out: \(action)")
    }
}