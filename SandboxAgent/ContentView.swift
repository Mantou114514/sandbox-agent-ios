//  ContentView.swift
//  SandboxAgent
//
//  Main UI - shows connection status and call controls

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var callManager: CallManager
    @EnvironmentObject var wsManager: WebSocketManager
    @EnvironmentObject var audioManager: AudioManager
    
    @State private var showSettings = false
    @State private var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "ws://192.168.1.100:8765/ws/agent"
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(hex: "080c14"), Color(hex: "0f1520")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "phone.fill.circle")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("Sandbox Agent")
                            .font(.system(.title, design: .rounded, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text("语音驱动远程操控")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)
                    
                    // Connection Status Card
                    ConnectionStatusCard()
                    
                    // Call Control Button (Main Action)
                    CallControlButton()
                    
                    // Live Transcript / Response
                    ResponseDisplayCard()
                    
                    // Audio Level Indicator (when recording)
                    if audioManager.isRecording {
                        AudioLevelView(level: audioManager.audioLevel)
                    }
                    
                    Spacer()
                    
                    // Quick Actions
                    QuickActionsView()
                }
                .padding(.horizontal, 24)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) {
                SettingsView(serverURL: $serverURL)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Subviews

struct ConnectionStatusCard: View {
    @EnvironmentObject var wsManager: WebSocketManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Indicator
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.5), lineWidth: 2)
                        .scaleEffect(wsManager.isConnected ? 1.5 : 1.0)
                        .animation(
                            wsManager.isConnected ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : .default,
                            value: wsManager.isConnected
                        )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundColor(.white)
                
                if case .failed(let error) = wsManager.connectionState {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                } else if wsManager.isConnected {
                    Text("服务器已连接")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // Settings button
            Button(action: {}) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "0f1520"))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "1c2738"), lineWidth: 1)
                )
        )
    }
    
    private var statusColor: Color {
        switch wsManager.connectionState {
        case .connected: return .green
        case .connecting, .reconnecting: return .yellow
        case .disconnected: return .gray
        case .failed: return .red
        }
    }
    
    private var statusText: String {
        switch wsManager.connectionState {
        case .connected: return "已连接"
        case .connecting: return "连接中..."
        case .reconnecting: return "重连中..."
        case .disconnected: return "未连接"
        case .failed: return "连接失败"
        }
    }
}

struct CallControlButton: View {
    @EnvironmentObject var callManager: CallManager
    @EnvironmentObject var wsManager: WebSocketManager
    @EnvironmentObject var audioManager: AudioManager
    
    var body: some View {
        Button(action: handleCallAction) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(buttonColor.opacity(0.3))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)
                    .scaleEffect(callManager.callState == .active ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: callManager.callState == .active)
                
                // Main button
                Circle()
                    .fill(
                        LinearGradient(
                            colors: buttonGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: buttonColor.opacity(0.5), radius: 20, x: 0, y: 10)
                
                // Icon
                Image(systemName: buttonIcon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(callManager.callState == .active ? 180 : 0))
                    .animation(.spring(), value: callManager.callState)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(wsManager.connectionState == .connecting || wsManager.connectionState == .reconnecting)
        .opacity(wsManager.connectionState == .connecting || wsManager.connectionState == .reconnecting ? 0.5 : 1.0)
    }
    
    private var buttonColor: Color {
        switch callManager.callState {
        case .idle: return .green
        case .connecting: return .yellow
        case .active: return .red
        case .held: return .orange
        case .ending: return .gray
        }
    }
    
    private var buttonGradientColors: [Color] {
        switch callManager.callState {
        case .idle: return [Color(hex: "00c853"), Color(hex: "00e676")]
        case .connecting: return [Color(hex: "ffd600"), Color(hex: "ffea00")]
        case .active: return [Color(hex: "ff1744"), Color(hex: "ff5252")]
        case .held: return [Color(hex: "ff9100"), Color(hex: "ffab40")]
        case .ending: return [Color.gray, Color.gray.opacity(0.7)]
        }
    }
    
    private var buttonIcon: String {
        switch callManager.callState {
        case .idle: return "phone.fill"
        case .connecting: return "phone.arrow.up.right.fill"
        case .active: return "phone.down.fill"
        case .held: return "pause.circle.fill"
        case .ending: return "phone.down.circle.fill"
        }
    }
    
    private func handleCallAction() {
        switch callManager.callState {
        case .idle:
            callManager.startCall()
        case .active, .connecting:
            if let uuid = callManager.activeCallUUID {
                callManager.endCall(uuid: uuid)
            }
        case .held:
            if let uuid = callManager.activeCallUUID {
                callManager.holdCall(uuid: uuid, onHold: false)
            }
        case .ending:
            break
        }
    }
}

