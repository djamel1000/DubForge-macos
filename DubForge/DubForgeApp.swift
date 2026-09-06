import SwiftUI

extension Notification.Name {
    static let dubForgeNewProject = Notification.Name("NewProject")
    static let dubForgeOpenProject = Notification.Name("OpenProject")
    static let dubForgeImportMedia = Notification.Name("ImportMedia")
    static let dubForgeExportProject = Notification.Name("ExportProject")
    static let dubForgeRunAnalysis = Notification.Name("RunAnalysis")
    static let dubForgeGenerateDubbing = Notification.Name("GenerateDubbing")
    static let dubForgeCancelJob = Notification.Name("CancelJob")
    static let dubForgeShowSettings = Notification.Name("ShowSettings")
}

// MARK: - Backend Process Manager
/// Launches and monitors the DubForge Python backend server.
/// The server runs as a child process of the macOS app and is killed when the app quits.
final class BackendLauncher: ObservableObject {
    static let shared = BackendLauncher()
    private var process: Process?
    private var shouldRun = false
    private var restartAttempt = 0
    private var restartWorkItem: DispatchWorkItem?
    @Published var isRunning = false
    @Published var launchLog: [String] = []

    private init() {}

    func start() {
        shouldRun = true
        restartWorkItem?.cancel()
        guard process == nil || !(process?.isRunning ?? false) else { return }

        // Locate Python inside the venv
        let projectRoot = findProjectRoot()
        guard let projectRoot else {
            log("⚠️ Could not locate DubForge project root.")
            return
        }

        let venvPython = projectRoot
            .appendingPathComponent("processing/venv/bin/python")

        guard FileManager.default.fileExists(atPath: venvPython.path) else {
            log("⚠️ venv Python not found at \(venvPython.path). Run: cd processing && python3 -m venv venv && venv/bin/pip install -r requirements.txt")
            return
        }

        let proc = Process()
        proc.executableURL = venvPython
        proc.arguments = ["-m", "processing.main"]
        proc.currentDirectoryURL = projectRoot

        var environment = ProcessInfo.processInfo.environment
        environment["MTL_DEBUG_LAYER"] = "0"
        environment["METAL_DEVICE_WRAPPER_TYPE"] = "0"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
        proc.environment = environment

        // Pipe stdout/stderr to our log
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.log(line.trimmingCharacters(in: .whitespacesAndNewlines))
                    if line.contains("Application startup complete") {
                        self?.isRunning = true
                        self?.restartAttempt = 0
                    }
                }
            }
        }
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.process === proc else { return }
                self.isRunning = false
                self.process = nil
                if self.shouldRun {
                    self.scheduleRestart()
                }
            }
        }

        do {
            try proc.run()
            process = proc
            log("🚀 DubForge backend starting on port 8765…")
        } catch {
            log("❌ Failed to launch backend: \(error.localizedDescription)")
            process = nil
            if shouldRun {
                scheduleRestart()
            }
        }
    }

    func stop() {
        shouldRun = false
        restartWorkItem?.cancel()
        restartWorkItem = nil
        process?.terminate()
        process = nil
        isRunning = false
    }

    func ensureRunning() {
        guard shouldRun else {
            start()
            return
        }
        guard process == nil || !(process?.isRunning ?? false) else { return }
        start()
    }

    private func scheduleRestart() {
        restartWorkItem?.cancel()
        restartAttempt += 1
        let delay = min(pow(2.0, Double(max(0, restartAttempt - 1))), 8.0)
        log("Backend stopped unexpectedly. Restarting in \(Int(delay)) second(s).")
        let workItem = DispatchWorkItem { [weak self] in
            self?.start()
        }
        restartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func log(_ msg: String) {
        launchLog.append(msg)
        if launchLog.count > 200 { launchLog.removeFirst() }
    }

    /// Finds the project root from common debug/dev launch locations.
    private func findProjectRoot() -> URL? {
        let candidates = [
            ProcessInfo.processInfo.environment["DUBFORGE_PROJECT_ROOT"].map(URL.init(fileURLWithPath:)),
            Bundle.main.resourceURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent(),
            Bundle.main.bundleURL.deletingLastPathComponent()
        ].compactMap { $0 }

        for root in candidates {
            if let found = findProjectRoot(startingAt: root) {
                return found
            }
        }
        return nil
    }

    private func findProjectRoot(startingAt startURL: URL) -> URL? {
        var candidate = startURL.standardizedFileURL
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("processing/main.py").path) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                break
            }
            candidate = parent
        }
        return nil
    }
}

// MARK: - App Entry Point
@main
struct DubForgeApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var backend = BackendLauncher.shared

    var body: some Scene {
        WindowGroup("DubForge") {
            ContentView()
                .frame(minWidth: 1280, minHeight: 800)
                .onAppear {
                    BackendLauncher.shared.start()
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandMenu("Project") {
                Button("New Project...") {
                    NotificationCenter.default.post(name: .dubForgeNewProject, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open Project...") {
                    NotificationCenter.default.post(name: .dubForgeOpenProject, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Import Media...") {
                    NotificationCenter.default.post(name: .dubForgeImportMedia, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Export...") {
                    NotificationCenter.default.post(name: .dubForgeExportProject, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
            }

            CommandMenu("Dubbing") {
                Button("Run Analysis") {
                    NotificationCenter.default.post(name: .dubForgeRunAnalysis, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Generate Dubbing") {
                    NotificationCenter.default.post(name: .dubForgeGenerateDubbing, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Cancel Job") {
                    NotificationCenter.default.post(name: .dubForgeCancelJob, object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)

                Divider()
                Button("Restart Backend Server") {
                    BackendLauncher.shared.stop()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        BackendLauncher.shared.start()
                    }
                }
            }

            CommandMenu("View") {
                Button("Show Log Console") {
                    openWindow(id: "log-console")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Show Settings") {
                    NotificationCenter.default.post(name: .dubForgeShowSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window("Log Console", id: "log-console") {
            LogConsoleView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 800, height: 500)

        Settings {
            SettingsView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 700, height: 500)
    }
}

// MARK: - Supporting Views (Minimal implementations for compilation)

struct LogConsoleView: View {
    var body: some View {
        VStack {
            Text("Log Console")
                .font(.headline)
                .padding()
            Spacer()
        }
    }
}

struct SettingsView: View {
    var body: some View {
        VStack {
            Text("Settings")
                .font(.headline)
                .padding()
            Spacer()
        }
    }
}
