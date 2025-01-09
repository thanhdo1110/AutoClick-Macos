//
//  AutoClickApp.swift
//  AutoClick
//
//  Created by Đỗ Thành on 08/01/2025.
//

import SwiftUI

@main
struct AutoClickApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
             
                    ConfigManager.shared.loadConfig()
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle()) // Ẩn thanh tiêu đề
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .undoRedo) {} 
        }
    }
}

// MARK: - Config Manager
class ConfigManager {
    static var shared = ConfigManager()
    private var configFileName = "autoclick_config.json"
    
    struct AppConfig: Codable {
        var clickPositions: [ClickPosition]
        var hotkey: String
        var globalRepeatCount: Int
        var isInfiniteLoop: Bool
        var showCircles: Bool
    }
    
    func saveConfig(clickPositions: [ClickPosition], hotkey: String, globalRepeatCount: Int, isInfiniteLoop: Bool, showCircles: Bool) {
        let config = AppConfig(clickPositions: clickPositions, hotkey: hotkey, globalRepeatCount: globalRepeatCount, isInfiniteLoop: isInfiniteLoop, showCircles: showCircles)
        
        if let encodedData = try? JSONEncoder().encode(config) {
            if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = documentsDirectory.appendingPathComponent(configFileName)
                do {
                    try encodedData.write(to: fileURL)
                } catch {
                    print("Failed to write config to file: \(error)")
                }
            }
        }
    }
    
    func loadConfig() -> AppConfig? {
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentsDirectory.appendingPathComponent(configFileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let config = try JSONDecoder().decode(AppConfig.self, from: data)
                    return config
                } catch {
                    print("Failed to load config from file: \(error)")
                }
            } else {
                print("Config file does not exist. A new one will be created when saving.")
            }
        }
        return nil
    }
}

// MARK: - Click Position Model
struct ClickPosition: Identifiable, Codable {
    var id = UUID()
    var point: CGPoint
    var delay: Double
    var isVisible: Bool = true
    var order: Int
}

// MARK: - Circle Window
class CircleWindow: NSWindow {
    var onDrag: ((CGPoint) -> Void)?
    var initialLocation: CGPoint = .zero
    var id: UUID
    
    init(position: CGPoint, order: Int, id: UUID) {
        self.id = id
        let windowSize = CGSize(width: 50, height: 50)
        let windowRect = NSRect(origin: position, size: windowSize)
        super.init(contentRect: windowRect, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.level = .floating
        self.isMovableByWindowBackground = true
        
        let circleView = NSHostingView(rootView: CircleView(order: order))
        circleView.frame = NSRect(origin: .zero, size: windowSize)
        self.contentView = circleView
    
        // Add tracking area to handle mouse events
        let trackingArea = NSTrackingArea(
            rect: circleView.bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        circleView.addTrackingArea(trackingArea)
    }
    
    override func mouseDown(with event: NSEvent) {
        initialLocation = event.locationInWindow
    }
    
    override func mouseDragged(with event: NSEvent) {
        let newLocation = event.locationInWindow
        let deltaX = newLocation.x - initialLocation.x
        let deltaY = newLocation.y - initialLocation.y
        
        var newOrigin = self.frame.origin
        newOrigin.x += deltaX
        newOrigin.y += deltaY
        
        self.setFrameOrigin(newOrigin)
        
        // Convert y-coordinate to match macOS coordinate system
        if let screenFrame = NSScreen.main?.frame {
            let flipY = CGPoint(x: newOrigin.x + 25, y: screenFrame.height - (newOrigin.y + 25)) // Center of the circle
            onDrag?(flipY)
        }
    }
}

// MARK: - Circle View
struct CircleView: View {
    var order: Int
    
    var body: some View {
        Circle()
            .fill(Color.blue.opacity(0.1))
            .frame(width: 50, height: 50)
            .overlay(Text("\(order)").foregroundColor(.white))
    }
}

// MARK: - VisualEffectView (AppKit)
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Custom Button Style
struct NeumorphicButtonStyle: ButtonStyle {
    var borderColor: Color = .clear
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(10)
            .background(
                Group {
                    if configuration.isPressed {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.3))
                            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.5))
                            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
                    }
                }
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut, value: configuration.isPressed)
    }
}

