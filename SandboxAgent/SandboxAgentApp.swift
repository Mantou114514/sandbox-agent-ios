//  SandboxAgentApp.swift
//  SandboxAgent
//
//  Native iPhone "phone call" interface to Sandbox Agent via WebSocket
//  Uses CallKit for native incoming call UI + VoIP push for background

import SwiftUI
import CallKit
import PushKit

@main
struct SandboxAgentApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(CallManager.shared)
                .environmentObject(WebSocketManager.shared)
                .environmentObject(AudioManager.shared)
        }
    }
}

// AppDelegate handles VoIP push registration
class AppDelegate: NSObject, UIApplicationDelegate, PKPushRegistryDelegate {
    let pushRegistry = PKPushRegistry(queue: DispatchQueue.main)
    let callManager = CallManager.shared
    let wsManager = WebSocketManager.shared
    let audioManager = AudioManager.shared
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register for VoIP pushes
        pushRegistry.delegate = self
        pushRegistry.desiredPushTypes = [.voIP]
        
        // Configure CallKit
        callManager.configureProvider()
        
        // Connect WebSocket on launch
        wsManager.connect()
        
        return true
    }
    
    // MARK: - PKPushRegistryDelegate
    
    func pushRegistry(
        _ registry: PKPushRegistry,
        didUpdate pushCredentials: PKPushCredentials,
        for type: PKPushType
    ) {
        let token = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
        print("VoIP push token: \(token)")
        // Send token to server for push notifications
    }
    
    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        // Handle incoming VoIP push - show CallKit UI
        guard type == .voIP else { completion(); return }
        
        let uuid = UUID()
        let handle = "Sandbox Agent"
        
        callManager.reportIncomingCall(uuid: uuid, handle: handle) { error in
            if error == nil {
                // Store the call UUID for when user answers
                self.callManager.pendingCallUUID = uuid
            }
            completion()
        }
    }
}