struct ResponseDisplayCard: View {
    @EnvironmentObject var wsManager: WebSocketManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Agent 回复")
                    .font(.system(.headline, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                if wsManager.connectionState == .connected {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(.cyan)
                        .symbolEffect(.pulse, options: .repeating)
                }
            }
            
            ScrollView {
                Text(wsManager.receivedText.isEmpty ? "等待指令..." : wsManager.receivedText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(wsManager.receivedText.isEmpty ? .gray : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 200)
            .background(Color(hex: "080c14"))
            .cornerRadius(12)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "0f1520"))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "1c2738"), lineWidth: 1)
                )
        )
    }
}

struct AudioLevelView: View {
    let level: Float
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(.green)
                Text("正在聆听...")
                    .font(.caption)
                    .foregroundColor(.green)
                Spacer()
            }
            
            // Audio level bars
            HStack(spacing: 4) {
                ForEach(0..<20, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .red],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 10, height: barHeight(for: i))
                        .animation(.easeOut(duration: 0.1), value: level)
                }
            }
            .frame(height: 50)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "0f1520"))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green.opacity(0.5), lineWidth: 1)
                )
        )
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let normalizedLevel = min(max(level / 10, 0), 1) // Normalize 0-1
        let threshold = Double(index) / 20.0
        let height = normalizedLevel > Float(threshold) ? CGFloat.random(in: 20...50) : 4
        return height
    }
}

struct QuickActionsView: View {
    @EnvironmentObject var wsManager: WebSocketManager
    @EnvironmentObject var callManager: CallManager
    
    let actions = [
        ("创建文件", "doc.badge.plus", "在沙盒创建新文件"),
        ("运行测试", "play.circle.fill", "执行 pytest 等测试"),
        ("查看文件", "folder.fill", "列出沙盒目录内容"),
        ("执行命令", "terminal.fill", "在沙盒运行 Shell 命令"),
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            Text("快捷指令")
                .font(.system(.headline, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(actions, id: \.0) { title, icon, description in
                    QuickActionButton(title: title, icon: icon, description: description) {
                        sendQuickCommand(title)
                    }
                }
            }
        }
    }
    
    private func sendQuickCommand(_ title: String) {
        let commands: [String: String] = [
            "创建文件": "帮我在沙盒里创建一个 hello.py 文件，打印 'Hello from iPhone'",
            "运行测试": "在沙盒运行 pytest 测试",
            "查看文件": "列出沙盒根目录下的所有文件",
            "执行命令": "在沙盒执行 ls -la 命令",
        ]
        
        if let cmd = commands[title] {
            wsManager.sendTextCommand(cmd)
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let description: String
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring()) { isPressed = false }
            }
            action()
        }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.cyan)
                    .frame(width: 44, height: 44)
                    .background(Color.cyan.opacity(0.1))
                    .clipShape(Circle())
                
                Text(title)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: "0f1520"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(hex: "1c2738"), lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var serverURL: String
    @EnvironmentObject var wsManager: WebSocketManager
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("服务器设置")) {
                    TextField("WebSocket URL", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            UserDefaults.standard.set(serverURL, forKey: "serverURL")
                            wsManager.disconnect()
                            // Note: Need app restart or manager recreation for new URL
                        }
                    
                    Text("格式: ws://IP:PORT/ws/agent")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Section(header: Text("连接状态")) {
                    HStack {
                        Text("状态")
                        Spacer()
                        Text(connectionStatusText)
                            .foregroundColor(connectionStatusColor)
                    }
                }
                
                Section {
                    Button("重新连接") {
                        wsManager.connect()
                    }
                    .foregroundColor(.cyan)
                }
                
                Section(header: Text("关于")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                    HStack {
                        Text("沙盒路径")
                        Spacer()
                        Text("~/sandbox_agent_workspace")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
    
    private var connectionStatusText: String {
        switch wsManager.connectionState {
        case .connected: return "已连接"
        case .connecting: return "连接中"
        case .reconnecting: return "重连中"
        case .disconnected: return "未连接"
        case .failed: return "失败"
        }
    }
    
    private var connectionStatusColor: Color {
        switch wsManager.connectionState {
        case .connected: return .green
        case .connecting, .reconnecting: return .yellow
        case .disconnected: return .gray
        case .failed: return .red
        }
    }
}

// MARK: - Helpers

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}