// MARK: - ContentView
struct ContentView: View {
    @State private var isAutoClicking = false
    @State private var timer: Timer?
    @State private var clickPositions: [ClickPosition] = []
    @State private var circleWindows: [UUID: CircleWindow] = [:]
    @State private var selectedTab: Int = 0
    @State private var showCircles: Bool = true
    @State private var globalRepeatCount: Int = 1
    @State private var isInfiniteLoop: Bool = false
    @State private var hotkey: String = ""
    @State private var isEditingHotkey: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showConfigPopup: Bool = false
    @State private var configs: [Config] = []
    @State private var isRecording: Bool = false
    @State private var recordedActions: [Action] = []
    @State private var recordingStartTime: Date = Date()
    @State private var isPlayingConfig: Bool = false
    
    // MARK: Lock for thread-safe access
    private let circleWindowsLock = NSLock()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background with Visual Effect (fully transparent)
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    .edgesIgnoringSafeArea(.all)

                // Main Content
                VStack(spacing: 16) {
                    Picker("Tab", selection: $selectedTab) {
                        Text("Home").tag(0)
                        Text("Chức năng").tag(1)
                        Text("Cấu hình").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, 16)
                    .frame(width: geometry.size.width * 0.8) // Adjust the width of the picker

                    // Tab Content
                    Group {
                        if selectedTab == 0 {
                            HomeTab()
                        } else if selectedTab == 1 {
                            FunctionTab(
                                isAutoClicking: $isAutoClicking,
                                clickPositions: $clickPositions,
                                circleWindows: $circleWindows,
                                showCircles: $showCircles,
                                globalRepeatCount: $globalRepeatCount,
                                isInfiniteLoop: $isInfiniteLoop,
                                hotkey: $hotkey,
                                isEditingHotkey: $isEditingHotkey,
                                showAlert: $showAlert,
                                alertMessage: $alertMessage
                            )
                        } else {
                            ConfigTab(
                                configs: $configs,
                                showConfigPopup: $showConfigPopup,
                                isRecording: $isRecording,
                                recordedActions: $recordedActions,
                                recordingStartTime: $recordingStartTime,
                                isAutoClicking: $isAutoClicking,
                                isPlayingConfig: $isPlayingConfig
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16) // Thêm padding để không chạm viền
                    .background(
                        VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                            .cornerRadius(12)
                    )
                    .padding(.horizontal, 16) // Thêm padding ngang để không chạm viền
                }
                .padding(.vertical, 16) // Thêm padding dọc để không chạm viền
            }
        }
        .frame(minWidth: 600, minHeight: 300) // Adjust the minimum size of the window
        .preferredColorScheme(.dark)
        .onAppear {
            loadConfig()
            setupHotkeyListener()
        }
        .onDisappear {
            saveConfig()
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Thông báo"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK")) {
                    // Đảm bảo không có logic nào truy cập vào đối tượng đã bị giải phóng
                    print("OK pressed")
                }
            )
        }
        .sheet(isPresented: $showConfigPopup) {
            ConfigPopupView(
                isRecording: $isRecording,
                recordedActions: $recordedActions,
                recordingStartTime: $recordingStartTime,
                configs: $configs,
                showConfigPopup: $showConfigPopup
            )
        }
    }

    // Load saved config
    func loadConfig() {
        if let config = ConfigManager.shared.loadConfig() {
            clickPositions = config.clickPositions
            hotkey = config.hotkey
            globalRepeatCount = config.globalRepeatCount
            isInfiniteLoop = config.isInfiniteLoop
            showCircles = config.showCircles
            
            if showCircles {
                for position in clickPositions {
                    showCircle(at: position.point, for: position.id)
                }
            }
        }
    }

    // Save config
    func saveConfig() {
        ConfigManager.shared.saveConfig(
            clickPositions: clickPositions,
            hotkey: hotkey,
            globalRepeatCount: globalRepeatCount,
            isInfiniteLoop: isInfiniteLoop,
            showCircles: showCircles
        )
    }

    // Setup hotkey listener
    func setupHotkeyListener() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if self.hotkey.isEmpty { return event }
            
            let modifiers = event.modifierFlags
            let key = event.charactersIgnoringModifiers ?? ""
            
            var hotkeyString = ""
            if modifiers.contains(.command) {
                hotkeyString += "Cmd+"
            }
            if modifiers.contains(.control) {
                hotkeyString += "Ctrl+"
            }
            if modifiers.contains(.option) {
                hotkeyString += "Option+"
            }
            if modifiers.contains(.shift) {
                hotkeyString += "Shift+"
            }
            hotkeyString += key
            
            print("Phím tắt được nhấn: \(hotkeyString)")
            
            if hotkeyString == self.hotkey {
                print("Phím tắt khớp: \(self.hotkey)")
                self.isAutoClicking.toggle()
                if self.isAutoClicking {
                    self.runClickPositions()
                }
                return nil
            }
            return event
        }
    }

   // Run click positions
    func runClickPositions() {
        isAutoClicking = true
        alertMessage = "Auto Click đã được kích hoạt."
        showAlert = true
        
        // Hide all circles
        circleWindowsLock.lock()
        for window in circleWindows.values {
            window.close()
        }
        circleWindows.removeAll()
        circleWindowsLock.unlock()
        
        DispatchQueue.global(qos: .userInitiated).async {
            var repeatCount = self.isInfiniteLoop ? Int.max : self.globalRepeatCount
            while self.isAutoClicking && repeatCount > 0 {
                for position in self.clickPositions {
                    DispatchQueue.main.async {
                        self.click(at: position.point)
                    }
                    Thread.sleep(forTimeInterval: position.delay)
                }
                repeatCount -= 1
            }
            
            DispatchQueue.main.async {
                self.isAutoClicking = false
                self.alertMessage = "Auto Click đã được tắt."
                self.showAlert = true
                // Show all circles again
                if self.showCircles {
                    for position in self.clickPositions {
                         self.showCircle(at: position.point, for: position.id)
                    }
                }
            }
        }
    }


    // Simulate a click at a specific position
    func click(at position: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let eventDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: position, mouseButton: .left)
        let eventUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: position, mouseButton: .left)
        eventDown?.post(tap: .cghidEventTap)
        eventUp?.post(tap: .cghidEventTap)
    }

   // Show circle at a specific position
    func showCircle(at position: CGPoint, for id: UUID) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let flipY = CGPoint(x: position.x - 25, y: screenFrame.height - (position.y + 25))
        
        DispatchQueue.main.async {
            guard let order = self.clickPositions.first(where: { $0.id == id })?.order else { return }
           
            let circleWindow = CircleWindow(position: flipY, order: order, id: id)
            circleWindow.onDrag = { newPosition in
                if let index = self.clickPositions.firstIndex(where: { $0.id == id }) {
                    self.clickPositions[index].point = newPosition
                }
            }
            circleWindow.orderFront(nil)
           
            self.circleWindowsLock.lock()
            self.circleWindows[id] = circleWindow
            self.circleWindowsLock.unlock()
        }
    }


    // Hide circle for a specific position
     func hideCircle(for id: UUID) {
         DispatchQueue.main.async {
             self.circleWindowsLock.lock()
            if let circleWindow = self.circleWindows[id] {
                circleWindow.close()
                 self.circleWindows.removeValue(forKey: id)
            }
             self.circleWindowsLock.unlock()
         }
    }
}

// MARK: - Home Tab
struct HomeTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Auto Clicker")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.top, 16)
            
            Text("Ứng dụng Auto Clicker giúp bạn tự động click chuột tại các vị trí chỉ định.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
            
            Text("Chức năng chính:")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.top, 16)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Thêm và quản lý nhiều vị trí click.")
                Text("• Hiển thị vòng tròn màu xanh để xác định vị trí click.")
                Text("• Kéo thả vòng tròn để thay đổi vị trí click.")
                Text("• Cài đặt delay và số lần click cho từng vị trí.")
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Function Tab
struct FunctionTab: View {
    @Binding var isAutoClicking: Bool
    @Binding var clickPositions: [ClickPosition]
    @Binding var circleWindows: [UUID: CircleWindow]
    @Binding var showCircles: Bool
    @Binding var globalRepeatCount: Int
    @Binding var isInfiniteLoop: Bool
    @Binding var hotkey: String
    @Binding var isEditingHotkey: Bool
    @Binding var showAlert: Bool
    @Binding var alertMessage: String
    
    // MARK: Lock for thread-safe access
    private let circleWindowsLock = NSLock()
    
    var body: some View {
        VStack(spacing: 16) {
            // Toggle to show/hide circles
            Toggle("Hiển thị vòng tròn", isOn: $showCircles)
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .padding(.horizontal, 16)
                .foregroundColor(.primary)
                .onChange(of: showCircles) { visible in
                   if visible {
                       for position in clickPositions {
                           showCircle(at: position.point, for: position.id)
                       }
                   } else {
                       circleWindowsLock.lock()
                       for window in circleWindows.values {
                           window.close()
                       }
                       circleWindows.removeAll()
                       circleWindowsLock.unlock()
                   }
                }
            
            // Hotkey Setting
            HStack {
                Text("Phím tắt:")
                    .foregroundColor(.primary)
                if isEditingHotkey {
                    TextField("Nhấn phím tắt...", text: $hotkey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 150)
                    Button(action: {
                        isEditingHotkey = false
                        saveHotkey()
                    }) {
                        Text("Lưu")
                            .padding(5)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(5)
                    }
                } else {
                    Text(hotkey)
                        .foregroundColor(.primary)
                    Button(action: {
                        isEditingHotkey = true
                    }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            
            // Add Click Position
            Button(action: addClickPosition) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                    Text("Thêm vị trí click")
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue).shadow(radius: 2))
                .foregroundColor(.white)
            }
            .buttonStyle(NeumorphicButtonStyle())
            
            // Global Repeat Count
            HStack {
                Text("Số lần lặp:")
                    .foregroundColor(.primary)
                TextField("", value: $globalRepeatCount, formatter: NumberFormatter())
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 80)
                Button(action: {
                    isInfiniteLoop.toggle()
                }) {
                    HStack {
                        Image(systemName: isInfiniteLoop ? "infinity.circle.fill" : "repeat.circle.fill")
                            .font(.system(size: 20))
                        Text(isInfiniteLoop ? "Vô hạn" : "Hữu hạn")
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(isInfiniteLoop ? Color.blue : Color.red).shadow(radius: 2))
                    .foregroundColor(.white)
                }
                .buttonStyle(NeumorphicButtonStyle(borderColor: isInfiniteLoop ? .white : .red))
            }
            .padding(.horizontal, 16)
            
            // List of Click Positions
            List {
                ForEach($clickPositions) { $position in
                    VStack(alignment: .leading) {
                        Text("Vị trí \(position.order): (\(position.point.x), \(position.point.y))")
                            .foregroundColor(.primary)
                        HStack {
                            Text("Delay (s):")
                                .foregroundColor(.primary)
                            TextField("Delay", value: $position.delay, formatter: NumberFormatter())
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 80)
                        }
                    }
                    .padding(8)
                    .background(Color.clear) // Loại bỏ nền của mỗi item
                }
                .onDelete { indices in
                    for index in indices {
                        hideCircle(for: clickPositions[index].id)
                    }
                    clickPositions.remove(atOffsets: indices)
                }
            }
            .listStyle(.plain) // Loại bỏ khung viền của List
            .frame(height: 150) // Giảm chiều cao của List
            .background(Color.clear) // Loại bỏ nền của List
            
            // Run Button
            Button(action: runClickPositions) {
                HStack {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20))
                    Text("Run")
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.green).shadow(radius: 2))
                .foregroundColor(.white)
            }
            .buttonStyle(NeumorphicButtonStyle())
            .disabled(clickPositions.isEmpty)
        }
    }
    
    // Add a new click position
    func addClickPosition() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let flipY = CGPoint(x: mouseLocation.x, y: screenFrame.height - mouseLocation.y)
        let newPosition = ClickPosition(point: flipY, delay: 1.0, order: clickPositions.count)
        clickPositions.append(newPosition)
        
        if showCircles {
            showCircle(at: flipY, for: newPosition.id)
        }
    }
    
   // Run click positions
    func runClickPositions() {
        isAutoClicking = true
        alertMessage = "Auto Click đã được kích hoạt."
        showAlert = true
        
        // Hide all circles
        circleWindowsLock.lock()
        for window in circleWindows.values {
            window.close()
        }
        circleWindows.removeAll()
         circleWindowsLock.unlock()
        
        DispatchQueue.global(qos: .userInitiated).async {
            var repeatCount = self.isInfiniteLoop ? Int.max : self.globalRepeatCount
            while self.isAutoClicking && repeatCount > 0 {
                for position in self.clickPositions {
                    DispatchQueue.main.async {
                        self.click(at: position.point)
                    }
                    Thread.sleep(forTimeInterval: position.delay)
                }
                repeatCount -= 1
            }
            
            DispatchQueue.main.async {
                self.isAutoClicking = false
                self.alertMessage = "Auto Click đã được tắt."
                self.showAlert = true
                // Show all circles again
                if self.showCircles {
                    for position in self.clickPositions {
                       self.showCircle(at: position.point, for: position.id)
                    }
                }
            }
        }
    }


    // Simulate a click at a specific position
    func click(at position: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let eventDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: position, mouseButton: .left)
        let eventUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: position, mouseButton: .left)
        eventDown?.post(tap: .cghidEventTap)
        eventUp?.post(tap: .cghidEventTap)
    }

   // Show circle at a specific position
    func showCircle(at position: CGPoint, for id: UUID) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let flipY = CGPoint(x: position.x - 25, y: screenFrame.height - (position.y + 25))
        
        DispatchQueue.main.async {
            guard let order = self.clickPositions.first(where: { $0.id == id })?.order else { return }
            let circleWindow = CircleWindow(position: flipY, order: order, id: id)
            circleWindow.onDrag = { newPosition in
                if let index = self.clickPositions.firstIndex(where: { $0.id == id }) {
                    self.clickPositions[index].point = newPosition
                }
            }
            circleWindow.orderFront(nil)
            
             self.circleWindowsLock.lock()
            self.circleWindows[id] = circleWindow
             self.circleWindowsLock.unlock()
        }
    }


    // Hide circle for a specific position
    func hideCircle(for id: UUID) {
        DispatchQueue.main.async {
            self.circleWindowsLock.lock()
           if let circleWindow = self.circleWindows[id] {
               circleWindow.close()
               self.circleWindows.removeValue(forKey: id)
           }
             self.circleWindowsLock.unlock()
        }
    }
    
    // Save hotkey
    func saveHotkey() {
        UserDefaults.standard.set(hotkey, forKey: "hotkey")
    }
}

// MARK: - Config Model
struct Config: Identifiable, Codable {
    var id = UUID()
    var name: String
    var actions: [Action]
    var createdAt: Date
    var duration: TimeInterval
}

// MARK: - Action Model
struct Action: Codable {
    var type: ActionType
    var point: CGPoint
    var timestamp: TimeInterval
}

enum ActionType: String, Codable {
    case click
    case swipe
}

// MARK: - Config Tab
struct ConfigTab: View {
    @Binding var configs: [Config]
    @Binding var showConfigPopup: Bool
    @Binding var isRecording: Bool
    @Binding var recordedActions: [Action]
    @Binding var recordingStartTime: Date
    @Binding var isAutoClicking: Bool
    @Binding var isPlayingConfig: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // Button to create new config
            Button(action: {
                showConfigPopup = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                    Text("Tạo Config")
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange).shadow(radius: 2))
                .foregroundColor(.white)
            }
            .buttonStyle(NeumorphicButtonStyle())
            
            // List of configs
            List {
                ForEach(configs.indices, id: \.self) { index in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(configs[index].name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Tạo lúc: \(configs[index].createdAt, formatter: dateFormatter)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Thời gian chạy: \(String(format: "%.2f", configs[index].duration)) giây")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Run Config Button
                        Button(action: {
                            if isPlayingConfig {
                                isPlayingConfig = false
                            } else {
                                isPlayingConfig = true
                                runConfig(config: configs[index])
                            }
                        }) {
                            Image(systemName: isPlayingConfig ? "stop.circle.fill" : "play.circle.fill")
                                .foregroundColor(isPlayingConfig ? .red : .green)
                                .font(.system(size: 20))
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Delete Config Button
                        Button(action: {
                            deleteConfig(at: index)
                        }) {
                            Image(systemName: "trash.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 20))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(8)
                    .background(Color.clear) // Loại bỏ nền của mỗi item
                }
            }
            .listStyle(.plain) // Loại bỏ khung viền của List
            .frame(height: 150) // Giảm chiều cao của List
            .background(Color.clear) // Loại bỏ nền của List
        }
    }
    
   // Run a specific config
    func runConfig(config: Config) {
        isAutoClicking = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            while self.isAutoClicking && self.isPlayingConfig {
                for action in config.actions {
                    DispatchQueue.main.async {
                        self.performAction(action: action)
                    }
                    Thread.sleep(forTimeInterval: action.timestamp)
                }
            }
            DispatchQueue.main.async {
                self.isAutoClicking = false
            }
        }
    }

    
    // Perform an action (click or swipe)
    func performAction(action: Action) {
        switch action.type {
        case .click:
            click(at: action.point)
        case .swipe:
            // Implement swipe logic if needed
            break
        }
    }
    
    // Simulate a click at a specific position
    func click(at position: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let eventDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: position, mouseButton: .left)
        let eventUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: position, mouseButton: .left)
        eventDown?.post(tap: .cghidEventTap)
        eventUp?.post(tap: .cghidEventTap)
    }
    
    // Delete a config at a specific index
    func deleteConfig(at index: Int) {
        configs.remove(at: index)
    }
    
    // Date formatter for displaying the creation time
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}

// MARK: - Config Popup View
struct ConfigPopupView: View {
    @Binding var isRecording: Bool
    @Binding var recordedActions: [Action]
    @Binding var recordingStartTime: Date
    @Binding var configs: [Config]
    @Binding var showConfigPopup: Bool
    
    @State private var configName: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Tạo Config")
                .font(.title)
                .foregroundColor(.primary)
            
            TextField("Tên Config", text: $configName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal, 16)
            
            HStack {
                Button(action: {
                    isRecording.toggle()
                    if isRecording {
                        recordingStartTime = Date()
                        recordedActions.removeAll()
                        startRecording()
                    } else {
                        stopRecording()
                    }
                }) {
                    HStack {
                        Image(systemName: isRecording ? "stop.circle.fill" : "record.circle.fill")
                            .font(.system(size: 20))
                        Text(isRecording ? "Dừng" : "Bắt đầu")
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(isRecording ? Color.red : Color.green).shadow(radius: 2))
                    .foregroundColor(.white)
                }
                .buttonStyle(NeumorphicButtonStyle(borderColor: isRecording ? .white : .clear))
                
                Button(action: {
                    showConfigPopup = false
                }) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                        Text("Đóng")
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray).shadow(radius: 2))
                    .foregroundColor(.white)
                }
                .buttonStyle(NeumorphicButtonStyle())
            }
        }
        .padding(16)
        .background(VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow))
        .cornerRadius(12)
        .frame(width: 300, height: 200)
        .onAppear {
            isRecording = false
            recordedActions.removeAll()
        }
    }
    
    // Start recording mouse clicks
    func startRecording() {
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            let mouseLocation = NSEvent.mouseLocation
            guard let screen = NSScreen.main else { return event }
            let screenFrame = screen.frame
             let flipY = CGPoint(x: mouseLocation.x, y: screenFrame.height - mouseLocation.y)
            let action = Action(type: .click, point: flipY, timestamp: Date().timeIntervalSince(recordingStartTime))
            recordedActions.append(action)
            return event
        }
    }
    
    // Stop recording
    func stopRecording() {
        let duration = Date().timeIntervalSince(recordingStartTime)
        let newConfig = Config(name: configName, actions: recordedActions, createdAt: Date(), duration: duration)
        configs.append(newConfig)
        configName = ""
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
