import SwiftUI
import Combine
import UniformTypeIdentifiers
import AVKit
import Security

private enum KeychainStore {
    private static let service = "com.dubforge.credentials"
    private static let queue = DispatchQueue(label: "com.dubforge.keychain", qos: .utility)

    static func string(for account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    static func set(_ value: String, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    static func loadCredentials(
        completion: @escaping (_ gemini: String, _ googleTTS: String, _ elevenLabs: String, _ huggingFace: String) -> Void
    ) {
        queue.async {
            let credentials = (
                string(for: "geminiApiKey"),
                string(for: "googleTtsApiKey"),
                string(for: "elevenlabsApiKey"),
                string(for: "huggingFaceToken")
            )
            DispatchQueue.main.async {
                completion(credentials.0, credentials.1, credentials.2, credentials.3)
            }
        }
    }

    static func saveCredentials(
        gemini: String,
        googleTTS: String,
        elevenLabs: String,
        huggingFace: String
    ) {
        queue.async {
            set(gemini, for: "geminiApiKey")
            set(googleTTS, for: "googleTtsApiKey")
            set(elevenLabs, for: "elevenlabsApiKey")
            set(huggingFace, for: "huggingFaceToken")
        }
    }
}

// MARK: - Hex Color Helper
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
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    // Custom theme variables from dubforge_10_10_ui_dsl.md
    static let darkBackground = Color(hex: "#13131B")
    static let surfaceLowest = Color(hex: "#0D0D15")
    static let surfaceLow = Color(hex: "#1B1B23")
    static let surfaceMid = Color(hex: "#1F1F27")
    static let surfaceHigh = Color(hex: "#292932")
    static let surfaceHighest = Color(hex: "#34343D")
    static let textPrimary = Color(hex: "#E4E1ED")
    static let textSecondary = Color(hex: "#C7C4D7")
    static let outlineBorder = Color(hex: "#464554")
    static let brandPrimary = Color(hex: "#C0C1FF")
    static let brandPrimaryStrong = Color(hex: "#8083FF")
    static let warningColor = Color(hex: "#FFB783")
    static let errorColor = Color(hex: "#FFB4AB")
    static let successColor = Color(hex: "#9BE7B1")
}

// MARK: - Navigation Enums
enum SidebarItem: String, CaseIterable, Identifiable {
    case importMedia = "Import"
    case analysis = "Analysis"
    case transcript = "Transcript"
    case speakers = "Speakers"
    case voices = "Voices"
    case director = "AI Director"
    case dubbing = "Dubbing"
    case mixing = "Mixing"
    case export = "Export"
    case settings = "Settings"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .importMedia: return "square.and.arrow.down"
        case .analysis: return "waveform.path.ecg"
        case .transcript: return "text.alignleft"
        case .speakers: return "person.2"
        case .voices: return "waveform"
        case .director: return "brain.head.profile"
        case .dubbing: return "play.circle"
        case .mixing: return "slider.horizontal.3"
        case .export: return "square.and.arrow.up"
        case .settings: return "gear"
        }
    }
}

// MARK: - Swift Data Models
struct AnalysisStatus: Codable {
    var extractAudio: String
    var transcription: String
    var diarization: String
    var integration: String
    var failedStage: String?
    var message: String?

    static var starting: AnalysisStatus {
        AnalysisStatus(
            extractAudio: "running",
            transcription: "pending",
            diarization: "pending",
            integration: "pending",
            failedStage: nil,
            message: "Extracting video audio streams..."
        )
    }
}

struct Project: Codable, Identifiable {
    var id: String { projectId }
    let projectId: String
    var name: String
    var sourceLanguage: String
    var targetLanguage: String
    var inputVideoPath: String
    var subtitlePath: String?
    var pipelineStage: String // Import, Analysis, Transcript, Speakers, Voices, Director, Dubbing, Mixing, Export
    var analysisStatus: AnalysisStatus? = nil
    var speakers: [Speaker]
    var segments: [Segment]
    var mix: MixSettings
    var export: ExportSettings
}

struct Segment: Codable, Identifiable, Hashable {
    var id: Int
    var start: Double
    var end: Double
    var duration: Double
    var speakerId: String
    var sourceText: String
    var dubText: String
    var literalTranslation: String
    var emotion: String
    var emotionIntensity: Double
    var performanceInstruction: String
    var qwenInstruction: String
    var voiceProfileId: String
    var generatedAudioPath: String?
    var generatedDuration: Double?
    var retryCount: Int
    var fitStatus: String // pending, fits, too_long, too_short, needs_review, failed, approved
    var approved: Bool
    var locked: Bool
    var warnings: [String]
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Segment, rhs: Segment) -> Bool {
        return lhs.id == rhs.id
    }
}

struct Speaker: Codable, Identifiable {
    var id: String { speakerId }
    let speakerId: String
    var displayName: String
    var characterName: String?
    var genderStyle: String?
    var ageStyle: String?
    var personalityStyle: String?
    var color: String
    var voiceProfileId: String?
    var segmentCount: Int
    var totalSpeakingTime: Double
    var confidence: Double
    var voiceType: String? = nil
    var referenceAudioPath: String? = nil
    var referenceText: String? = nil
    var referenceSegmentId: Int? = nil
    var cloneReady: Bool? = nil
    var cloneError: String? = nil
}

struct VoiceProfile: Codable, Identifiable {
    var id: String { voiceProfileId }
    let voiceProfileId: String
    var speakerId: String?
    var voiceType: String // preset_voice, designed_voice, cloned_voice, imported_voice
    var description: String
    var qwenVoiceReference: String?
    var referenceAudioPath: String?
    var consentConfirmed: Bool
    var generatedSegmentCount: Int
}

struct VoiceSelectionOption: Identifiable {
    let id: String
    let label: String
}

struct RemoteMediaInfo: Codable {
    let title: String
    let creator: String
    let duration: Double
    let thumbnail: String?
    let platform: String
    let resolution: String
    let fileSize: Int64?
    let `extension`: String
    let subtitles: [String]
    let mediaId: String
}

private struct DubForgeAPIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct MixSettings: Codable {
    var voiceRemovalStrength: String // Light, Medium, Strong, Manual
    var vocalStemGainDb: Double
    var backgroundGainDb: Double
    var dubbedVoiceGainDb: Double
    var duckingEnabled: Bool
    var duckingAmountDb: Double
    var duckingAttackMs: Double
    var duckingReleaseMs: Double
    var limiterEnabled: Bool
    var targetLoudness: String
    var backgroundDamageRisk: String? // low, medium, high
    var backgroundPath: String?
    var vocalResidualPath: String?
    var dubbedVoiceCanvasPath: String?
    var finalMixPath: String?
}

struct ExportSettings: Codable {
    var videoFormat: String
    var audioFormat: String
    var includeProjectJson: Bool
    var includeStems: Bool
    var includeSubtitles: Bool
    var burnInSubtitles: Bool
}

// MARK: - Networking Client (API)
class DubForgeAPIClient {
    static let shared = DubForgeAPIClient()
    private let baseURL = "http://127.0.0.1:8765"

    private func validatedData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let detail = json?["detail"] as? String
            throw DubForgeAPIError(message: detail ?? "The local DubForge service rejected the request.")
        }
        return data
    }

    func inspectMediaURL(_ sourceURL: String) async throws -> RemoteMediaInfo {
        let url = URL(string: "\(baseURL)/media/url/inspect")!
        var request = URLRequest(url: url, timeoutInterval: 130)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["source_url": sourceURL])
        let data = try await validatedData(for: request)
        return try JSONDecoder().decode(RemoteMediaInfo.self, from: data)
    }

    func startMediaURLDownload(_ sourceURL: String) async throws -> String {
        let url = URL(string: "\(baseURL)/media/url/download")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["source_url": sourceURL])
        let data = try await validatedData(for: request)
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let jobId = response?["job_id"] as? String, !jobId.isEmpty else {
            throw DubForgeAPIError(message: "The downloader did not create a download task.")
        }
        return jobId
    }
    
    func createProject(name: String, source: String, target: String, video: String, subtitle: String?) async throws -> Project {
        let url = URL(string: "\(baseURL)/projects/create")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any?] = [
            "name": name,
            "sourceLanguage": source,
            "targetLanguage": target,
            "inputVideoPath": video,
            "subtitlePath": subtitle
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(Project.self, from: data)
    }
    
    func getProject(id: String) async throws -> Project {
        let url = URL(string: "\(baseURL)/projects/\(id)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(Project.self, from: data)
    }

    func saveProject(_ project: Project) async throws -> Project {
        let url = URL(string: "\(baseURL)/projects/\(project.projectId)/save")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(project)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let projectDict = json?["project"] else { return project }
        let projectData = try JSONSerialization.data(withJSONObject: projectDict)
        return try JSONDecoder().decode(Project.self, from: projectData)
    }
    
    func updateSettings(settings: [String: Any]) async throws {
        let url = URL(string: "\(baseURL)/settings/update")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: settings)
        _ = try await URLSession.shared.data(for: request)
    }
    
    // Fetch available Gemini + Gemma models DIRECTLY from Google API (no backend needed)
    func fetchGeminiModels(apiKey: String) async throws -> (models: [[String: Any]], source: String) {
        guard !apiKey.isEmpty else {
            return ([], "offline")
        }
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "pageSize", value: "200")
        ]
        let url = components.url!
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("DubForge/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return ([], "offline")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let rawModels = json?["models"] as? [[String: Any]] ?? []
        let filtered = rawModels.compactMap { m -> [String: Any]? in
            guard let name = m["name"] as? String,
                  let methods = m["supportedGenerationMethods"] as? [String],
                  methods.contains("generateContent") else { return nil }
            let modelId = name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
            let base = modelId.lowercased()
            guard base.hasPrefix("gemini") || base.hasPrefix("gemma") else { return nil }
            let display = (m["displayName"] as? String) ?? modelId
            let provider = base.hasPrefix("gemma") ? "gemma" : "gemini"
            return ["id": modelId, "display": display, "provider": provider]
        }
        return (filtered, "live_api")
    }
    
    // Fetch ElevenLabs voices and models directly from their API
    func fetchElevenLabsData(apiKey: String) async throws -> (voices: [(id: String, name: String, category: String)], models: [(id: String, name: String)]) {
        let headers = ["xi-api-key": apiKey]
        // Fetch voices
        var voiceReq = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/voices")!, timeoutInterval: 10)
        for (k, v) in headers { voiceReq.setValue(v, forHTTPHeaderField: k) }
        let (vData, _) = try await URLSession.shared.data(for: voiceReq)
        let vJson = try JSONSerialization.jsonObject(with: vData) as? [String: Any]
        let rawVoices = vJson?["voices"] as? [[String: Any]] ?? []
        let voices: [(id: String, name: String, category: String)] = rawVoices.compactMap { v in
            guard let id = v["voice_id"] as? String, let name = v["name"] as? String else { return nil }
            return (id: id, name: name, category: v["category"] as? String ?? "premade")
        }
        // Fetch models
        var modelReq = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/models")!, timeoutInterval: 10)
        for (k, v) in headers { modelReq.setValue(v, forHTTPHeaderField: k) }
        let (mData, _) = try await URLSession.shared.data(for: modelReq)
        let rawModels = (try? JSONSerialization.jsonObject(with: mData)) as? [[String: Any]] ?? []
        let models: [(id: String, name: String)] = rawModels.compactMap { m in
            guard let id = m["model_id"] as? String, let name = m["name"] as? String else { return nil }
            return (id: id, name: name)
        }
        return (voices, models)
    }
    
    // Fetch Google Cloud TTS voices directly
    func fetchGoogleVoices(apiKey: String, languageCode: String) async throws -> [(name: String, gender: String, langCodes: [String])] {
        var urlStr = "https://texttospeech.googleapis.com/v1/voices?key=\(apiKey)"
        if !languageCode.isEmpty { urlStr += "&languageCode=\(languageCode)" }
        let (data, _) = try await URLSession.shared.data(from: URL(string: urlStr)!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let rawVoices = json?["voices"] as? [[String: Any]] ?? []
        return rawVoices.compactMap { v in
            guard let name = v["name"] as? String else { return nil }
            let gender = v["ssmlGender"] as? String ?? ""
            let codes = v["languageCodes"] as? [String] ?? []
            return (name: name, gender: gender, langCodes: codes)
        }
    }
    
    func startAnalysis(projectId: String) async throws -> String {
        let url = URL(string: "\(baseURL)/media/extract-audio")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["project_id": projectId])
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let res = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return res?["job_id"] as? String ?? ""
    }
    
    func startAdaptation(projectId: String) async throws -> String {
        let url = URL(string: "\(baseURL)/gemini/adapt")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["project_id": projectId])
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let res = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return res?["job_id"] as? String ?? ""
    }
    
    func startTTSGeneration(projectId: String) async throws -> String {
        let url = URL(string: "\(baseURL)/tts/generate-all")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["project_id": projectId])
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let res = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return res?["job_id"] as? String ?? ""
    }

    func generateSegment(_ segment: Segment, projectId: String) async throws -> (duration: Double?, audioPath: String?, status: String, warnings: [String], dubText: String?, retryCount: Int) {
        let url = URL(string: "\(baseURL)/tts/generate-segment")!
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encodedSegment = try JSONSerialization.jsonObject(with: JSONEncoder().encode(segment))
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "project_id": projectId,
            "segment": encodedSegment
        ])

        let data = try await validatedData(for: request)
        let res = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let status = res?["status"] as? String else {
            throw DubForgeAPIError(message: "The TTS service returned an invalid segment result.")
        }
        return (
            duration: res?["generated_duration"] as? Double,
            audioPath: res?["generated_audio_path"] as? String,
            status: status,
            warnings: res?["warnings"] as? [String] ?? [],
            dubText: res?["dub_text"] as? String,
            retryCount: res?["retry_count"] as? Int ?? 0
        )
    }
    
    func startSeparation(projectId: String) async throws -> String {
        let url = URL(string: "\(baseURL)/audio/separate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["project_id": projectId])
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let res = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return res?["job_id"] as? String ?? ""
    }
    
    func startMixing(projectId: String) async throws -> String {
        let url = URL(string: "\(baseURL)/audio/mix")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["project_id": projectId])
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let res = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return res?["job_id"] as? String ?? ""
    }
    
    func startExport(projectId: String) async throws -> String {
        let url = URL(string: "\(baseURL)/export/video")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["project_id": projectId])
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let res = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return res?["job_id"] as? String ?? ""
    }
    
    func checkJobStatus(id: String) async throws -> (status: String, progress: Double, message: String, result: [String: Any]?) {
        let url = URL(string: "\(baseURL)/jobs/\(id)/status")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let res = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        let status = res?["status"] as? String ?? "failed"
        let progress = res?["progress"] as? Double ?? 0.0
        let message = res?["message"] as? String ?? ""
        let result = res?["result"] as? [String: Any]
        
        return (status, progress, message, result)
    }

    func cancelJob(id: String) async throws {
        let url = URL(string: "\(baseURL)/jobs/\(id)/cancel")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: request)
    }
}

// MARK: - View Model
class ProjectViewModel: ObservableObject {
    @Published var activeProject: Project?
    @Published var sidebarSelection: SidebarItem = .importMedia
    
    // Selection Details
    @Published var selectedSegment: Segment?
    @Published var selectedSpeaker: Speaker?
    @Published var selectedVoice: VoiceProfile?
    
    // Status Bar & Async Jobs
    @Published var activeJobId: String?
    @Published var activeJobProgress: Double = 0.0
    @Published var activeJobStatus: String = "Idle"
    @Published var activeJobMessage: String = "System Ready"
    @Published var activeJobKind: String?
    @Published var isServerConnected = false
    
    // Audio Player states
    @Published var previewMode: String = "Original"
    @Published var isPlaying = false
    @Published var playhead: Double = 0.0
    
    // Logs Consoles
    @Published var logs: [String] = ["System diagnostic initialized."]
    
    // Configuration Bindings
    @Published var geminiApiKey: String = ""
    @Published var geminiModel: String = "gemini-1.5-pro"
    @Published var qwenLocalPath: String = ""
    @Published var qwenModel: String = "Qwen3-TTS-12Hz-1.7B-Base-8bit"
    @Published var whisperModel: String = "medium"
    @Published var whisperComputeType: String = "int8"
    @Published var demucsPath: String = "/Users/Apple/projects/DubForge_macos_2026-05-30T22-43-12/processing/ml_venv/bin/demucs"
    @Published var mlPythonPath: String = "/Users/Apple/projects/DubForge_macos_2026-05-30T22-43-12/processing/ml_venv/bin/python"
    @Published var diarizationModel: String = "pyannote/speaker-diarization-community-1"
    @Published var diarizationDevice: String = "cpu"
    @Published var huggingFaceToken: String = ""
    
    // TTS Provider
    @Published var ttsProvider: String = "qwen"  // "qwen" | "google" | "elevenlabs"
    // Google TTS
    @Published var googleTtsApiKey: String = ""
    @Published var googleTtsLanguageCode: String = "en-US"
    @Published var googleTtsVoiceName: String = ""
    @Published var googleTtsPitch: Double = 0.0
    @Published var googleTtsVoices: [(name: String, gender: String, langCodes: [String])] = []
    @Published var googleTtsVoicesLoading: Bool = false
    // ElevenLabs
    @Published var elevenlabsApiKey: String = ""
    @Published var elevenlabsVoiceId: String = ""
    @Published var elevenlabsModelId: String = "eleven_multilingual_v2"
    @Published var elevenlabsStability: Double = 0.5
    @Published var elevenlabsSimilarityBoost: Double = 0.75
    @Published var elevenlabsStyle: Double = 0.0
    @Published var elevenlabsVoices: [(id: String, name: String, category: String)] = []
    @Published var elevenlabsModels: [(id: String, name: String)] = [
        (id: "eleven_multilingual_v2",  name: "Multilingual v2 (best quality)"),
        (id: "eleven_flash_v2_5",       name: "Flash v2.5 (fast, multilingual)"),
        (id: "eleven_flash_v2",         name: "Flash v2"),
        (id: "eleven_turbo_v2_5",       name: "Turbo v2.5 (low latency)"),
        (id: "eleven_turbo_v2",         name: "Turbo v2"),
        (id: "eleven_monolingual_v1",   name: "English v1"),
    ]
    @Published var elevenlabsVoicesLoading: Bool = false
    
    func loadElevenLabsVoices() {
        guard !elevenlabsApiKey.isEmpty else { return }
        elevenlabsVoicesLoading = true
        let key = elevenlabsApiKey
        Task {
            do {
                let (voices, models) = try await DubForgeAPIClient.shared.fetchElevenLabsData(apiKey: key)
                DispatchQueue.main.async {
                    self.elevenlabsVoices = voices
                    if !models.isEmpty { self.elevenlabsModels = models }
                    self.elevenlabsVoicesLoading = false
                    if self.elevenlabsVoiceId.isEmpty, let first = voices.first {
                        self.elevenlabsVoiceId = first.id
                    }
                    self.log("Loaded \(voices.count) ElevenLabs voices.")
                }
            } catch {
                DispatchQueue.main.async {
                    self.elevenlabsVoicesLoading = false
                    self.log("ElevenLabs voice load failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func loadGoogleVoices() {
        guard !googleTtsApiKey.isEmpty else { return }
        googleTtsVoicesLoading = true
        let key = googleTtsApiKey
        let lang = googleTtsLanguageCode
        Task {
            do {
                let voices = try await DubForgeAPIClient.shared.fetchGoogleVoices(apiKey: key, languageCode: lang)
                DispatchQueue.main.async {
                    self.googleTtsVoices = voices
                    self.googleTtsVoicesLoading = false
                    self.log("Loaded \(voices.count) Google TTS voices.")
                }
            } catch {
                DispatchQueue.main.async {
                    self.googleTtsVoicesLoading = false
                    self.log("Google TTS voice load failed: \(error.localizedDescription)")
                }
            }
        }
    }

    var ttsProviderDisplayName: String {
        switch ttsProvider {
        case "google": return "Google Cloud TTS"
        case "elevenlabs": return "ElevenLabs"
        default: return "Qwen3-TTS Local"
        }
    }

    var ttsProviderDetail: String {
        switch ttsProvider {
        case "google":
            let voice = googleTtsVoiceName.isEmpty ? "No voice selected" : googleTtsVoiceName
            return "\(googleTtsLanguageCode) • \(voice)"
        case "elevenlabs":
            let voice = elevenlabsVoiceId.isEmpty ? "No voice selected" : elevenlabsVoiceId
            return "\(elevenlabsModelId) • \(voice)"
        default:
            return qwenLocalPath.isEmpty ? "\(qwenModel) • on-device" : "\(qwenModel) • local weights"
        }
    }

    var voiceProfileOptions: [VoiceSelectionOption] {
        switch ttsProvider {
        case "google":
            let loaded = googleTtsVoices.map { voice in
                VoiceSelectionOption(id: voice.name, label: "\(voice.name) (\(voice.gender))")
            }
            if loaded.isEmpty, !googleTtsVoiceName.isEmpty {
                return [VoiceSelectionOption(id: googleTtsVoiceName, label: googleTtsVoiceName)]
            }
            return loaded
        case "elevenlabs":
            let loaded = elevenlabsVoices.map { voice in
                VoiceSelectionOption(id: voice.id, label: "\(voice.name) (\(voice.category))")
            }
            if loaded.isEmpty, !elevenlabsVoiceId.isEmpty {
                return [VoiceSelectionOption(id: elevenlabsVoiceId, label: elevenlabsVoiceId)]
            }
            return loaded
        default:
            return activeProject?.speakers.compactMap { speaker in
                guard let voiceProfileId = speaker.voiceProfileId, !voiceProfileId.isEmpty else {
                    return nil
                }
                return VoiceSelectionOption(id: voiceProfileId, label: "\(speaker.displayName) • \(voiceProfileId)")
            } ?? []
        }
    }

    func effectiveVoiceLabel(for segment: Segment) -> String {
        switch ttsProvider {
        case "google":
            return googleTtsVoiceName.isEmpty ? "Google default voice" : googleTtsVoiceName
        case "elevenlabs":
            if let voice = elevenlabsVoices.first(where: { $0.id == elevenlabsVoiceId }) {
                return voice.name
            }
            return elevenlabsVoiceId.isEmpty ? "ElevenLabs default voice" : elevenlabsVoiceId
        default:
            return segment.voiceProfileId.isEmpty ? "Qwen default voice" : segment.voiceProfileId
        }
    }

    private func currentStudioSettingsPayload() -> [String: Any] {
        [
            "geminiApiKey": geminiApiKey,
            "geminiModel": geminiModel,
            "whisperModel": whisperModel,
            "whisperComputeType": whisperComputeType,
            "demucsPath": demucsPath,
            "mlPythonPath": mlPythonPath,
            "diarizationModel": diarizationModel,
            "diarizationDevice": diarizationDevice,
            "huggingFaceToken": huggingFaceToken,
            "ttsProvider": ttsProvider,
            "qwenLocalPath": qwenLocalPath,
            "qwenModel": qwenModel,
            "googleTtsApiKey": googleTtsApiKey,
            "googleTtsLanguageCode": googleTtsLanguageCode,
            "googleTtsVoiceName": googleTtsVoiceName,
            "googleTtsPitch": googleTtsPitch,
            "elevenlabsApiKey": elevenlabsApiKey,
            "elevenlabsVoiceId": elevenlabsVoiceId,
            "elevenlabsModelId": elevenlabsModelId,
            "elevenlabsStability": elevenlabsStability,
            "elevenlabsSimilarityBoost": elevenlabsSimilarityBoost,
            "elevenlabsStyle": elevenlabsStyle
        ]
    }

    func syncStudioSettings() async throws {
        persistStudioSettings()
        try await DubForgeAPIClient.shared.updateSettings(settings: currentStudioSettingsPayload())
    }

    func persistStudioSettings() {
        KeychainStore.saveCredentials(
            gemini: geminiApiKey,
            googleTTS: googleTtsApiKey,
            elevenLabs: elevenlabsApiKey,
            huggingFace: huggingFaceToken
        )

        let defaults = UserDefaults.standard
        defaults.set(geminiModel, forKey: "studio.geminiModel")
        defaults.set(qwenLocalPath, forKey: "studio.qwenLocalPath")
        defaults.set(qwenModel, forKey: "studio.qwenModel")
        defaults.set(whisperModel, forKey: "studio.whisperModel")
        defaults.set(whisperComputeType, forKey: "studio.whisperComputeType")
        defaults.set(demucsPath, forKey: "studio.demucsPath")
        defaults.set(mlPythonPath, forKey: "studio.mlPythonPath")
        defaults.set(diarizationModel, forKey: "studio.diarizationModel")
        defaults.set(diarizationDevice, forKey: "studio.diarizationDevice")
        defaults.set(ttsProvider, forKey: "studio.ttsProvider")
        defaults.set(googleTtsLanguageCode, forKey: "studio.googleTtsLanguageCode")
        defaults.set(googleTtsVoiceName, forKey: "studio.googleTtsVoiceName")
        defaults.set(googleTtsPitch, forKey: "studio.googleTtsPitch")
        defaults.set(elevenlabsVoiceId, forKey: "studio.elevenlabsVoiceId")
        defaults.set(elevenlabsModelId, forKey: "studio.elevenlabsModelId")
    }

    func syncTTSSettings() async throws {
        try await syncStudioSettings()
    }
    
    // Gemini model picker state — pre-seeded with ALL current models so the
    // dropdown is always visible. When an API key is present, live data replaces this.
    @Published var geminiModels: [(id: String, display: String, provider: String)] = [
        // ── Gemini 2.5 ──
        (id: "gemini-2.5-pro",                   display: "Gemini 2.5 Pro",                  provider: "gemini"),
        (id: "gemini-2.5-pro-preview-06-05",      display: "Gemini 2.5 Pro Preview (Jun)",    provider: "gemini"),
        (id: "gemini-2.5-pro-preview-05-06",      display: "Gemini 2.5 Pro Preview (May)",    provider: "gemini"),
        (id: "gemini-2.5-flash",                  display: "Gemini 2.5 Flash",                provider: "gemini"),
        (id: "gemini-2.5-flash-preview-05-20",    display: "Gemini 2.5 Flash Preview (May)",  provider: "gemini"),
        (id: "gemini-2.5-flash-lite-preview-06-17",display: "Gemini 2.5 Flash Lite Preview", provider: "gemini"),
        // ── Gemini 2.0 ──
        (id: "gemini-2.0-flash",                  display: "Gemini 2.0 Flash",                provider: "gemini"),
        (id: "gemini-2.0-flash-lite",             display: "Gemini 2.0 Flash Lite",           provider: "gemini"),
        // ── Gemini 1.5 ──
        (id: "gemini-1.5-pro",                    display: "Gemini 1.5 Pro",                  provider: "gemini"),
        (id: "gemini-1.5-flash",                  display: "Gemini 1.5 Flash",                provider: "gemini"),
        (id: "gemini-1.5-flash-8b",               display: "Gemini 1.5 Flash-8B",             provider: "gemini"),
        // ── Gemma 4 ──
        (id: "gemma-4-27b-it",                    display: "Gemma 4 27B Instruct",            provider: "gemma"),
        (id: "gemma-4-9b-it",                     display: "Gemma 4 9B Instruct",             provider: "gemma"),
        // ── Gemma 3 ──
        (id: "gemma-3-27b-it",                    display: "Gemma 3 27B Instruct",            provider: "gemma"),
        (id: "gemma-3-12b-it",                    display: "Gemma 3 12B Instruct",            provider: "gemma"),
        (id: "gemma-3-4b-it",                     display: "Gemma 3 4B Instruct",             provider: "gemma"),
        (id: "gemma-3-1b-it",                     display: "Gemma 3 1B Instruct",             provider: "gemma"),
        // ── Gemma 3n ──
        (id: "gemma-3n-e4b-it",                   display: "Gemma 3n E4B Instruct",           provider: "gemma"),
        (id: "gemma-3n-e2b-it",                   display: "Gemma 3n E2B Instruct",           provider: "gemma"),
    ]
    @Published var geminiModelsLoading: Bool = false
    @Published var geminiModelsSource: String = "offline"  // "live_api" | "offline"
    
    func loadGeminiModels() {
        geminiModelsLoading = true
        let key = geminiApiKey
        Task {
            do {
                let (raw, source) = try await DubForgeAPIClient.shared.fetchGeminiModels(apiKey: key)
                let parsed = raw.compactMap { m -> (id: String, display: String, provider: String)? in
                    guard let id = m["id"] as? String,
                          let display = m["display"] as? String,
                          let provider = m["provider"] as? String else { return nil }
                    return (id: id, display: display, provider: provider)
                }
                DispatchQueue.main.async {
                    if !parsed.isEmpty {
                        // Sort: gemini first (newest first), then gemma (newest first)
                        let sorted = parsed.sorted {
                            if $0.provider != $1.provider {
                                return $0.provider == "gemini"
                            }
                            return $0.id > $1.id
                        }
                        self.geminiModels = sorted
                        self.geminiModelsSource = source
                        // Auto-select first model if current selection not in live list
                        if !sorted.contains(where: { $0.id == self.geminiModel }) {
                            self.geminiModel = sorted.first?.id ?? self.geminiModel
                        }
                        self.log("\(sorted.count) models loaded from Google API")
                    } else {
                        self.geminiModelsSource = "offline"
                        self.log("Using offline model list (no API key or network unavailable)")
                    }
                    self.geminiModelsLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.geminiModelsLoading = false
                    self.geminiModelsSource = "offline"
                    self.log("Model fetch failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var pollingTimer: Timer?
    private var jobPollingFailureCount = 0
    
    init() {
        let defaults = UserDefaults.standard
        geminiModel = defaults.string(forKey: "studio.geminiModel") ?? geminiModel
        qwenLocalPath = defaults.string(forKey: "studio.qwenLocalPath") ?? qwenLocalPath
        qwenModel = defaults.string(forKey: "studio.qwenModel") ?? qwenModel
        whisperModel = defaults.string(forKey: "studio.whisperModel") ?? whisperModel
        whisperComputeType = defaults.string(forKey: "studio.whisperComputeType") ?? whisperComputeType
        demucsPath = defaults.string(forKey: "studio.demucsPath") ?? demucsPath
        mlPythonPath = defaults.string(forKey: "studio.mlPythonPath") ?? mlPythonPath
        diarizationModel = defaults.string(forKey: "studio.diarizationModel") ?? diarizationModel
        diarizationDevice = defaults.string(forKey: "studio.diarizationDevice") ?? diarizationDevice
        ttsProvider = defaults.string(forKey: "studio.ttsProvider") ?? ttsProvider
        googleTtsLanguageCode = defaults.string(forKey: "studio.googleTtsLanguageCode") ?? googleTtsLanguageCode
        googleTtsVoiceName = defaults.string(forKey: "studio.googleTtsVoiceName") ?? googleTtsVoiceName
        googleTtsPitch = defaults.object(forKey: "studio.googleTtsPitch") as? Double ?? googleTtsPitch
        elevenlabsVoiceId = defaults.string(forKey: "studio.elevenlabsVoiceId") ?? elevenlabsVoiceId
        elevenlabsModelId = defaults.string(forKey: "studio.elevenlabsModelId") ?? elevenlabsModelId

        // Automatically check backend status periodically
        Timer.publish(every: 4.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pingServer()
            }
            .store(in: &cancellables)

        BackendLauncher.shared.ensureRunning()
        pingServer()

        // Keychain access can wait for a locked keychain or an authorization UI.
        // Load credentials after the first frame so it cannot block app startup.
        KeychainStore.loadCredentials { [weak self] gemini, googleTTS, elevenLabs, huggingFace in
            guard let self else { return }
            self.geminiApiKey = gemini
            self.googleTtsApiKey = googleTTS
            self.elevenlabsApiKey = elevenLabs
            self.huggingFaceToken = huggingFace
            self.loadGeminiModels()
        }
    }
    
    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: Date())
        logs.append("[\(timeStr)] \(message)")
    }

    func persistActiveProject() {
        guard let project = activeProject else { return }
        Task {
            do {
                let saved = try await DubForgeAPIClient.shared.saveProject(project)
                DispatchQueue.main.async {
                    self.activeProject = saved
                    if let selected = self.selectedSegment,
                       let refreshed = saved.segments.first(where: { $0.id == selected.id }) {
                        self.selectedSegment = refreshed
                    }
                    self.log("Project changes saved.")
                }
            } catch {
                DispatchQueue.main.async {
                    self.log("Project save failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func updateSegment(_ segment: Segment, persist: Bool = true) {
        guard var project = activeProject,
              let index = project.segments.firstIndex(where: { $0.id == segment.id }) else {
            selectedSegment = segment
            return
        }

        project.segments[index] = segment
        activeProject = project
        selectedSegment = segment

        if persist {
            persistActiveProject()
        }
    }

    func setSelectedSegment(_ segment: Segment?) {
        selectedSegment = segment
        selectedSpeaker = nil
        selectedVoice = nil
        if let segment {
            playhead = segment.start
        }
    }

    func previewSegment(_ segment: Segment) {
        setSelectedSegment(segment)
        playhead = segment.start
        isPlaying = true
        activeJobMessage = "Previewing segment \(segment.id)"
    }

    func toggleLock(_ segment: Segment) {
        var updated = segment
        updated.locked.toggle()
        updateSegment(updated)
        log(updated.locked ? "Locked segment \(segment.id)." : "Unlocked segment \(segment.id).")
    }

    func approveSegment(_ segment: Segment) {
        var updated = segment
        updated.approved = true
        updated.fitStatus = "approved"
        updateSegment(updated)
    }

    func shortenSegment(_ segment: Segment) {
        var updated = segment
        let source = updated.dubText.isEmpty ? updated.sourceText : updated.dubText
        let words = source.split(separator: " ")
        if words.count > 8 {
            updated.dubText = words.prefix(max(4, Int(Double(words.count) * 0.75))).joined(separator: " ")
        } else {
            updated.dubText = source
        }
        updated.performanceInstruction = "Shortened locally for timing. Run AI Director for a full rewrite."
        updated.fitStatus = "needs_review"
        updateSegment(updated)
    }

    func shortenTooLongSegments() {
        guard let segments = activeProject?.segments else { return }
        let targets = segments.filter { $0.fitStatus == "too_long" || $0.fitStatus == "needs_review" }
        guard !targets.isEmpty else {
            log("No too-long or review segments to shorten.")
            return
        }
        targets.forEach { shortenSegment($0) }
        log("Shortened \(targets.count) segment(s) locally.")
    }

    func recheckLocalTiming() {
        guard let segments = activeProject?.segments else { return }
        for segment in segments {
            guard let generatedDuration = segment.generatedDuration else { continue }
            var updated = segment
            if generatedDuration <= segment.duration * 1.05 && generatedDuration >= segment.duration * 0.70 {
                updated.fitStatus = "fits"
            } else if generatedDuration > segment.duration * 1.05 {
                updated.fitStatus = "too_long"
            } else {
                updated.fitStatus = "too_short"
            }
            updateSegment(updated, persist: false)
        }
        persistActiveProject()
        log("Rechecked local timing for generated clips.")
    }

    func addSpeaker() {
        guard var project = activeProject else { return }
        let next = project.speakers.count + 1
        let colors = ["#C0C1FF", "#FFB783", "#9BE7B1", "#FFB4AB", "#C7C4D7"]
        let speaker = Speaker(
            speakerId: String(format: "SPEAKER_%02d", next),
            displayName: "Speaker \(next)",
            characterName: "Character \(next)",
            genderStyle: "Neutral",
            ageStyle: "Adult",
            personalityStyle: "Neutral",
            color: colors[(next - 1) % colors.count],
            voiceProfileId: String(format: "qwen_voice_speaker_%02d", next),
            segmentCount: 0,
            totalSpeakingTime: 0.0,
            confidence: 1.0
        )
        project.speakers.append(speaker)
        activeProject = project
        selectedSpeaker = speaker
        persistActiveProject()
    }
    
    func pingServer() {
        guard let url = URL(string: "http://127.0.0.1:8765/health") else { return }
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                let healthy = error == nil && statusCode == 200
                if healthy {
                    self.isServerConnected = true
                    return
                }

                self.isServerConnected = false
                if self.activeJobStatus == "running" {
                    self.pollingTimer?.invalidate()
                    self.activeJobId = nil
                    self.activeJobKind = nil
                    self.activeJobStatus = "failed"
                    self.activeJobProgress = 0
                    self.activeJobMessage = "Task interrupted because the backend stopped"
                    self.log("Backend disconnected; the active task was interrupted.")
                }
                BackendLauncher.shared.ensureRunning()
            }
        }.resume()
    }
    
    // Create new project
    func createNewProject(name: String, src: String, tgt: String, video: String, subtitle: String?, autoAnalyze: Bool = false) {
        log("Creating project: \(name)...")
        Task {
            do {
                let project = try await DubForgeAPIClient.shared.createProject(
                    name: name, source: src, target: tgt, video: video, subtitle: subtitle
                )
                DispatchQueue.main.async {
                    self.activeProject = project
                    self.sidebarSelection = .analysis
                    self.log("Project created with ID \(project.projectId)")
                    if autoAnalyze {
                        self.runAnalysis()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.log("Failed to create project: \(error.localizedDescription)")
                }
            }
        }
    }

    func openProjectFromDisk() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let project = try JSONDecoder().decode(Project.self, from: data)
            activeProject = project
            sidebarSelection = .analysis
            log("Opened project \(project.projectId)")
        } catch {
            log("Failed to open project: \(error.localizedDescription)")
        }
    }
    
    // Pipeline Trigger: Analysis
    func runAnalysis() {
        guard var project = activeProject else { return }
        guard isServerConnected else {
            activeJobMessage = "Waiting for backend server"
            BackendLauncher.shared.ensureRunning()
            return
        }
        project.analysisStatus = .starting
        activeProject = project
        activeJobProgress = 0
        activeJobMessage = "Extracting video audio streams..."
        log("Initiating pipeline analysis for video extraction...")
        Task {
            do {
                try await syncStudioSettings()
                _ = try await DubForgeAPIClient.shared.saveProject(project)
                let jobId = try await DubForgeAPIClient.shared.startAnalysis(projectId: project.projectId)
                DispatchQueue.main.async {
                    self.activeJobId = jobId
                    self.activeJobKind = "analysis"
                    self.activeJobStatus = "running"
                    self.startJobPolling()
                }
            } catch {
                DispatchQueue.main.async {
                    self.log("Analysis start failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // Pipeline Trigger: Director Translation
    func runDialogueAdaptation() {
        guard let project = activeProject else { return }
        log("Director Gemma adaptating dialogue translation...")
        Task {
            do {
                try await syncStudioSettings()
                _ = try await DubForgeAPIClient.shared.saveProject(project)
                let jobId = try await DubForgeAPIClient.shared.startAdaptation(projectId: project.projectId)
                DispatchQueue.main.async {
                    self.activeJobId = jobId
                    self.activeJobKind = "adaptation"
                    self.activeJobStatus = "running"
                    self.startJobPolling()
                }
            } catch {
                DispatchQueue.main.async {
                    self.log("Adaptation failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // Pipeline Trigger: TTS generation
    func runTTSGeneration() {
        guard let project = activeProject else { return }
        log("\(ttsProviderDisplayName) synthesizing voice over stems...")
        Task {
            do {
                try await syncTTSSettings()
                _ = try await DubForgeAPIClient.shared.saveProject(project)
                let jobId = try await DubForgeAPIClient.shared.startTTSGeneration(projectId: project.projectId)
                DispatchQueue.main.async {
                    self.activeJobId = jobId
                    self.activeJobKind = "tts"
                    self.activeJobStatus = "running"
                    self.startJobPolling()
                }
            } catch {
                DispatchQueue.main.async {
                    self.log("TTS generation failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func generateSelectedSegment() {
        guard let segment = selectedSegment, let project = activeProject else {
            log("Select a segment before generating audio.")
            return
        }

        activeJobStatus = "running"
        activeJobMessage = "Generating segment \(segment.id) with \(ttsProviderDisplayName)"
        Task {
            do {
                try await syncTTSSettings()
                _ = try await DubForgeAPIClient.shared.saveProject(project)
                let result = try await DubForgeAPIClient.shared.generateSegment(
                    segment,
                    projectId: project.projectId
                )
                DispatchQueue.main.async {
                    var updated = segment
                    updated.generatedDuration = result.duration
                    updated.generatedAudioPath = result.audioPath
                    updated.fitStatus = result.status
                    updated.warnings = result.warnings
                    if let adaptedText = result.dubText, !adaptedText.isEmpty {
                        updated.dubText = adaptedText
                    }
                    updated.retryCount = result.retryCount
                    updated.approved = result.status == "fits"
                    self.updateSegment(updated)
                    self.activeJobStatus = result.status == "failed" ? "failed" : "completed"
                    self.activeJobMessage = "Generated segment \(segment.id) with \(self.ttsProviderDisplayName)"
                }
            } catch {
                DispatchQueue.main.async {
                    let message = error.localizedDescription
                    var updated = segment
                    updated.fitStatus = "failed"
                    updated.warnings = [message]
                    self.updateSegment(updated)
                    self.activeJobStatus = "failed"
                    self.activeJobMessage = message
                    self.log("Segment generation failed: \(message)")
                }
            }
        }
    }
    
    // Pipeline Trigger: Separate Vocals
    func runSeparation() {
        guard let project = activeProject else { return }
        log("Separating original vocals with Demucs isolation...")
        Task {
            do {
                try await syncStudioSettings()
                _ = try await DubForgeAPIClient.shared.saveProject(project)
                let jobId = try await DubForgeAPIClient.shared.startSeparation(projectId: project.projectId)
                DispatchQueue.main.async {
                    self.activeJobId = jobId
                    self.activeJobKind = "separation"
                    self.activeJobStatus = "running"
                    self.startJobPolling()
                }
            } catch {
                DispatchQueue.main.async {
                    self.log("Separation failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // Pipeline Trigger: Mix stems
    func runMixing() {
        guard let project = activeProject else { return }
        log("Master mixing background and dubbed voices...")
        Task {
            do {
                try await syncStudioSettings()
                _ = try await DubForgeAPIClient.shared.saveProject(project)
                let jobId = try await DubForgeAPIClient.shared.startMixing(projectId: project.projectId)
                DispatchQueue.main.async {
                    self.activeJobId = jobId
                    self.activeJobKind = "mixing"
                    self.activeJobStatus = "running"
                    self.startJobPolling()
                }
            } catch {
                DispatchQueue.main.async {
                    self.log("Mixing execution failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // Pipeline Trigger: Merge Video
    func runExport() {
        guard let project = activeProject else { return }
        log("Merging dubbed track back into source video stream...")
        Task {
            do {
                try await syncStudioSettings()
                _ = try await DubForgeAPIClient.shared.saveProject(project)
                let jobId = try await DubForgeAPIClient.shared.startExport(projectId: project.projectId)
                DispatchQueue.main.async {
                    self.activeJobId = jobId
                    self.activeJobKind = "export"
                    self.activeJobStatus = "running"
                    self.startJobPolling()
                }
            } catch {
                DispatchQueue.main.async {
                    self.log("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func cancelActiveJob() {
        guard let jobId = activeJobId else {
            log("No active job to cancel.")
            return
        }

        Task {
            do {
                try await DubForgeAPIClient.shared.cancelJob(id: jobId)
                DispatchQueue.main.async {
                    self.pollingTimer?.invalidate()
                    self.activeJobId = nil
                    self.activeJobKind = nil
                    self.activeJobStatus = "cancelled"
                    self.activeJobProgress = 100.0
                    self.activeJobMessage = "Cancelled by user"
                    self.log("Cancelled job \(jobId).")
                }
            } catch {
                DispatchQueue.main.async {
                    self.log("Cancel failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // Poll active jobs
    private func startJobPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pollActiveJob()
        }
    }
    
    private func pollActiveJob() {
        guard let jobId = activeJobId else {
            pollingTimer?.invalidate()
            return
        }
        
        Task {
            do {
                let (status, progress, message, result) = try await DubForgeAPIClient.shared.checkJobStatus(id: jobId)
                DispatchQueue.main.async {
                    self.jobPollingFailureCount = 0
                    self.activeJobProgress = progress
                    self.activeJobMessage = message
                    self.activeJobStatus = status
                    self.synchronizeProject(from: result)
                    
                    self.log("Job status update: \(message) (\(Int(progress))%)")
                    
                    if status == "completed" {
                        self.pollingTimer?.invalidate()
                        self.activeJobId = nil
                        self.activeJobKind = nil
                        self.activeJobMessage = "Operation finished successfully"
                        
                    } else if status == "failed" || status == "cancelled" {
                        self.pollingTimer?.invalidate()
                        self.activeJobId = nil
                        self.activeJobKind = nil
                        self.log(status == "cancelled" ? "Job cancelled: \(message)" : "Job failed: \(message)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.jobPollingFailureCount += 1
                    if self.jobPollingFailureCount >= 2 {
                        self.pollingTimer?.invalidate()
                        self.activeJobId = nil
                        self.activeJobKind = nil
                        self.activeJobStatus = "failed"
                        self.activeJobProgress = 0
                        self.activeJobMessage = "Task interrupted because job status is unavailable"
                    }
                    self.log("Error querying job progress: \(error.localizedDescription)")
                }
            }
        }
    }

    private func synchronizeProject(from result: [String: Any]?) {
        guard let projDict = result?["project"] else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: projDict)
            let updatedProj = try JSONDecoder().decode(Project.self, from: data)
            activeProject = updatedProj
            if let selected = selectedSegment,
               let refreshed = updatedProj.segments.first(where: { $0.id == selected.id }) {
                selectedSegment = refreshed
            }
            log("Project state successfully synchronized.")
        } catch {
            log("Decodable mapping failed: \(error)")
        }
    }
}

// MARK: - Main UI Layout (Three Pane View)
struct ContentView: View {
    @StateObject private var vm = ProjectViewModel()
    @State private var sidebarWidth: CGFloat = 260
    @State private var inspectorWidth: CGFloat = 340
    @State private var showNewProjectSheet = false

    private var shouldShowInspector: Bool {
        guard vm.selectedSegment != nil || vm.selectedSpeaker != nil || vm.selectedVoice != nil else {
            return false
        }
        switch vm.sidebarSelection {
        case .transcript, .director, .dubbing, .mixing, .export:
            return true
        case .importMedia, .analysis, .speakers, .voices, .settings:
            return false
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: 1. Top Toolbar
            TopToolbarView(vm: vm, showNewProject: $showNewProjectSheet)
                .frame(height: 48)
                .background(Color.surfaceLowest)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.outlineBorder), alignment: .bottom)
            
            // MARK: 1b. Disconnected Warning Banner
            if !vm.isServerConnected {
                DisconnectedBannerView()
            }

            // MARK: 2. Core Workspace Panes
            HStack(spacing: 0) {
                // Left Sidebar
                SidebarView(vm: vm)
                    .frame(width: sidebarWidth)
                    .background(Color.surfaceLowest)
                    .overlay(Rectangle().frame(width: 1).foregroundColor(.outlineBorder), alignment: .trailing)
                
                // Center workspace content
                CenterContentView(vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.darkBackground)
                
                // Right Inspector
                if shouldShowInspector {
                    InspectorView(vm: vm)
                        .frame(width: inspectorWidth)
                        .background(Color.surfaceLow)
                        .overlay(Rectangle().frame(width: 1).foregroundColor(.outlineBorder), alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // MARK: 3. Bottom Status Bar
            BottomStatusBarView(vm: vm)
                .frame(height: 32)
                .background(Color.surfaceLowest)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.outlineBorder), alignment: .top)
        }
        .preferredColorScheme(.dark)
        .font(.custom("Inter", size: 13))
        .foregroundColor(.textPrimary)
        .modifier(DubForgeRootModifiers(vm: vm, showNewProjectSheet: $showNewProjectSheet))
    }
}

// MARK: - Root sheet + notification wiring
// Kept in its own ViewModifier so the notification/sheet chain type-checks
// separately from ContentView.body, which otherwise blows the Swift
// type-checker's time budget.
struct DubForgeRootModifiers: ViewModifier {
    @ObservedObject var vm: ProjectViewModel
    @Binding var showNewProjectSheet: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showNewProjectSheet) {
                NewProjectView(vm: vm)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dubForgeNewProject)) { _ in
                showNewProjectSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .dubForgeOpenProject)) { _ in
                vm.openProjectFromDisk()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dubForgeImportMedia)) { _ in
                vm.sidebarSelection = .importMedia
                showNewProjectSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .dubForgeExportProject)) { _ in
                vm.runExport()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dubForgeRunAnalysis)) { _ in
                vm.runAnalysis()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dubForgeGenerateDubbing)) { _ in
                vm.runTTSGeneration()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dubForgeCancelJob)) { _ in
                vm.cancelActiveJob()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dubForgeShowSettings)) { _ in
                vm.sidebarSelection = .settings
            }
    }
}

// MARK: - Disconnected Warning Banner
struct DisconnectedBannerView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.warningColor)
            Text("Backend server is not running — features are unavailable.")
                .font(.caption)
                .foregroundColor(.warningColor)
            Spacer()
            Button("Restart Server") {
                BackendLauncher.shared.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    BackendLauncher.shared.start()
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.warningColor.opacity(0.2))
            .cornerRadius(5)
            .foregroundColor(.warningColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.warningColor.opacity(0.08))
        .overlay(Rectangle().frame(height: 1).foregroundColor(.warningColor.opacity(0.3)), alignment: .bottom)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Top Toolbar View
struct TopToolbarView: View {
    @ObservedObject var vm: ProjectViewModel
    @Binding var showNewProject: Bool
    
    private let pipelineStages = ["Import", "Analysis", "Transcript", "Speakers", "Voices", "AI Director", "Dubbing", "Mixing", "Export"]
    
    var body: some View {
        HStack(spacing: 12) {
            // App branding
            HStack(spacing: 8) {
                Image(systemName: "film.stack")
                    .font(.title3)
                    .foregroundColor(.brandPrimary)
                Text("DubForge")
                    .font(.headline)
                    .foregroundColor(.brandPrimary)
            }
            .padding(.leading, 16)
            
            Button(action: { showNewProject = true }) {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("New Project")
                }
            }
            .buttonStyle(.bordered)
            
            // Pipeline Mini Stepper (#1)
            HStack(spacing: 4) {
                ForEach(pipelineStages, id: \.self) { stage in
                    let isCurrent = vm.activeProject?.pipelineStage == stage
                    Text(stage)
                        .font(.system(size: 9, weight: isCurrent ? .bold : .regular))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .foregroundColor(isCurrent ? .white : .textSecondary)
                        .background(isCurrent ? Color.brandPrimary : Color.surfaceHigh)
                        .clipShape(Capsule())
                }
            }
            
            Spacer()
            
            // Transport Controls (#2)
            HStack(spacing: 4) {
                Button(action: { vm.isPlaying = true }) {
                    Image(systemName: "play.fill")
                        .foregroundColor(vm.isPlaying ? .brandPrimary : .textSecondary)
                }
                .buttonStyle(.plain)
                Button(action: { vm.isPlaying = false }) {
                    Image(systemName: "pause.fill")
                        .foregroundColor(!vm.isPlaying ? .brandPrimary : .textSecondary)
                }
                .buttonStyle(.plain)
                Button(action: {
                    vm.isPlaying = false
                    vm.playhead = 0
                }) {
                    Image(systemName: "stop.fill")
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            
            // Preview Modes (DSL Option)
            Picker("Preview", selection: $vm.previewMode) {
                Text("Original").tag("Original")
                Text("Background").tag("Background Only")
                Text("Voice Only").tag("Dubbed Voice Only")
                Text("Final Mix").tag("Final Mix")
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            
            Spacer()
            
            // Status and Badges
            HStack(spacing: 12) {
                // Job Status Badge (#3)
                HStack(spacing: 4) {
                    Circle()
                        .fill(jobStatusColor)
                        .frame(width: 7, height: 7)
                    Text(vm.activeJobStatus.capitalized)
                        .font(.caption2)
                        .foregroundColor(jobStatusColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(jobStatusColor.opacity(0.12))
                .clipShape(Capsule())
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(vm.isServerConnected ? Color.successColor : Color.errorColor)
                        .frame(width: 8, height: 8)
                    Text(vm.isServerConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                
                Button(action: { vm.runExport() }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export")
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.brandPrimary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(vm.activeProject == nil)
            }
            .padding(.trailing, 16)
        }
    }
    
    private var jobStatusColor: Color {
        switch vm.activeJobStatus.lowercased() {
        case "running": return .brandPrimary
        case "completed": return .successColor
        case "failed": return .errorColor
        default: return .textSecondary
        }
    }
}

// MARK: - Sidebar View
struct SidebarView: View {
    @ObservedObject var vm: ProjectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let project = vm.activeProject {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundColor(.brandPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(project.sourceLanguage) ➔ \(project.targetLanguage) Dub")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider().foregroundColor(.outlineBorder)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SidebarItem.allCases) { item in
                        Button(action: { vm.sidebarSelection = item }) {
                            HStack(spacing: 10) {
                                Image(systemName: item.icon)
                                    .frame(width: 18, alignment: .center)
                                Text(item.rawValue)
                                Spacer()
                                if vm.activeProject?.pipelineStage == item.rawValue {
                                    Circle()
                                        .fill(Color.brandPrimaryStrong)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(vm.sidebarSelection == item ? Color.brandPrimaryStrong.opacity(0.15) : Color.clear)
                            .foregroundColor(vm.sidebarSelection == item ? .brandPrimary : .textSecondary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
    }
}

// MARK: - Center Content View Router
struct CenterContentView: View {
    @ObservedObject var vm: ProjectViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            switch vm.sidebarSelection {
            case .importMedia:
                ImportView(vm: vm)
            case .analysis:
                AnalysisView(vm: vm)
            case .transcript:
                TranscriptView(vm: vm)
            case .speakers:
                SpeakerRegistryView(vm: vm)
            case .voices:
                VoiceRegistryView(vm: vm)
            case .director:
                AIDirectorView(vm: vm)
            case .dubbing:
                DubbingView(vm: vm)
            case .mixing:
                MixingView(vm: vm)
            case .export:
                ExportScreenView(vm: vm)
            case .settings:
                SettingsScreenView(vm: vm)
            }
        }
    }
}

// MARK: - Language Catalogue
struct LanguageCatalogue {
    struct Language: Identifiable, Hashable {
        let id: String; let name: String; let googleCode: String; let whisperCode: String
    }
    static let all: [Language] = [
        Language(id:"Afrikaans",  name:"Afrikaans",           googleCode:"af-ZA",  whisperCode:"af"),
        Language(id:"Albanian",   name:"Albanian",             googleCode:"sq-AL",  whisperCode:"sq"),
        Language(id:"Arabic",     name:"Arabic",               googleCode:"ar-XA",  whisperCode:"ar"),
        Language(id:"Armenian",   name:"Armenian",             googleCode:"hy-AM",  whisperCode:"hy"),
        Language(id:"Azerbaijani",name:"Azerbaijani",          googleCode:"az-AZ",  whisperCode:"az"),
        Language(id:"Basque",     name:"Basque",               googleCode:"eu-ES",  whisperCode:"eu"),
        Language(id:"Bengali",    name:"Bengali",              googleCode:"bn-IN",  whisperCode:"bn"),
        Language(id:"Bosnian",    name:"Bosnian",              googleCode:"bs-BA",  whisperCode:"bs"),
        Language(id:"Bulgarian",  name:"Bulgarian",            googleCode:"bg-BG",  whisperCode:"bg"),
        Language(id:"Catalan",    name:"Catalan",              googleCode:"ca-ES",  whisperCode:"ca"),
        Language(id:"Chinese (Simplified)",  name:"Chinese (Simplified)",  googleCode:"zh-CN", whisperCode:"zh"),
        Language(id:"Chinese (Traditional)", name:"Chinese (Traditional)", googleCode:"zh-TW", whisperCode:"zh"),
        Language(id:"Croatian",   name:"Croatian",             googleCode:"hr-HR",  whisperCode:"hr"),
        Language(id:"Czech",      name:"Czech",                googleCode:"cs-CZ",  whisperCode:"cs"),
        Language(id:"Danish",     name:"Danish",               googleCode:"da-DK",  whisperCode:"da"),
        Language(id:"Dutch",      name:"Dutch",                googleCode:"nl-NL",  whisperCode:"nl"),
        Language(id:"English",    name:"English",              googleCode:"en-US",  whisperCode:"en"),
        Language(id:"Estonian",   name:"Estonian",             googleCode:"et-EE",  whisperCode:"et"),
        Language(id:"Filipino",   name:"Filipino",             googleCode:"fil-PH", whisperCode:"tl"),
        Language(id:"Finnish",    name:"Finnish",              googleCode:"fi-FI",  whisperCode:"fi"),
        Language(id:"French",     name:"French",               googleCode:"fr-FR",  whisperCode:"fr"),
        Language(id:"Galician",   name:"Galician",             googleCode:"gl-ES",  whisperCode:"gl"),
        Language(id:"Georgian",   name:"Georgian",             googleCode:"ka-GE",  whisperCode:"ka"),
        Language(id:"German",     name:"German",               googleCode:"de-DE",  whisperCode:"de"),
        Language(id:"Greek",      name:"Greek",                googleCode:"el-GR",  whisperCode:"el"),
        Language(id:"Gujarati",   name:"Gujarati",             googleCode:"gu-IN",  whisperCode:"gu"),
        Language(id:"Hebrew",     name:"Hebrew",               googleCode:"he-IL",  whisperCode:"he"),
        Language(id:"Hindi",      name:"Hindi",                googleCode:"hi-IN",  whisperCode:"hi"),
        Language(id:"Hungarian",  name:"Hungarian",            googleCode:"hu-HU",  whisperCode:"hu"),
        Language(id:"Icelandic",  name:"Icelandic",            googleCode:"is-IS",  whisperCode:"is"),
        Language(id:"Indonesian", name:"Indonesian",           googleCode:"id-ID",  whisperCode:"id"),
        Language(id:"Irish",      name:"Irish",                googleCode:"ga-IE",  whisperCode:"ga"),
        Language(id:"Italian",    name:"Italian",              googleCode:"it-IT",  whisperCode:"it"),
        Language(id:"Japanese",   name:"Japanese",             googleCode:"ja-JP",  whisperCode:"ja"),
        Language(id:"Kannada",    name:"Kannada",              googleCode:"kn-IN",  whisperCode:"kn"),
        Language(id:"Kazakh",     name:"Kazakh",               googleCode:"kk-KZ",  whisperCode:"kk"),
        Language(id:"Korean",     name:"Korean",               googleCode:"ko-KR",  whisperCode:"ko"),
        Language(id:"Latvian",    name:"Latvian",              googleCode:"lv-LV",  whisperCode:"lv"),
        Language(id:"Lithuanian", name:"Lithuanian",           googleCode:"lt-LT",  whisperCode:"lt"),
        Language(id:"Macedonian", name:"Macedonian",           googleCode:"mk-MK",  whisperCode:"mk"),
        Language(id:"Malay",      name:"Malay",                googleCode:"ms-MY",  whisperCode:"ms"),
        Language(id:"Malayalam",  name:"Malayalam",            googleCode:"ml-IN",  whisperCode:"ml"),
        Language(id:"Maltese",    name:"Maltese",              googleCode:"mt-MT",  whisperCode:"mt"),
        Language(id:"Marathi",    name:"Marathi",              googleCode:"mr-IN",  whisperCode:"mr"),
        Language(id:"Norwegian",  name:"Norwegian",            googleCode:"nb-NO",  whisperCode:"no"),
        Language(id:"Persian",    name:"Persian",              googleCode:"fa-IR",  whisperCode:"fa"),
        Language(id:"Polish",     name:"Polish",               googleCode:"pl-PL",  whisperCode:"pl"),
        Language(id:"Portuguese", name:"Portuguese",           googleCode:"pt-PT",  whisperCode:"pt"),
        Language(id:"Punjabi",    name:"Punjabi",              googleCode:"pa-IN",  whisperCode:"pa"),
        Language(id:"Romanian",   name:"Romanian",             googleCode:"ro-RO",  whisperCode:"ro"),
        Language(id:"Russian",    name:"Russian",              googleCode:"ru-RU",  whisperCode:"ru"),
        Language(id:"Serbian",    name:"Serbian",              googleCode:"sr-RS",  whisperCode:"sr"),
        Language(id:"Slovak",     name:"Slovak",               googleCode:"sk-SK",  whisperCode:"sk"),
        Language(id:"Slovenian",  name:"Slovenian",            googleCode:"sl-SI",  whisperCode:"sl"),
        Language(id:"Spanish",    name:"Spanish",              googleCode:"es-ES",  whisperCode:"es"),
        Language(id:"Swahili",    name:"Swahili",              googleCode:"sw-KE",  whisperCode:"sw"),
        Language(id:"Swedish",    name:"Swedish",              googleCode:"sv-SE",  whisperCode:"sv"),
        Language(id:"Tamil",      name:"Tamil",                googleCode:"ta-IN",  whisperCode:"ta"),
        Language(id:"Telugu",     name:"Telugu",               googleCode:"te-IN",  whisperCode:"te"),
        Language(id:"Thai",       name:"Thai",                 googleCode:"th-TH",  whisperCode:"th"),
        Language(id:"Turkish",    name:"Turkish",              googleCode:"tr-TR",  whisperCode:"tr"),
        Language(id:"Ukrainian",  name:"Ukrainian",            googleCode:"uk-UA",  whisperCode:"uk"),
        Language(id:"Urdu",       name:"Urdu",                 googleCode:"ur-IN",  whisperCode:"ur"),
        Language(id:"Uzbek",      name:"Uzbek",                googleCode:"uz-UZ",  whisperCode:"uz"),
        Language(id:"Vietnamese", name:"Vietnamese",           googleCode:"vi-VN",  whisperCode:"vi"),
        Language(id:"Welsh",      name:"Welsh",                googleCode:"cy-GB",  whisperCode:"cy"),
    ]
    static let elevenLabsIds: Set<String> = [
        "English","Spanish","French","German","Italian","Portuguese","Polish",
        "Hindi","Arabic","Turkish","Russian","Dutch","Czech","Slovak","Romanian",
        "Hungarian","Norwegian","Swedish","Danish","Finnish","Ukrainian","Greek",
        "Indonesian","Malay","Vietnamese","Thai","Korean","Japanese",
        "Chinese (Simplified)","Chinese (Traditional)","Filipino","Tamil","Bulgarian","Croatian",
    ]
    static let googleIds: Set<String> = [
        "Afrikaans","Albanian","Arabic","Armenian","Azerbaijani","Basque","Bengali",
        "Bulgarian","Catalan","Chinese (Simplified)","Chinese (Traditional)","Croatian",
        "Czech","Danish","Dutch","English","Estonian","Filipino","Finnish","French",
        "Galician","Georgian","German","Greek","Gujarati","Hebrew","Hindi","Hungarian",
        "Icelandic","Indonesian","Irish","Italian","Japanese","Kannada","Korean",
        "Latvian","Lithuanian","Macedonian","Malay","Malayalam","Maltese","Marathi",
        "Norwegian","Persian","Polish","Portuguese","Punjabi","Romanian","Russian",
        "Serbian","Slovak","Slovenian","Spanish","Swahili","Swedish","Tamil","Telugu",
        "Thai","Turkish","Ukrainian","Urdu","Vietnamese","Welsh",
    ]
    static func targetLanguages(for provider: String) -> [Language] {
        switch provider {
        case "elevenlabs": return all.filter { elevenLabsIds.contains($0.id) }
        case "google":     return all.filter { googleIds.contains($0.id) }
        default:           return all
        }
    }
}

private enum MediaSourceMode: String, CaseIterable, Identifiable {
    case local = "Local File"
    case link = "Video Link"

    var id: String { rawValue }
}

private struct MediaSourcePicker: View {
    @Binding var videoPath: String
    @Binding var subtitlePath: String

    @State private var sourceMode: MediaSourceMode = .local
    @State private var remoteURL = ""
    @State private var mediaInfo: RemoteMediaInfo?
    @State private var isInspecting = false
    @State private var permissionConfirmed = false
    @State private var downloadJobId: String?
    @State private var downloadProgress = 0.0
    @State private var downloadMessage = ""
    @State private var downloadedPath = ""
    @State private var errorMessage: String?
    @State private var pollingTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Source Media").foregroundColor(.textSecondary)

            Picker("Source Media", selection: $sourceMode) {
                ForEach(MediaSourceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if sourceMode == .local {
                HStack {
                    TextField("/path/to/video.mp4", text: $videoPath)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        browseVideo()
                    } label: {
                        Label("Browse", systemImage: "folder")
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("https://www.youtube.com/watch?v=...", text: $remoteURL)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { inspectLink() }
                        Button {
                            inspectLink()
                        } label: {
                            if isInspecting {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Inspect", systemImage: "magnifyingglass")
                            }
                        }
                        .disabled(remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isInspecting || downloadJobId != nil)
                    }

                    if let mediaInfo {
                        HStack(alignment: .top, spacing: 14) {
                            if let thumbnail = mediaInfo.thumbnail,
                               let thumbnailURL = URL(string: thumbnail) {
                                AsyncImage(url: thumbnailURL) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        ZStack {
                                            Color.surfaceHighest
                                            Image(systemName: "film").foregroundColor(.textSecondary)
                                        }
                                    }
                                }
                                .frame(width: 152, height: 86)
                                .clipped()
                                .cornerRadius(6)
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text(mediaInfo.title)
                                    .fontWeight(.semibold)
                                    .lineLimit(2)
                                Text(mediaInfo.creator)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .lineLimit(1)
                                HStack(spacing: 10) {
                                    Label(mediaInfo.platform, systemImage: "network")
                                    Label(formatDuration(mediaInfo.duration), systemImage: "clock")
                                    Label(mediaInfo.resolution, systemImage: "rectangle.inset.filled")
                                    if let fileSize = mediaInfo.fileSize {
                                        Label(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file), systemImage: "internaldrive")
                                    }
                                }
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }

                        Toggle("I have permission to download and process this media", isOn: $permissionConfirmed)
                            .toggleStyle(.checkbox)

                        if let jobId = downloadJobId {
                            HStack(spacing: 10) {
                                ProgressView(value: downloadProgress, total: 100)
                                    .progressViewStyle(.linear)
                                Text("\(Int(downloadProgress))%")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 40, alignment: .trailing)
                                Button(role: .cancel) {
                                    cancelDownload(jobId)
                                } label: {
                                    Image(systemName: "stop.fill")
                                }
                                .help("Cancel download")
                            }
                            Text(downloadMessage)
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        } else if !downloadedPath.isEmpty {
                            Label("Video downloaded and ready", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.successColor)
                        } else {
                            Button {
                                startDownload()
                            } label: {
                                Label("Download Video", systemImage: "arrow.down.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!permissionConfirmed)
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.errorColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Optional Subtitle File").foregroundColor(.textSecondary)
                HStack {
                    TextField("/path/to/subtitle.srt", text: $subtitlePath)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        browseSubtitle()
                    } label: {
                        Label("Browse", systemImage: "captions.bubble")
                    }
                }
            }
        }
        .onChange(of: sourceMode) { _ in
            pollingTask?.cancel()
            if let jobId = downloadJobId {
                Task { try? await DubForgeAPIClient.shared.cancelJob(id: jobId) }
            }
            videoPath = ""
            downloadedPath = ""
            downloadJobId = nil
            downloadProgress = 0
            downloadMessage = ""
            errorMessage = nil
        }
        .onChange(of: remoteURL) { _ in
            guard downloadJobId == nil else { return }
            mediaInfo = nil
            permissionConfirmed = false
            if videoPath == downloadedPath {
                videoPath = ""
            }
            downloadedPath = ""
            errorMessage = nil
        }
        .onDisappear {
            pollingTask?.cancel()
            if let jobId = downloadJobId {
                Task { try? await DubForgeAPIClient.shared.cancelJob(id: jobId) }
            }
        }
    }

    private func inspectLink() {
        let link = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return }
        isInspecting = true
        mediaInfo = nil
        errorMessage = nil
        Task { @MainActor in
            do {
                mediaInfo = try await DubForgeAPIClient.shared.inspectMediaURL(link)
            } catch {
                errorMessage = error.localizedDescription
            }
            isInspecting = false
        }
    }

    private func startDownload() {
        let link = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mediaInfo != nil, permissionConfirmed, !link.isEmpty else { return }
        errorMessage = nil
        downloadProgress = 0
        downloadMessage = "Starting download"
        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            do {
                let jobId = try await DubForgeAPIClient.shared.startMediaURLDownload(link)
                downloadJobId = jobId
                while !Task.isCancelled {
                    let status = try await DubForgeAPIClient.shared.checkJobStatus(id: jobId)
                    downloadProgress = status.progress
                    downloadMessage = status.message
                    if status.status == "completed" {
                        guard let path = status.result?["path"] as? String, !path.isEmpty else {
                            throw DubForgeAPIError(message: "The completed download did not return a local video path.")
                        }
                        downloadedPath = path
                        videoPath = path
                        downloadJobId = nil
                        return
                    }
                    if status.status == "failed" || status.status == "cancelled" {
                        throw DubForgeAPIError(message: status.message)
                    }
                    try await Task.sleep(nanoseconds: 750_000_000)
                }
            } catch is CancellationError {
                downloadJobId = nil
            } catch {
                errorMessage = error.localizedDescription
                downloadJobId = nil
            }
        }
    }

    private func cancelDownload(_ jobId: String) {
        pollingTask?.cancel()
        Task { try? await DubForgeAPIClient.shared.cancelJob(id: jobId) }
        downloadJobId = nil
        downloadProgress = 0
        downloadMessage = "Download cancelled"
    }

    private func browseVideo() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        if panel.runModal() == .OK, let path = panel.url?.path {
            videoPath = path
        }
    }

    private func browseSubtitle() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let path = panel.url?.path {
            subtitlePath = path
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Screen: Import
struct ImportView: View {
    @ObservedObject var vm: ProjectViewModel
    @State private var projectName = "My Dubbing Project"
    @State private var sourceLanguage = "English"
    @State private var targetLanguage = "Arabic"
    @State private var videoPath = ""
    @State private var subtitlePath = ""
    @State private var transMode = "subtitle_text_whisper_timing"

    private var targetList: [LanguageCatalogue.Language] {
        LanguageCatalogue.targetLanguages(for: vm.ttsProvider)
    }
    private var providerBadge: String {
        switch vm.ttsProvider {
        case "google":     return "Google Cloud TTS (\(LanguageCatalogue.googleIds.count) target langs)"
        case "elevenlabs": return "ElevenLabs (\(LanguageCatalogue.elevenLabsIds.count) target langs)"
        default:           return "Qwen3-TTS (all languages)"
        }
    }
    private var providerColor: Color {
        vm.ttsProvider == "elevenlabs" ? .successColor :
        vm.ttsProvider == "google"     ? .brandPrimary : .warningColor
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Import Media & Start Dubbing")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Begin a new speech alignment session by importing source files and selecting target languages.")
                        .foregroundColor(.textSecondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project Name").foregroundColor(.textSecondary)
                        TextField("Name", text: $projectName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // TTS Engine badge + Settings shortcut
                    HStack(spacing: 6) {
                        Circle().fill(providerColor).frame(width: 7, height: 7)
                        Text("TTS Engine: \(providerBadge)")
                            .font(.caption).foregroundColor(.textSecondary)
                        Spacer()
                        Button("Open Settings") { vm.sidebarSelection = .settings }
                            .buttonStyle(.plain).font(.caption2).foregroundColor(.brandPrimary)
                    }

                    HStack(spacing: 16) {
                        // Source — Whisper transcribes all languages
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Source Language").foregroundColor(.textSecondary)
                            Picker("", selection: $sourceLanguage) {
                                ForEach(LanguageCatalogue.all) { lang in
                                    Text(lang.name).tag(lang.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .labelsHidden()
                        }

                        // Target — filtered by TTS provider capability
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                Text("Target Language").foregroundColor(.textSecondary)
                                if vm.ttsProvider != "qwen" {
                                    Text("(\(targetList.count) supported)")
                                        .font(.caption2).foregroundColor(.brandPrimary)
                                }
                            }
                            Picker("", selection: $targetLanguage) {
                                ForEach(targetList) { lang in
                                    Text(lang.name).tag(lang.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .labelsHidden()
                            .onChange(of: vm.ttsProvider) { _ in
                                if !targetList.contains(where: { $0.id == targetLanguage }) {
                                    targetLanguage = targetList.first?.id ?? "English"
                                }
                            }
                        }
                    }
                    
                    MediaSourcePicker(videoPath: $videoPath, subtitlePath: $subtitlePath)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transcription & Alignment Strategy").foregroundColor(.textSecondary)
                        Picker("", selection: $transMode) {
                            Text("Use subtitle timing strictly").tag("subtitle_only")
                            Text("Run Whisper completely").tag("whisper_only")
                            Text("Use subtitle text + Whisper timing verification").tag("subtitle_text_whisper_timing")
                        }
                        .pickerStyle(.radioGroup)
                    }
                }
                .padding(20)
                .background(Color.surfaceLow)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineBorder, lineWidth: 1))
                
                Button(action: {
                    vm.createNewProject(
                        name: projectName,
                        src: sourceLanguage,
                        tgt: targetLanguage,
                        video: videoPath,
                        subtitle: subtitlePath.isEmpty ? nil : subtitlePath,
                        autoAnalyze: true
                    )
                }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Create Project & Launch Analysis")
                    }
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.brandPrimary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(videoPath.isEmpty)
            }
            .padding(40)
        }
    }
    
}

// MARK: - Screen: Analysis Pipeline
struct AnalysisView: View {
    @ObservedObject var vm: ProjectViewModel

    private var hasSegments: Bool {
        vm.activeProject?.segments.isEmpty == false
    }

    private var hasSpeakers: Bool {
        vm.activeProject?.speakers.isEmpty == false
    }

    private var running: Bool {
        vm.isServerConnected && vm.activeJobStatus == "running" && vm.activeJobKind == "analysis" && vm.activeJobId != nil
    }

    private func status(persisted: String?, done: Bool, lowerBound: Double, upperBound: Double) -> String {
        if let persisted { return persisted }
        if done { return "completed" }
        guard running else { return "pending" }
        if vm.activeJobProgress >= upperBound { return "completed" }
        if vm.activeJobProgress >= lowerBound { return "running" }
        return "pending"
    }

    private func stageProgress(lowerBound: Double, upperBound: Double) -> Double {
        guard running, upperBound > lowerBound else { return 0 }
        return min(1, max(0, (vm.activeJobProgress - lowerBound) / (upperBound - lowerBound)))
    }

    private func progress(for status: String, lowerBound: Double, upperBound: Double) -> Double {
        if status == "completed" { return 1 }
        if status == "running" { return stageProgress(lowerBound: lowerBound, upperBound: upperBound) }
        return 0
    }
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Analysis Pipeline Dashboard")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("FFmpeg and Whisper are extracting and slicing audio segments. Diarization is resolving speaker identities.")
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 16) {
                let extractStatus = status(persisted: vm.activeProject?.analysisStatus?.extractAudio, done: hasSegments, lowerBound: 0, upperBound: 30)
                let transcriptionStatus = status(persisted: vm.activeProject?.analysisStatus?.transcription, done: hasSegments, lowerBound: 30, upperBound: 60)
                let diarizationStatus = status(persisted: vm.activeProject?.analysisStatus?.diarization, done: hasSpeakers, lowerBound: 60, upperBound: 80)
                let integrationStatus = status(persisted: vm.activeProject?.analysisStatus?.integration, done: hasSegments && hasSpeakers, lowerBound: 80, upperBound: 100)

                PipelineCard(title: "1. Extract Audio Stem", progress: progress(for: extractStatus, lowerBound: 0, upperBound: 30), status: extractStatus)
                PipelineCard(title: "2. Speech Transcription (Whisper)", progress: progress(for: transcriptionStatus, lowerBound: 30, upperBound: 60), status: transcriptionStatus)
                PipelineCard(
                    title: "3. Speaker Diarization Mapping",
                    progress: progress(for: diarizationStatus, lowerBound: 60, upperBound: 80),
                    status: diarizationStatus,
                    detail: diarizationStatus == "failed" ? vm.activeProject?.analysisStatus?.message : nil
                )
                PipelineCard(title: "4. Timeline Segment Integration", progress: progress(for: integrationStatus, lowerBound: 80, upperBound: 100), status: integrationStatus)
            }
            
            if vm.activeProject?.segments.isEmpty == false {
                Button(action: { vm.sidebarSelection = .transcript }) {
                    Text("Open Segment Table Review")
                        .foregroundColor(.black)
                        .font(.headline)
                        .padding()
                        .frame(width: 280)
                        .background(Color.brandPrimary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: { vm.runAnalysis() }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Trigger Core Extraction")
                    }
                    .foregroundColor(.black)
                    .font(.headline)
                    .padding()
                    .frame(width: 280)
                    .background(Color.brandPrimary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(running || !vm.isServerConnected)
            }
            
            Spacer()
        }
        .padding(40)
    }
}

struct PipelineCard: View {
    let title: String
    let progress: Double
    let status: String
    var detail: String? = nil

    private var statusColor: Color {
        switch status {
        case "completed": return .successColor
        case "running": return .brandPrimary
        case "failed": return .errorColor
        default: return .textSecondary
        }
    }

    private var statusIcon: String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "running": return "arrow.triangle.2.circlepath"
        case "failed": return "xmark.circle.fill"
        default: return "circle"
        }
    }
    
    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                if status == "running" {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.errorColor)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Text(status.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(status == "pending" ? 0.08 : 0.15))
                .foregroundColor(statusColor)
                .cornerRadius(4)
        }
        .padding(16)
        .background(Color.surfaceLow)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineBorder, lineWidth: 1))
    }
}

// AVKit's SwiftUI VideoPlayer can abort during a large project-state refresh on
// current macOS builds. Keep the AppKit player view and AVPlayer lifecycle stable.
struct StableVideoPlayer: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var representedURL: URL?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        playerView.videoGravity = .resizeAspect
        playerView.player = AVPlayer(url: url)
        context.coordinator.representedURL = url
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        guard context.coordinator.representedURL != url else { return }
        playerView.player?.pause()
        playerView.player?.replaceCurrentItem(with: AVPlayerItem(url: url))
        context.coordinator.representedURL = url
    }

    static func dismantleNSView(_ playerView: AVPlayerView, coordinator: Coordinator) {
        playerView.player?.pause()
        playerView.player = nil
        coordinator.representedURL = nil
    }
}

// MARK: - Screen: Transcript Review
struct TranscriptView: View {
    @ObservedObject var vm: ProjectViewModel
    @State private var filterMode = "All"
    @State private var searchString = ""

    private var timelineDuration: Double {
        vm.activeProject?.segments.map(\.end).max() ?? 100.0
    }

    private var fitCount: Int {
        vm.activeProject?.segments.filter { $0.fitStatus == "fits" || $0.fitStatus == "approved" }.count ?? 0
    }

    private var reviewCount: Int {
        vm.activeProject?.segments.filter { $0.fitStatus == "needs_review" || $0.fitStatus == "too_long" || $0.fitStatus == "too_short" }.count ?? 0
    }

    private var failedCount: Int {
        vm.activeProject?.segments.filter { $0.fitStatus == "failed" }.count ?? 0
    }

    private var previewVideoURL: URL? {
        guard let path = vm.activeProject?.inputVideoPath,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
    
    init(vm: ProjectViewModel) {
        self.vm = vm
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Video / timeline canvas stubs
            HStack(spacing: 12) {
                VStack {
                    ZStack {
                        if let previewVideoURL {
                            StableVideoPlayer(url: previewVideoURL)
                        } else {
                            Color.black
                            Text("Source Video Unavailable")
                                .foregroundColor(.textSecondary)
                        }
                        
                        // Subtitle overlay
                        if let seg = vm.selectedSegment {
                            VStack {
                                Spacer()
                                Text(seg.dubText.isEmpty ? seg.sourceText : seg.dubText)
                                    .font(.headline)
                                    .padding(8)
                                    .background(Color.black.opacity(0.75))
                                    .cornerRadius(6)
                                    .padding(.bottom, 20)
                            }
                        }
                    }
                    .frame(height: 240)
                    .cornerRadius(8)
                    
                    // Simple play controls scrubber
                    HStack {
                        Button(action: {
                            if let segment = vm.selectedSegment {
                                vm.previewSegment(segment)
                            } else {
                                vm.isPlaying.toggle()
                            }
                        }) {
                            Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        }
                        Slider(value: $vm.playhead, in: 0...max(1.0, timelineDuration))
                        Text(String(format: "%.2fs", vm.playhead))
                    }
                    .padding(.horizontal, 8)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preflight Diagnostics")
                        .font(.headline)
                    DiagnosticRow(label: "Perfect Timing Fit", value: "\(fitCount) Segments", color: .successColor)
                    DiagnosticRow(label: "Needs Rewrites", value: "\(reviewCount) Segments", color: reviewCount == 0 ? .successColor : .warningColor)
                    DiagnosticRow(label: "Critical Audio Clips", value: "\(failedCount) Failed", color: failedCount == 0 ? .successColor : .errorColor)
                    Spacer()
                }
                .padding()
                .frame(width: 240, height: 260)
                .background(Color.surfaceLow)
                .cornerRadius(8)
            }
            .padding(24)

            Divider().foregroundColor(.outlineBorder)
            
            // Grid Filter header
            HStack {
                Picker("", selection: $filterMode) {
                    Text("All").tag("All")
                    Text("Needs Review").tag("Needs Review")
                    Text("Too Long").tag("Too Long")
                    Text("Too Short").tag("Too Short")
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                
                Spacer()
                
                TextField("Search transcript...", text: $searchString)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Data Grid Header Row (#6)
            HStack(spacing: 0) {
                Text("ID").frame(width: 48, alignment: .leading)
                Text("Start").frame(width: 90, alignment: .leading)
                Text("End").frame(width: 90, alignment: .leading)
                Text("Orig Dur").frame(width: 72, alignment: .leading)
                Text("Gen Dur").frame(width: 72, alignment: .leading)
                Text("Speaker").frame(width: 140, alignment: .leading)
                Text("Voice").frame(width: 110, alignment: .leading)
                Text("Emotion").frame(width: 100, alignment: .leading)
                Text("Source Text").frame(maxWidth: .infinity, alignment: .leading)
                Text("Dub Text").frame(maxWidth: .infinity, alignment: .leading)
                Text("Retry").frame(width: 54, alignment: .center)
                Text("Fit Status").frame(width: 90, alignment: .leading)
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.surfaceMid)
            
            // Data Grid List
            List(selection: Binding<Segment?>(
                get: { vm.selectedSegment },
                set: { vm.setSelectedSegment($0) }
            )) {
                if let project = vm.activeProject {
                    let filtered = project.segments.filter { seg in
                        let matchesSearch = searchString.isEmpty ||
                            seg.sourceText.localizedCaseInsensitiveContains(searchString) ||
                            seg.dubText.localizedCaseInsensitiveContains(searchString)
                        if filterMode == "Needs Review" {
                            return matchesSearch && seg.fitStatus == "needs_review"
                        } else if filterMode == "Too Long" {
                            return matchesSearch && seg.fitStatus == "too_long"
                        } else if filterMode == "Too Short" {
                            return matchesSearch && seg.fitStatus == "too_short"
                        }
                        return matchesSearch
                    }
                    
                    ForEach(filtered) { seg in
                        SegmentRow(segment: seg, speakers: project.speakers, voiceLabel: vm.effectiveVoiceLabel(for: seg), isSelected: vm.selectedSegment?.id == seg.id)
                            .tag(seg)
                            .contextMenu {
                                Button { vm.previewSegment(seg) } label: {
                                    Label("Preview Segment", systemImage: "play.circle")
                                }
                                Button { vm.shortenSegment(seg) } label: {
                                    Label("Shorten Locally", systemImage: "arrow.down.right.and.arrow.up.left")
                                }
                                Button { vm.toggleLock(seg) } label: {
                                    Label(seg.locked ? "Unlock Segment" : "Lock Segment", systemImage: seg.locked ? "lock.open" : "lock")
                                }
                            }
                    }
                }
            }
        }
    }
}

struct DiagnosticRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .foregroundColor(color)
                .fontWeight(.bold)
        }
        .font(.caption)
    }
}

struct SegmentRow: View {
    let segment: Segment
    let speakers: [Speaker]
    let voiceLabel: String
    let isSelected: Bool
    
    private var speakerColor: Color {
        if let sp = speakers.first(where: { $0.speakerId == segment.speakerId }) {
            return Color(hex: sp.color)
        }
        return .brandPrimary
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // ID
            Text(String(format: "%03d", segment.id))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.brandPrimary)
                .frame(width: 48, alignment: .leading)
            
            // Start
            Text(String(format: "%.2f", segment.start))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 90, alignment: .leading)
            
            // End
            Text(String(format: "%.2f", segment.end))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 90, alignment: .leading)
            
            // Orig Dur
            Text(String(format: "%.2f", segment.duration))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 72, alignment: .leading)
            
            // Gen Dur
            Text(segment.generatedDuration != nil ? String(format: "%.2f", segment.generatedDuration!) : "—")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 72, alignment: .leading)
            
            // Speaker (badge with color)
            HStack(spacing: 4) {
                Circle()
                    .fill(speakerColor)
                    .frame(width: 8, height: 8)
                Text(segment.speakerId)
                    .lineLimit(1)
            }
            .font(.system(size: 11))
            .frame(width: 140, alignment: .leading)
            
            // Voice
            Text(voiceLabel)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
            
            // Emotion
            Text(segment.emotion)
                .font(.system(size: 11))
                .frame(width: 100, alignment: .leading)
            
            // Source Text (flex)
            Text(segment.sourceText)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Dub Text (flex)
            Text(segment.dubText.isEmpty ? "—" : segment.dubText)
                .font(.system(size: 11))
                .foregroundColor(.brandPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Retry
            Text("\(segment.retryCount)")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 54, alignment: .center)
            
            // Fit Status (badge)
            Text(segment.fitStatus.uppercased())
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(fitColor.opacity(0.15))
                .foregroundColor(fitColor)
                .cornerRadius(4)
                .frame(width: 90, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.brandPrimary.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
    
    private var fitColor: Color {
        switch segment.fitStatus {
        case "fits", "approved": return .successColor
        case "too_long": return .errorColor
        case "too_short": return .warningColor
        case "needs_review": return .warningColor
        case "failed": return .errorColor
        default: return .textSecondary
        }
    }
}

// MARK: - Screen: Speaker Registry
struct SpeakerRegistryView: View {
    @ObservedObject var vm: ProjectViewModel
    @State private var speakerSearch = ""
    
    private var filteredSpeakers: [Speaker] {
        guard let project = vm.activeProject else { return [] }
        if speakerSearch.isEmpty { return project.speakers }
        return project.speakers.filter {
            $0.displayName.localizedCaseInsensitiveContains(speakerSearch) ||
            ($0.characterName ?? "").localizedCaseInsensitiveContains(speakerSearch)
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Main speaker grid
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Speaker Identity Registry")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Diarization maps unique acoustic signals. Match registry templates with character files.")
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Button("Auto Detect") {
                            vm.runAnalysis()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Search and Add Speaker (#12)
                    HStack(spacing: 12) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.textSecondary)
                            TextField("Search speakers...", text: $speakerSearch)
                                .textFieldStyle(.plain)
                        }
                        .padding(6)
                        .background(Color.surfaceMid)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.outlineBorder, lineWidth: 1))
                        .frame(width: 260)
                        
                        Button(action: { vm.addSpeaker() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Add Speaker")
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                    }
                    
                    if vm.activeProject != nil {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                            ForEach(filteredSpeakers) { speaker in
                                SpeakerCard(speaker: speaker, isSelected: vm.selectedSpeaker?.speakerId == speaker.speakerId) {
                                    vm.selectedSpeaker = speaker
                                }
                            }
                        }
                    } else {
                        ContentUnavailableView("Create project to list speakers", systemImage: "person.2.slash")
                    }
                }
                .padding(24)
            }
            
            // Speaker Inspector Panel (#13)
            if let speaker = vm.selectedSpeaker {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Speaker Details")
                            .font(.headline)
                            .foregroundColor(.brandPrimary)
                        
                        // Identity
                        Group {
                            Text("Identity").font(.subheadline).fontWeight(.bold)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text("Display Name").foregroundColor(.textSecondary); Spacer(); Text(speaker.displayName) }
                                HStack { Text("Character Name").foregroundColor(.textSecondary); Spacer(); Text(speaker.characterName ?? "—") }
                                HStack { Text("Gender Style").foregroundColor(.textSecondary); Spacer(); Text(speaker.genderStyle ?? "—") }
                                HStack { Text("Age Style").foregroundColor(.textSecondary); Spacer(); Text(speaker.ageStyle ?? "—") }
                                HStack { Text("Personality Notes").foregroundColor(.textSecondary); Spacer(); Text(speaker.personalityStyle ?? "—") }
                            }
                            .font(.caption)
                        }
                        
                        Divider().foregroundColor(.outlineBorder)
                        
                        // Statistics
                        Group {
                            Text("Statistics").font(.subheadline).fontWeight(.bold)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text("Segments").foregroundColor(.textSecondary); Spacer(); Text("\(speaker.segmentCount)") }
                                HStack { Text("Total Speech Time").foregroundColor(.textSecondary); Spacer(); Text(String(format: "%.1fs", speaker.totalSpeakingTime)) }
                                HStack { Text("Confidence").foregroundColor(.textSecondary); Spacer(); Text(String(format: "%.0f%%", speaker.confidence * 100)) }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(20)
                }
                .frame(width: 280)
                .background(Color.surfaceLow)
                .overlay(Rectangle().frame(width: 1).foregroundColor(.outlineBorder), alignment: .leading)
            }
        }
    }
}

struct SpeakerCard: View {
    let speaker: Speaker
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(Color(hex: speaker.color))
                        .frame(width: 12, height: 12)
                    Text(speaker.displayName)
                        .fontWeight(.bold)
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Role:")
                            .foregroundColor(.textSecondary)
                        Text(speaker.characterName ?? "Not Assigned")
                    }
                    HStack {
                        Text("Timeline clips:")
                            .foregroundColor(.textSecondary)
                        Text("\(speaker.segmentCount)")
                    }
                    HStack {
                        Text("Speech time:")
                            .foregroundColor(.textSecondary)
                        Text(String(format: "%.1fs", speaker.totalSpeakingTime))
                    }
                }
                .font(.caption)
            }
            .padding(16)
            .background(isSelected ? Color.brandPrimary.opacity(0.1) : Color.surfaceLow)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.brandPrimary : Color.outlineBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Screen: Voice Registry
struct VoiceRegistryView: View {
    @ObservedObject var vm: ProjectViewModel
    @State private var voicePrompts: [String: String] = [:]
    @State private var voiceType = "designed_voice"
    @State private var consentGiven = false
    
    private func bindingForPrompt(speakerId: String) -> Binding<String> {
        Binding<String>(
            get: { voicePrompts[speakerId] ?? "Middle-aged male, nervous but kind, soft official tone." },
            set: { voicePrompts[speakerId] = $0 }
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stable Voice Registry")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Bind consistent voice types. Voice cloning requires legal owner consent.")
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }
            .padding(24)
            
            // Legal consent notice
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(.warningColor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Legal and Safety Compliance Warning").fontWeight(.bold)
                    Text("You must explicitly verify you possess necessary licenses or permissions to utilize cloned or imitated voice stubs.")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                Toggle("Confirm Consent", isOn: $consentGiven)
                    .toggleStyle(.checkbox)
            }
            .padding()
            .background(Color.warningColor.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 24)
            
            // Column headers (#14)
            HStack(spacing: 16) {
                Text("Speaker").fontWeight(.bold).frame(width: 120, alignment: .leading)
                Text("Character").fontWeight(.bold).frame(width: 100, alignment: .leading)
                Text("Prompt Characteristics").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading)
                Text("Voice Type").fontWeight(.bold).frame(width: 100, alignment: .leading)
                Text("Consistency").fontWeight(.bold).frame(width: 90, alignment: .center)
                Text("").frame(width: 70)
            }
            .font(.caption)
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
            .background(Color.surfaceMid)
            
            List {
                if let project = vm.activeProject {
                    ForEach(project.speakers) { sp in
                        HStack(spacing: 16) {
                            Text(sp.displayName)
                                .fontWeight(.bold)
                                .frame(width: 120, alignment: .leading)
                            
                            // Character column (#14)
                            Text(sp.characterName ?? "—")
                                .frame(width: 100, alignment: .leading)
                                .foregroundColor(.textSecondary)
                            
                            // Per-speaker prompt (#15)
                            TextField("Enter prompt characteristics...", text: bindingForPrompt(speakerId: sp.speakerId))
                                .textFieldStyle(.roundedBorder)
                            
                            Picker("", selection: $voiceType) {
                                Text("Designed").tag("designed_voice")
                                Text("Preset").tag("preset_voice")
                                Text("Cloned").tag("cloned_voice")
                            }
                            .frame(width: 100)
                            
                            // Consistency Status column (#14)
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.successColor)
                                .frame(width: 90, alignment: .center)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Screen: AI Director
struct AIDirectorView: View {
    @ObservedObject var vm: ProjectViewModel
    @State private var directorPrompt = "You are the professional dubbing director. Your principal constraint is timing alignment. Adjust dubbed segments to fit their original mouth time boxes, prioritizing compression over literal translation."
    
    private var pendingLinesCount: Int {
        guard let project = vm.activeProject else { return 0 }
        return project.segments.filter { segment in
            let dub = segment.dubText.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = segment.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            return dub.isEmpty || (project.sourceLanguage != project.targetLanguage && dub == source)
        }.count
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Gemma / Gemini Director Console")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("AI adapts timing-aware script, assigns emotions, and configures vocal acting instructions.")
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Status cards (#16 – 4th card added)
                HStack(spacing: 16) {
                    StatusCard(title: "Active Director Model", value: vm.geminiModel, icon: "cpu")
                    StatusCard(title: "Dialogue adaptation status", value: vm.activeProject?.segments.isEmpty == false ? "Ready" : "Pending", icon: "brain")
                    StatusCard(title: "Est. rewrite rate", value: "35% Timing Adjusted", icon: "arrow.left.and.right")
                    StatusCard(title: "Pending Lines", value: "\(pendingLinesCount)", icon: "text.badge.minus")
                }
                
                // Editable director prompt (#17)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Director Core Prompt").fontWeight(.bold)
                    TextEditor(text: $directorPrompt)
                        .frame(height: 80)
                        .padding(4)
                        .background(Color.surfaceLow)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineBorder, lineWidth: 1))
                }
                
                // Batch Controls (#18)
                HStack(spacing: 12) {
                    Button {
                        if let selected = vm.selectedSegment {
                            vm.shortenSegment(selected)
                        } else {
                            vm.log("Select a segment before adapting one line.")
                        }
                    } label: {
                        Label("Adapt Selected", systemImage: "text.cursor")
                    }
                    .buttonStyle(.bordered)
                    
                    Button { vm.runDialogueAdaptation() } label: {
                        Label("Adapt All Pending", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                    
                    Button { vm.shortenTooLongSegments() } label: {
                        Label("Shorten Too-Long", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(.bordered)
                    
                    Button { vm.recheckLocalTiming() } label: {
                        Label("Recheck JSON", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(action: { vm.runDialogueAdaptation() }) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Trigger Global adaptation")
                    }
                    .foregroundColor(.black)
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.brandPrimary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(vm.activeJobStatus == "running")
                
                // Output Table (#19)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Per-Segment Director Output").fontWeight(.bold)
                    
                    HStack(spacing: 0) {
                        Text("Seg ID").frame(width: 54, alignment: .leading)
                        Text("Dub Text").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Emotion").frame(width: 80, alignment: .leading)
                        Text("Qwen Instruction").frame(width: 160, alignment: .leading)
                        Text("Timing").frame(width: 80, alignment: .leading)
                        Text("Review").frame(width: 60, alignment: .center)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textSecondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.surfaceMid)
                    .cornerRadius(4)
                    
                    ScrollView {
                        VStack(spacing: 2) {
                            if let segments = vm.activeProject?.segments {
                                ForEach(segments) { seg in
                                    HStack(spacing: 0) {
                                        Text("\(seg.id)").frame(width: 54, alignment: .leading)
                                        Text(seg.dubText.isEmpty ? "—" : seg.dubText).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(seg.emotion).frame(width: 80, alignment: .leading)
                                        Text(seg.qwenInstruction).lineLimit(1).frame(width: 160, alignment: .leading)
                                        Text(seg.fitStatus).frame(width: 80, alignment: .leading)
                                        let reviewed = seg.fitStatus == "fits" || seg.fitStatus == "approved"
                                        Image(systemName: reviewed ? "checkmark" : (seg.fitStatus == "failed" ? "xmark" : "circle"))
                                            .foregroundColor(reviewed ? .successColor : (seg.fitStatus == "failed" ? .errorColor : .textSecondary))
                                            .frame(width: 60, alignment: .center)
                                    }
                                    .font(.system(size: 10))
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 8)
                                    .background(Color.surfaceLow)
                                    .cornerRadius(4)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
                .padding()
                .background(Color.surfaceLow.opacity(0.5))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineBorder, lineWidth: 1))
            }
            .padding(40)
        }
    }
}

struct StatusCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.brandPrimary)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            Text(value)
                .font(.headline)
                .lineLimit(1)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceLow)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineBorder, lineWidth: 1))
    }
}

// MARK: - Screen: Dubbing (TTS queue)
struct DubbingView: View {
    @ObservedObject var vm: ProjectViewModel
    @State private var audioPreviewMode = "Generated segment only"

    private var generatedCount: Int {
        vm.activeProject?.segments.filter { $0.generatedAudioPath != nil }.count ?? 0
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(vm.ttsProviderDisplayName) Generation Queue")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Processes timing-aware audio synthesis with actor instruction-safety protocols.")
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Speech Synthesis Provider")
                            .font(.headline)
                        Spacer()
                        Button("Open Settings") {
                            vm.sidebarSelection = .settings
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.brandPrimary)
                            .frame(width: 8, height: 8)
                        Text(vm.ttsProviderDisplayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }

                    Text(vm.ttsProviderDetail)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color.surfaceLow)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineBorder, lineWidth: 1))
                
                // Queue dashboard status
                HStack(spacing: 16) {
                    StatusCard(title: "TTS Engine", value: vm.ttsProviderDisplayName, icon: "mic")
                    StatusCard(title: "Generated Clips", value: "\(generatedCount) Stems", icon: "music.note")
                    StatusCard(title: "Active State", value: vm.activeJobStatus, icon: "waveform")
                }
                
                // Generation Controls (#21)
                HStack(spacing: 12) {
                    Button { vm.generateSelectedSegment() } label: {
                        Label("Generate Selected", systemImage: "play.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.selectedSegment == nil || vm.activeJobStatus == "running")
                    
                    Button { vm.runTTSGeneration() } label: {
                        Label("Generate All Pending", systemImage: "waveform.path")
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.activeJobStatus == "running")
                    
                    Button { vm.runTTSGeneration() } label: {
                        Label("Regenerate Failed", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.activeJobStatus == "running")
                    
                    Button { vm.cancelActiveJob() } label: {
                        Label("Stop Queue", systemImage: "stop.circle")
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.errorColor)
                    .disabled(vm.activeJobId == nil)
                }
                
                // Generation Queue Table (#20)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Generation Queue").fontWeight(.bold)
                    
                    HStack(spacing: 0) {
                        Text("Seg ID").frame(width: 54, alignment: .leading)
                        Text("Speaker").frame(width: 110, alignment: .leading)
                        Text("Voice Profile").frame(width: 120, alignment: .leading)
                        Text("Dub Text").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Target Dur").frame(width: 80, alignment: .leading)
                        Text("Gen Dur").frame(width: 80, alignment: .leading)
                        Text("Retry").frame(width: 50, alignment: .center)
                        Text("Status").frame(width: 80, alignment: .leading)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textSecondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.surfaceMid)
                    .cornerRadius(4)
                    
                    ScrollView {
                        VStack(spacing: 2) {
                            if let segments = vm.activeProject?.segments {
                                ForEach(segments) { seg in
                                    HStack(spacing: 0) {
                                        Text("\(seg.id)").frame(width: 54, alignment: .leading)
                                        Text(seg.speakerId).lineLimit(1).frame(width: 110, alignment: .leading)
                                        Text(vm.effectiveVoiceLabel(for: seg)).lineLimit(1).frame(width: 120, alignment: .leading)
                                        Text(seg.dubText.isEmpty ? "—" : String(seg.dubText.prefix(40))).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(String(format: "%.2fs", seg.duration)).frame(width: 80, alignment: .leading)
                                        Text(seg.generatedDuration != nil ? String(format: "%.2fs", seg.generatedDuration!) : "—").frame(width: 80, alignment: .leading)
                                        Text("\(seg.retryCount)").frame(width: 50, alignment: .center)
                                        Text(seg.fitStatus.uppercased())
                                            .foregroundColor(seg.fitStatus == "fits" ? .successColor : (seg.fitStatus == "failed" ? .errorColor : .textSecondary))
                                            .frame(width: 80, alignment: .leading)
                                    }
                                    .font(.system(size: 10))
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 8)
                                    .background(Color.surfaceLow)
                                    .cornerRadius(4)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
                .padding()
                .background(Color.surfaceLow.opacity(0.5))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineBorder, lineWidth: 1))
                
                // Audio Preview Panel (#22)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio Preview").fontWeight(.bold)
                    HStack(spacing: 12) {
                        ForEach(["Generated segment only", "With background", "Final mix preview"], id: \.self) { mode in
                            Button(action: { audioPreviewMode = mode }) {
                                Text(mode)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(audioPreviewMode == mode ? Color.brandPrimary.opacity(0.2) : Color.surfaceHigh)
                                    .foregroundColor(audioPreviewMode == mode ? .brandPrimary : .textSecondary)
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(audioPreviewMode == mode ? Color.brandPrimary : Color.outlineBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
                .background(Color.surfaceLow)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineBorder, lineWidth: 1))
            }
            .padding(40)
        }
    }
}

// MARK: - Screen: Mixing Track view
struct MixingView: View {
    @ObservedObject var vm: ProjectViewModel
    @State private var voiceRemoval = "Medium"
    @State private var bgVolume: Double = 0.0
    @State private var vocalVolume: Double = -24.0
    @State private var dubbedVolume: Double = 0.0
    // Mute/Solo (#23)
    @State private var muteBg = false
    @State private var soloBg = false
    @State private var muteVocal = false
    @State private var soloVocal = false
    @State private var muteDubbed = false
    @State private var soloDubbed = false
    // Ducking (#24)
    @State private var duckingEnabled = true
    @State private var duckingAmount: Double = 6.0
    @State private var duckingAttack: Double = 80.0
    @State private var duckingRelease: Double = 300.0
    // Loudness (#25)
    @State private var targetLoudness = "-16 LUFS Web Video"
    @State private var limiterEnabled = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preservation & Multitrack Mixing")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Separate original vocals and blend background stems with dubbed overlays.")
                        .foregroundColor(.textSecondary)
                }
                
                // Voice Removal / Isolation Settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("Original Voice Separation (Demucs)").fontWeight(.bold)
                    HStack {
                        Picker("Removal strength", selection: $voiceRemoval) {
                            Text("Light").tag("Light")
                            Text("Medium").tag("Medium")
                            Text("Strong").tag("Strong")
                            Text("Manual").tag("Manual")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 320)
                        
                        Spacer()
                        
                        Button("Run Separator") {
                            vm.runSeparation()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if let risk = vm.activeProject?.mix.backgroundDamageRisk {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.warningColor)
                            Text("Background damage risk level is \(risk.uppercased()). Higher strengths may cut ambient effects.")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
                .padding()
                .background(Color.surfaceLow)
                .cornerRadius(8)
                
                // Multitrack Board with Mute/Solo (#23)
                VStack(spacing: 16) {
                    MixerTrackRow(name: "Preserved Background Track", volume: $bgVolume, isMuted: $muteBg, isSolo: $soloBg, icon: "waveform", color: .brandPrimary)
                    MixerTrackRow(name: "Original Voice Residual", volume: $vocalVolume, isMuted: $muteVocal, isSolo: $soloVocal, icon: "waveform.badge.minus", color: .warningColor)
                    MixerTrackRow(name: "Dubbed Voice Over stems", volume: $dubbedVolume, isMuted: $muteDubbed, isSolo: $soloDubbed, icon: "mic.fill", color: .successColor)
                }
                
                // Background Ducking (#24)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Background Ducking").fontWeight(.bold)
                    Toggle("Enable Ducking", isOn: $duckingEnabled)
                        .toggleStyle(.checkbox)
                    if duckingEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Ducking Amount").foregroundColor(.textSecondary)
                                Slider(value: $duckingAmount, in: 0...12)
                                Text(String(format: "%.1f dB", duckingAmount))
                                    .font(.caption).foregroundColor(.textSecondary).frame(width: 50)
                            }
                            HStack {
                                Text("Attack").foregroundColor(.textSecondary)
                                Slider(value: $duckingAttack, in: 10...300)
                                Text(String(format: "%.0f ms", duckingAttack))
                                    .font(.caption).foregroundColor(.textSecondary).frame(width: 50)
                            }
                            HStack {
                                Text("Release").foregroundColor(.textSecondary)
                                Slider(value: $duckingRelease, in: 50...800)
                                Text(String(format: "%.0f ms", duckingRelease))
                                    .font(.caption).foregroundColor(.textSecondary).frame(width: 50)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.surfaceLow)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineBorder, lineWidth: 1))
                
                // Loudness and Mastering (#25)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Loudness and Mastering").fontWeight(.bold)
                    Picker("Target Loudness", selection: $targetLoudness) {
                        Text("-16 LUFS Web Video").tag("-16 LUFS Web Video")
                        Text("-14 LUFS Loud Online").tag("-14 LUFS Loud Online")
                        Text("-23 LUFS Broadcast").tag("-23 LUFS Broadcast")
                    }
                    .pickerStyle(.radioGroup)
                    
                    Toggle("Limiter", isOn: $limiterEnabled)
                        .toggleStyle(.checkbox)
                    
                    HStack {
                        Text("Peak:").foregroundColor(.textSecondary)
                        Text("-1.0 dBTP").font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text("Integrated LUFS:").foregroundColor(.textSecondary)
                        Text(targetLoudness.components(separatedBy: " ").first ?? "—").font(.system(.caption, design: .monospaced))
                    }
                }
                .padding()
                .background(Color.surfaceLow)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineBorder, lineWidth: 1))
                
                Button(action: {
                    if var proj = vm.activeProject {
                        proj.mix.backgroundGainDb = bgVolume
                        proj.mix.vocalStemGainDb = vocalVolume
                        proj.mix.dubbedVoiceGainDb = dubbedVolume
                        proj.mix.duckingEnabled = duckingEnabled
                        proj.mix.duckingAmountDb = duckingAmount
                        proj.mix.duckingAttackMs = duckingAttack
                        proj.mix.duckingReleaseMs = duckingRelease
                        proj.mix.limiterEnabled = limiterEnabled
                        proj.mix.targetLoudness = targetLoudness
                        vm.activeProject = proj
                        vm.runMixing()
                    }
                }) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("Trigger mastered Mix Down")
                    }
                    .foregroundColor(.black)
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.brandPrimary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(vm.activeJobStatus == "running")
            }
            .padding(24)
        }
    }
}

struct MixerTrackRow: View {
    let name: String
    @Binding var volume: Double
    @Binding var isMuted: Bool
    @Binding var isSolo: Bool
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(isMuted ? .textSecondary.opacity(0.4) : color)
                Text(name)
                    .fontWeight(.bold)
                    .foregroundColor(isMuted ? .textSecondary.opacity(0.4) : .textPrimary)
                Spacer()
                
                // Mute/Solo toggles (#23)
                Button(action: { isMuted.toggle() }) {
                    Text("M")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(isMuted ? Color.errorColor : Color.surfaceHigh)
                        .foregroundColor(isMuted ? .white : .textSecondary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                
                Button(action: { isSolo.toggle() }) {
                    Text("S")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(isSolo ? Color.warningColor : Color.surfaceHigh)
                        .foregroundColor(isSolo ? .black : .textSecondary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                
                Text(String(format: "%.1f dB", volume))
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            
            HStack(spacing: 12) {
                // Waveform Mock visualizer
                HStack(spacing: 2) {
                    ForEach(0..<20) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(color.opacity(isMuted ? 0.1 : 0.35))
                            .frame(width: 4, height: CGFloat.random(in: 4...28))
                    }
                }
                .frame(width: 140)
                
                Slider(value: $volume, in: -48...6)
            }
        }
        .padding()
        .background(Color.surfaceLow)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineBorder, lineWidth: 1))
    }
}

// MARK: - Screen: Export
struct ExportScreenView: View {
    @ObservedObject var vm: ProjectViewModel
    @State private var includeStems = false
    @State private var includeSubtitles = true
    @State private var videoFormat = "MP4 H.264"
    @State private var audioFormat = "AAC 320 kbps"
    @State private var burnInSubtitles = false
    
    private var totalDuration: Double {
        vm.activeProject?.segments.reduce(0) { $0 + $1.duration } ?? 0
    }
    private var approvedCount: Int {
        vm.activeProject?.segments.filter { $0.approved || $0.fitStatus == "approved" }.count ?? 0
    }
    private var warningCount: Int {
        vm.activeProject?.segments.filter { $0.fitStatus == "needs_review" || $0.fitStatus == "too_long" || $0.fitStatus == "too_short" }.count ?? 0
    }
    private var hasTooLong: Bool {
        vm.activeProject?.segments.contains { $0.fitStatus == "too_long" } ?? false
    }
    private let pipelineStageOrder = ["Import", "Analysis", "Transcript", "Speakers", "Voices", "AI Director", "Dubbing", "Mixing", "Export"]
    private var mixingDone: Bool {
        guard let stage = vm.activeProject?.pipelineStage,
              let idx = pipelineStageOrder.firstIndex(of: stage),
              let mixIdx = pipelineStageOrder.firstIndex(of: "Mixing") else { return false }
        return idx >= mixIdx
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Export and Render Masters")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Consolidate stems, mux dubbed video streams, and review pipeline preflight checks.")
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Project Summary Card (#26)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project Summary").fontWeight(.bold)
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Project").font(.caption).foregroundColor(.textSecondary)
                            Text(vm.activeProject?.name ?? "—").fontWeight(.semibold)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Duration").font(.caption).foregroundColor(.textSecondary)
                            Text(String(format: "%.1fs", totalDuration)).fontWeight(.semibold)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Target Language").font(.caption).foregroundColor(.textSecondary)
                            Text(vm.activeProject?.targetLanguage ?? "—").fontWeight(.semibold)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Approved").font(.caption).foregroundColor(.textSecondary)
                            Text("\(approvedCount)").fontWeight(.semibold).foregroundColor(.successColor)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Warnings").font(.caption).foregroundColor(.textSecondary)
                            Text("\(warningCount)").fontWeight(.semibold).foregroundColor(.warningColor)
                        }
                    }
                }
                .padding()
                .background(Color.surfaceLow)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineBorder, lineWidth: 1))
                
                // Preflight Checklist (#30)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preflight Checklist").fontWeight(.bold)
                    
                    ChecklistRow(title: "All Dialogue adaptated", checked: vm.activeProject?.segments.isEmpty == false)
                    ChecklistRow(title: "Expressive Qwen TTS clips synthesized", checked: vm.activeProject?.segments.filter { $0.generatedAudioPath != nil }.count == vm.activeProject?.segments.count)
                    ChecklistRow(title: "Background voice isolation finished", checked: vm.activeProject?.mix.backgroundDamageRisk != nil)
                    ChecklistRow(title: "Timing fit acceptable", checked: !hasTooLong)
                    ChecklistRow(title: "Final mix generated", checked: mixingDone)
                }
                .padding()
                .background(Color.surfaceLow)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineBorder, lineWidth: 1))
                
                // Video Format Selector (#27)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Video Format").fontWeight(.bold)
                    Picker("", selection: $videoFormat) {
                        Text("MP4 H.264").tag("MP4 H.264")
                        Text("MP4 H.265").tag("MP4 H.265")
                        Text("MOV ProRes 422").tag("MOV ProRes 422")
                    }
                    .pickerStyle(.radioGroup)
                }
                
                // Audio Format Selector (#28)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio Format").fontWeight(.bold)
                    Picker("", selection: $audioFormat) {
                        Text("AAC 320 kbps").tag("AAC 320 kbps")
                        Text("WAV 24-bit 48kHz").tag("WAV 24-bit 48kHz")
                        Text("FLAC").tag("FLAC")
                    }
                    .pickerStyle(.radioGroup)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Output formats").fontWeight(.bold)
                    Toggle("Include per-speaker stems", isOn: $includeStems)
                    Toggle("Include generated adapted subtitle file", isOn: $includeSubtitles)
                    // Burn-in Subtitles (#29)
                    Toggle("Burn-in subtitles", isOn: $burnInSubtitles)
                }
                
                Button(action: {
                    if var proj = vm.activeProject {
                        proj.export.includeStems = includeStems
                        proj.export.includeSubtitles = includeSubtitles
                        proj.export.videoFormat = videoFormat
                        proj.export.audioFormat = audioFormat
                        proj.export.burnInSubtitles = burnInSubtitles
                        vm.activeProject = proj
                        vm.runExport()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.down.doc")
                        Text("Render Final Dubbed Video")
                    }
                    .foregroundColor(.black)
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.brandPrimary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(vm.activeJobStatus == "running")
            }
            .padding(40)
        }
    }
}

struct ChecklistRow: View {
    let title: String
    let checked: Bool
    
    var body: some View {
        HStack {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .foregroundColor(checked ? .successColor : .textSecondary)
            Text(title)
                .foregroundColor(checked ? .textPrimary : .textSecondary)
            Spacer()
        }
    }
}

// MARK: - Screen: Settings View
struct SettingsScreenView: View {
    @ObservedObject var vm: ProjectViewModel
    @State private var useStructuredJson = true
    @State private var keepTextSeparate = true
    @State private var separationModel = "htdemucs"
    @State private var ffmpegPath = "/usr/local/bin/ffmpeg"

    private var huggingFaceTokenIsEntered: Bool {
        vm.huggingFaceToken.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("hf_")
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Studio Configuration & API Keys")
                    .font(.title2)
                    .fontWeight(.bold)
                
                VStack(spacing: 16) {
                    // API Key field — triggers model reload on change
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gemini API Key").foregroundColor(.textSecondary)
                        SecureField("AI Director credentials Key...", text: $vm.geminiApiKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: vm.geminiApiKey) { _ in
                                vm.loadGeminiModels()
                            }
                    }
                    
                    // Gemini / Gemma Model Picker — auto-loaded from API
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("AI Director Model").foregroundColor(.textSecondary)
                            Spacer()
                            if vm.geminiModelsLoading {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 16, height: 16)
                                Text("Loading models...")
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                            } else if !vm.geminiModelsSource.isEmpty {
                                // Source badge
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(vm.geminiModelsSource == "live_api" ? Color.successColor : Color.warningColor)
                                        .frame(width: 6, height: 6)
                                    Text(vm.geminiModelsSource == "live_api" ? "Live API" : "Offline list")
                                        .font(.caption2)
                                        .foregroundColor(vm.geminiModelsSource == "live_api" ? .successColor : .warningColor)
                                }
                            }
                            Button(action: { vm.loadGeminiModels() }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundColor(.brandPrimary)
                            }
                            .buttonStyle(.plain)
                            .disabled(vm.geminiModelsLoading)
                        }
                        
                        // Always show dropdown — list is pre-seeded and updated live
                        let geminiGroup = vm.geminiModels.filter { $0.provider == "gemini" }
                        let gemmaGroup  = vm.geminiModels.filter { $0.provider == "gemma" }
                        
                        Picker("", selection: $vm.geminiModel) {
                            if !geminiGroup.isEmpty {
                                Section(header: Text("── Gemini ──")) {
                                    ForEach(geminiGroup, id: \.id) { m in
                                        Text(m.display).tag(m.id)
                                    }
                                }
                            }
                            if !gemmaGroup.isEmpty {
                                Section(header: Text("── Gemma ──")) {
                                    ForEach(gemmaGroup, id: \.id) { m in
                                        Text(m.display).tag(m.id)
                                    }
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .labelsHidden()
                    }
                    
                    // Use Structured JSON Output (#31)
                    Toggle("Use Structured JSON Output", isOn: $useStructuredJson)
                        .toggleStyle(.checkbox)
                    
                    // ── TTS Provider ─────────────────────────────────────────
                    Divider().padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Speech Synthesis Provider")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        
                        // Provider picker
                        Picker("", selection: $vm.ttsProvider) {
                            Text("Qwen3-TTS (Local)").tag("qwen")
                            Text("Google Cloud TTS").tag("google")
                            Text("ElevenLabs").tag("elevenlabs")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: vm.ttsProvider) { newValue in
                            if newValue == "google" {
                                vm.loadGoogleVoices()
                            } else if newValue == "elevenlabs" {
                                vm.loadElevenLabsVoices()
                            }
                            Task {
                                try? await vm.syncTTSSettings()
                            }
                        }
                        
                        // ── Qwen ──────────────────────────────────────────
                        if vm.ttsProvider == "qwen" {
                            VStack(alignment: .leading, spacing: 8) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Qwen Voice-Cloning Model").foregroundColor(.textSecondary)
                                    TextField("Qwen3-TTS-12Hz-1.7B-Base-8bit", text: $vm.qwenModel)
                                        .textFieldStyle(.roundedBorder)
                                    Text("Use a Base model for reference-audio cloning. CustomVoice models use preset voices.")
                                        .font(.caption)
                                        .foregroundColor(.textSecondary.opacity(0.75))
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Qwen Local Model Path").foregroundColor(.textSecondary)
                                    HStack {
                                        TextField("Leave empty to download from Hugging Face", text: $vm.qwenLocalPath)
                                            .textFieldStyle(.roundedBorder)
                                        Button("Browse...") {
                                            let panel = NSOpenPanel()
                                            panel.canChooseDirectories = true
                                            panel.canChooseFiles = false
                                            if panel.runModal() == .OK {
                                                if let path = panel.url?.path { vm.qwenLocalPath = path }
                                            }
                                        }
                                    }
                                    Text("Point at an already-downloaded checkpoint directory to synthesize entirely offline.")
                                        .font(.caption)
                                        .foregroundColor(.textSecondary.opacity(0.75))
                                }
                            }
                        }
                        
                        // ── Google Cloud TTS ───────────────────────────────
                        if vm.ttsProvider == "google" {
                            VStack(alignment: .leading, spacing: 8) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Google Cloud API Key").foregroundColor(.textSecondary)
                                    SecureField("AIza...", text: $vm.googleTtsApiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: vm.googleTtsApiKey) { _ in vm.loadGoogleVoices() }
                                }
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Language Code").foregroundColor(.textSecondary)
                                        TextField("en-US", text: $vm.googleTtsLanguageCode)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 100)
                                            .onChange(of: vm.googleTtsLanguageCode) { _ in vm.loadGoogleVoices() }
                                    }
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Voice").foregroundColor(.textSecondary)
                                            Spacer()
                                            if vm.googleTtsVoicesLoading {
                                                ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                                            } else {
                                                Button(action: { vm.loadGoogleVoices() }) {
                                                    Image(systemName: "arrow.clockwise").font(.caption).foregroundColor(.brandPrimary)
                                                }.buttonStyle(.plain)
                                            }
                                        }
                                        if vm.googleTtsVoices.isEmpty {
                                            TextField("en-US-Neural2-F", text: $vm.googleTtsVoiceName)
                                                .textFieldStyle(.roundedBorder)
                                        } else {
                                            Picker("", selection: $vm.googleTtsVoiceName) {
                                                ForEach(vm.googleTtsVoices, id: \.name) { v in
                                                    Text("\(v.name) (\(v.gender))").tag(v.name)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .frame(maxWidth: .infinity)
                                            .labelsHidden()
                                        }
                                    }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Pitch").foregroundColor(.textSecondary).font(.caption)
                                        Spacer()
                                        Text(String(format: "%.1f", vm.googleTtsPitch)).font(.caption).foregroundColor(.brandPrimary)
                                    }
                                    Slider(value: $vm.googleTtsPitch, in: -10...10, step: 0.5)
                                        .tint(.brandPrimary)
                                }
                                Text("Neural2 and Studio voices provide the highest quality for dubbing.")
                                    .font(.caption2).foregroundColor(.textSecondary)
                            }
                            .padding(10)
                            .background(Color.surfaceMid)
                            .cornerRadius(6)
                        }
                        
                        // ── ElevenLabs ────────────────────────────────────
                        if vm.ttsProvider == "elevenlabs" {
                            VStack(alignment: .leading, spacing: 8) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("ElevenLabs API Key").foregroundColor(.textSecondary)
                                    SecureField("sk_...", text: $vm.elevenlabsApiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: vm.elevenlabsApiKey) { _ in vm.loadElevenLabsVoices() }
                                }
                                
                                // Voice picker
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Voice").foregroundColor(.textSecondary)
                                        Spacer()
                                        if vm.elevenlabsVoicesLoading {
                                            ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                                            Text("Loading voices...").font(.caption2).foregroundColor(.textSecondary)
                                        } else {
                                            Text("\(vm.elevenlabsVoices.count) voices").font(.caption2).foregroundColor(.textSecondary)
                                            Button(action: { vm.loadElevenLabsVoices() }) {
                                                Image(systemName: "arrow.clockwise").font(.caption).foregroundColor(.brandPrimary)
                                            }.buttonStyle(.plain)
                                        }
                                    }
                                    if vm.elevenlabsVoices.isEmpty {
                                        TextField("voice_id...", text: $vm.elevenlabsVoiceId)
                                            .textFieldStyle(.roundedBorder)
                                    } else {
                                        Picker("", selection: $vm.elevenlabsVoiceId) {
                                            let premade = vm.elevenlabsVoices.filter { $0.category == "premade" }
                                            let cloned  = vm.elevenlabsVoices.filter { $0.category == "cloned" }
                                            let designed = vm.elevenlabsVoices.filter { $0.category != "premade" && $0.category != "cloned" }
                                            if !premade.isEmpty {
                                                Section(header: Text("── Premade ──")) {
                                                    ForEach(premade, id: \.id) { v in Text(v.name).tag(v.id) }
                                                }
                                            }
                                            if !cloned.isEmpty {
                                                Section(header: Text("── Cloned ──")) {
                                                    ForEach(cloned, id: \.id) { v in Text(v.name).tag(v.id) }
                                                }
                                            }
                                            if !designed.isEmpty {
                                                Section(header: Text("── Designed ──")) {
                                                    ForEach(designed, id: \.id) { v in Text(v.name).tag(v.id) }
                                                }
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .frame(maxWidth: .infinity)
                                        .labelsHidden()
                                    }
                                }
                                
                                // Model picker
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Model").foregroundColor(.textSecondary)
                                    Picker("", selection: $vm.elevenlabsModelId) {
                                        ForEach(vm.elevenlabsModels, id: \.id) { m in
                                            Text(m.name).tag(m.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity)
                                    .labelsHidden()
                                }
                                
                                // Voice settings
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Stability").font(.caption).foregroundColor(.textSecondary)
                                        Spacer()
                                        Text(String(format: "%.2f", vm.elevenlabsStability)).font(.caption).foregroundColor(.brandPrimary)
                                    }
                                    Slider(value: $vm.elevenlabsStability, in: 0...1).tint(.brandPrimary)
                                    
                                    HStack {
                                        Text("Clarity + Similarity").font(.caption).foregroundColor(.textSecondary)
                                        Spacer()
                                        Text(String(format: "%.2f", vm.elevenlabsSimilarityBoost)).font(.caption).foregroundColor(.brandPrimary)
                                    }
                                    Slider(value: $vm.elevenlabsSimilarityBoost, in: 0...1).tint(.brandPrimary)
                                    
                                    HStack {
                                        Text("Style Exaggeration").font(.caption).foregroundColor(.textSecondary)
                                        Spacer()
                                        Text(String(format: "%.2f", vm.elevenlabsStyle)).font(.caption).foregroundColor(.brandPrimary)
                                    }
                                    Slider(value: $vm.elevenlabsStyle, in: 0...1).tint(.brandPrimary)
                                }
                                
                                Text("ElevenLabs Multilingual v2 delivers the highest expressiveness for dubbing.")
                                    .font(.caption2).foregroundColor(.textSecondary)
                            }
                            .padding(10)
                            .background(Color.surfaceMid)
                            .cornerRadius(6)
                        }
                    }
                    
                    Divider().padding(.vertical, 4)

                    // Keep text and instruction separate (#31)
                    Toggle("Keep text and instruction separate", isOn: $keepTextSeparate)
                        .toggleStyle(.checkbox)
                        .disabled(true)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Whisper Model Size").foregroundColor(.textSecondary)
                        Picker("", selection: $vm.whisperModel) {
                            Text("Small").tag("small")
                            Text("Medium").tag("medium")
                            Text("Large-V3").tag("large-v3")
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Whisper Compute Type (#31)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Whisper Compute Type").foregroundColor(.textSecondary)
                        Picker("", selection: $vm.whisperComputeType) {
                            Text("int8").tag("int8")
                            Text("float16").tag("float16")
                            Text("float32").tag("float32")
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Speaker Diarization").font(.headline).foregroundColor(.textPrimary)
                            Spacer()
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(huggingFaceTokenIsEntered ? Color.successColor : Color.warningColor)
                                    .frame(width: 7, height: 7)
                                Text(huggingFaceTokenIsEntered ? "Token entered" : "Token required")
                                    .font(.caption2)
                                    .foregroundColor(huggingFaceTokenIsEntered ? .successColor : .warningColor)
                            }
                        }

                        Text("Hugging Face access token")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        SecureField("Paste a read token beginning with hf_", text: $vm.huggingFaceToken)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Hugging Face access token")

                        HStack(spacing: 16) {
                            Link(destination: URL(string: "https://huggingface.co/pyannote/speaker-diarization-community-1")!) {
                                Label("Accept model access", systemImage: "checkmark.shield")
                            }
                            Link(destination: URL(string: "https://huggingface.co/settings/tokens")!) {
                                Label("Create read token", systemImage: "key")
                            }
                        }
                        .font(.caption)

                        Text("Pyannote model ID")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        TextField("Model repository", text: $vm.diarizationModel)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Pyannote model ID")
                        Picker("Compute", selection: $vm.diarizationDevice) {
                            Text("CPU").tag("cpu")
                            Text("Apple Metal").tag("mps")
                        }
                        .pickerStyle(.segmented)

                        Text("ML Python runtime")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        TextField("Python executable path", text: $vm.mlPythonPath)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Demucs Python path").foregroundColor(.textSecondary)
                        TextField("/usr/local/bin/demucs", text: $vm.demucsPath)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Separation Model (#31)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Separation Model").foregroundColor(.textSecondary)
                        Picker("", selection: $separationModel) {
                            Text("htdemucs").tag("htdemucs")
                            Text("htdemucs_ft").tag("htdemucs_ft")
                            Text("two_stem_vocals").tag("two_stem_vocals")
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // FFmpeg Binary (#31)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FFmpeg Binary").foregroundColor(.textSecondary)
                        HStack {
                            TextField("/usr/local/bin/ffmpeg", text: $ffmpegPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = false
                                panel.canChooseFiles = true
                                if panel.runModal() == .OK {
                                    if let path = panel.url?.path { ffmpegPath = path }
                                }
                            }
                            Button("Test FFmpeg") {
                                vm.log("Testing FFmpeg at path: \(ffmpegPath)")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
                .background(Color.surfaceLow)
                .cornerRadius(8)
                
                Button(action: {
                    let settings: [String: Any] = [
                        "geminiApiKey": vm.geminiApiKey,
                        "geminiModel": vm.geminiModel,
                        "whisperModel": vm.whisperModel,
                        "whisperComputeType": vm.whisperComputeType,
                        "demucsPath": vm.demucsPath,
                        "mlPythonPath": vm.mlPythonPath,
                        "diarizationModel": vm.diarizationModel,
                        "diarizationDevice": vm.diarizationDevice,
                        "huggingFaceToken": vm.huggingFaceToken,
                        "separationModel": separationModel,
                        "ffmpegPath": ffmpegPath,
                        "useStructuredJson": useStructuredJson,
                        // TTS
                        "ttsProvider": vm.ttsProvider,
                        // Qwen
                        "qwenLocalPath": vm.qwenLocalPath,
                        "qwenModel": vm.qwenModel,
                        // Google TTS
                        "googleTtsApiKey": vm.googleTtsApiKey,
                        "googleTtsLanguageCode": vm.googleTtsLanguageCode,
                        "googleTtsVoiceName": vm.googleTtsVoiceName,
                        "googleTtsPitch": vm.googleTtsPitch,
                        // ElevenLabs
                        "elevenlabsApiKey": vm.elevenlabsApiKey,
                        "elevenlabsVoiceId": vm.elevenlabsVoiceId,
                        "elevenlabsModelId": vm.elevenlabsModelId,
                        "elevenlabsStability": vm.elevenlabsStability,
                        "elevenlabsSimilarityBoost": vm.elevenlabsSimilarityBoost,
                        "elevenlabsStyle": vm.elevenlabsStyle,
                    ]
                    Task {
                        vm.persistStudioSettings()
                        try? await DubForgeAPIClient.shared.updateSettings(settings: settings)
                        vm.log("Settings successfully written to backend.")
                    }
                }) {
                    Text("Apply Studio configuration")
                        .foregroundColor(.black)
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.brandPrimary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .onAppear {
            vm.loadGeminiModels()
        }
    }
}

// MARK: - Right Inspector: Segment Inspector
struct InspectorView: View {
    @ObservedObject var vm: ProjectViewModel
    @State private var dubText = ""
    @State private var qwenInstruction = ""
    @State private var emotion = "neutral"
    @State private var emotionIntensity: Double = 50
    @State private var selectedSpeakerId = ""
    @State private var selectedVoiceProfileId = ""
    @State private var bracketWarning = false

    private var requiresTargetLanguageText: Bool {
        guard let project = vm.activeProject,
              let segment = vm.selectedSegment,
              project.sourceLanguage != project.targetLanguage else {
            return false
        }
        let candidate = dubText.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = segment.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty || candidate == source
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Segment Details")
                    .font(.headline)
                    .foregroundColor(.brandPrimary)
                
                if let seg = vm.selectedSegment {
                    VStack(alignment: .leading, spacing: 16) {
                        // Timing Info & comparison bar
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Timing bounds & limits").foregroundColor(.textSecondary).font(.caption)
                            HStack {
                                Text(String(format: "Start: %.2fs", seg.start))
                                Spacer()
                                Text(String(format: "End: %.2fs", seg.end))
                            }
                            .font(.system(.caption, design: .monospaced))
                            
                            // Visual comparison bar
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Original / Generated durations:")
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                                
                                GeometryReader { geo in
                                    VStack(alignment: .leading, spacing: 2) {
                                        // Original Limit
                                        Rectangle()
                                            .fill(Color.outlineBorder)
                                            .frame(width: geo.size.width, height: 6)
                                        // Generated Output
                                        let durationRatio = CGFloat(seg.generatedDuration ?? 0.0) / CGFloat(seg.duration)
                                        let fits = (seg.generatedDuration ?? 0.0) <= seg.duration * 1.05
                                        Rectangle()
                                            .fill(fits ? Color.successColor : Color.errorColor)
                                            .frame(width: min(geo.size.width, geo.size.width * max(0.05, durationRatio)), height: 6)
                                    }
                                }
                                .frame(height: 14)
                            }
                        }
                        
                        Divider().foregroundColor(.outlineBorder)
                        
                        // Speaker Picker (#8)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Speaker").foregroundColor(.textSecondary).font(.caption)
                            Picker("", selection: $selectedSpeakerId) {
                                Text("— None —").tag("")
                                if let speakers = vm.activeProject?.speakers {
                                    ForEach(speakers) { sp in
                                        Text(sp.displayName).tag(sp.speakerId)
                                    }
                                }
                            }
                            .onChange(of: selectedSpeakerId) { newValue in
                                if var updated = vm.selectedSegment {
                                    updated.speakerId = newValue
                                    vm.updateSegment(updated, persist: false)
                                }
                            }
                        }
                        
                        // Voice Profile Picker (#9)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Voice Profile").foregroundColor(.textSecondary).font(.caption)
                            Picker("", selection: $selectedVoiceProfileId) {
                                Text("— Provider Default —").tag("")
                                ForEach(vm.voiceProfileOptions) { option in
                                    Text(option.label).tag(option.id)
                                }
                            }
                            .onChange(of: selectedVoiceProfileId) { newValue in
                                applyVoiceSelection(newValue)
                            }
                        }
                        
                        Divider().foregroundColor(.outlineBorder)
                        
                        // Pickers
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Vocal performance emotions").foregroundColor(.textSecondary).font(.caption)
                            Picker("", selection: $emotion) {
                                Text("Neutral").tag("neutral")
                                Text("Happy").tag("happy")
                                Text("Sad").tag("sad")
                                Text("Angry").tag("angry")
                                Text("Afraid").tag("afraid")
                                Text("Serious").tag("serious")
                            }
                            .onChange(of: emotion) { newValue in
                                if var updated = vm.selectedSegment {
                                    updated.emotion = newValue
                                    vm.updateSegment(updated, persist: false)
                                }
                            }
                        }
                        
                        // Emotion Intensity Slider (#10)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Emotion Intensity").foregroundColor(.textSecondary).font(.caption)
                            HStack {
                                Slider(value: $emotionIntensity, in: 0...100)
                                    .onChange(of: emotionIntensity) { newValue in
                                        if var updated = vm.selectedSegment {
                                            updated.emotionIntensity = newValue
                                            vm.updateSegment(updated, persist: false)
                                        }
                                    }
                                Text(String(format: "%.0f%%", emotionIntensity))
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .frame(width: 36)
                            }
                        }
                        
                        Divider().foregroundColor(.outlineBorder)
                        
                        // Spoken dialogue fields
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Source Dialogue").foregroundColor(.textSecondary).font(.caption)
                            Text(seg.sourceText)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.surfaceLowest)
                                .cornerRadius(6)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Adapted dub text").foregroundColor(.textSecondary).font(.caption)
                            ZStack(alignment: .topLeading) {
                                if dubText.isEmpty {
                                    Text("Enter target-language dialogue...")
                                        .foregroundColor(.textSecondary.opacity(0.7))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 8)
                                }
                                TextEditor(text: $dubText)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .onChange(of: dubText) { newValue in
                                        if var updated = vm.selectedSegment {
                                            updated.dubText = newValue
                                            vm.updateSegment(updated, persist: false)
                                        }
                                        bracketWarning = newValue.contains("[")
                                    }
                            }
                            .frame(height: 60)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.outlineBorder, lineWidth: 1))
                            if bracketWarning {
                                Text("⚠️ Bracket tags may be spoken literally by TTS.")
                                    .font(.caption2)
                                    .foregroundColor(.warningColor)
                            }
                            if requiresTargetLanguageText {
                                HStack {
                                    Text("Translate this line before generating speech.")
                                        .font(.caption2)
                                        .foregroundColor(.warningColor)
                                    Spacer()
                                    Button("Open AI Director") {
                                        vm.sidebarSelection = .director
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption2)
                                }
                            }
                            ForEach(seg.warnings, id: \.self) { warning in
                                Text(warning)
                                    .font(.caption2)
                                    .foregroundColor(.errorColor)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Acting instructions").foregroundColor(.textSecondary).font(.caption)
                                Spacer()
                                Text("Sent as prompt, not spoken!")
                                    .font(.system(size: 9))
                                    .foregroundColor(.warningColor)
                            }
                            TextEditor(text: $qwenInstruction)
                                .frame(height: 60)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.outlineBorder, lineWidth: 1))
                                .onChange(of: qwenInstruction) { newValue in
                                    if var updated = vm.selectedSegment {
                                        updated.qwenInstruction = newValue
                                        vm.updateSegment(updated, persist: false)
                                    }
                                }
                        }
                        
                        Divider().foregroundColor(.outlineBorder)
                        
                        // Action Buttons (#11)
                        VStack(spacing: 8) {
                            Button(action: {
                                if let selected = vm.selectedSegment {
                                    vm.shortenSegment(selected)
                                    if let refreshed = vm.selectedSegment {
                                        populateBindings(from: refreshed)
                                    }
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                                    Text("Shorten Locally")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: {
                                vm.generateSelectedSegment()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Regenerate TTS")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            .background(Color.brandPrimary)
                            .cornerRadius(6)
                            .disabled(requiresTargetLanguageText || vm.activeJobStatus == "running")
                            
                            Button(action: {
                                if let selected = vm.selectedSegment {
                                    vm.approveSegment(selected)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Approve Segment")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .foregroundColor(.black)
                            }
                            .buttonStyle(.plain)
                            .background(Color.successColor)
                            .cornerRadius(6)
                        }
                    }
                    .onAppear {
                        // Populate bindings
                        populateBindings(from: seg)
                    }
                    .onChange(of: seg.id) { _ in
                        if let selected = vm.selectedSegment {
                            populateBindings(from: selected)
                        }
                    }
                    .onChange(of: vm.ttsProvider) { _ in
                        if let selected = vm.selectedSegment {
                            populateBindings(from: selected)
                        }
                    }
                    .onChange(of: vm.googleTtsVoiceName) { _ in
                        if vm.ttsProvider == "google", let selected = vm.selectedSegment {
                            populateBindings(from: selected)
                        }
                    }
                    .onChange(of: vm.elevenlabsVoiceId) { _ in
                        if vm.ttsProvider == "elevenlabs", let selected = vm.selectedSegment {
                            populateBindings(from: selected)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func populateBindings(from segment: Segment) {
        dubText = segment.dubText
        qwenInstruction = segment.qwenInstruction.isEmpty ? "Speak in a natural, adapted tone." : segment.qwenInstruction
        emotion = segment.emotion
        emotionIntensity = segment.emotionIntensity
        selectedSpeakerId = segment.speakerId
        selectedVoiceProfileId = selectedVoiceValue(for: segment)
        bracketWarning = dubText.contains("[")
    }

    private func selectedVoiceValue(for segment: Segment) -> String {
        switch vm.ttsProvider {
        case "google":
            return vm.googleTtsVoiceName
        case "elevenlabs":
            return vm.elevenlabsVoiceId
        default:
            return segment.voiceProfileId
        }
    }

    private func applyVoiceSelection(_ newValue: String) {
        switch vm.ttsProvider {
        case "google":
            guard vm.googleTtsVoiceName != newValue else { return }
            vm.googleTtsVoiceName = newValue
            Task { try? await vm.syncTTSSettings() }
        case "elevenlabs":
            guard vm.elevenlabsVoiceId != newValue else { return }
            vm.elevenlabsVoiceId = newValue
            Task { try? await vm.syncTTSSettings() }
        default:
            if var updated = vm.selectedSegment {
                updated.voiceProfileId = newValue
                vm.updateSegment(updated, persist: false)
            }
        }
    }
}

// MARK: - Bottom Status Bar View
struct BottomStatusBarView: View {
    @ObservedObject var vm: ProjectViewModel
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: vm.activeJobStatus == "running" ? "arrow.triangle.2.circlepath" : "power")
                .foregroundColor(vm.activeJobStatus == "running" ? .brandPrimary : .successColor)
            
            Text(vm.activeJobMessage)
                .font(.caption2)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
            
            if vm.activeJobStatus == "running" {
                ProgressView(value: vm.activeJobProgress, total: 100)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
            }
            
            Spacer()
            
            // Selected Segment Summary (#4)
            if let seg = vm.selectedSegment {
                HStack(spacing: 6) {
                    Text("Segment \(seg.id)")
                    Text("•")
                    Text(seg.speakerId)
                    Text("•")
                    Text(seg.fitStatus)
                }
                .font(.caption2)
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.surfaceMid)
                .cornerRadius(4)
            }
            
            Spacer()
            
            // Tasks and Health buttons (#5)
            HStack(spacing: 8) {
                Button(action: {
                    vm.activeJobMessage = vm.activeJobId.map { "Active task: \($0)" } ?? "No active task"
                    vm.sidebarSelection = .analysis
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Tasks")
                    }
                    .font(.caption2)
                    .foregroundColor(.brandPrimary)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    vm.pingServer()
                    vm.log("Health check requested.")
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.text.square")
                        Text("Health")
                    }
                    .font(.caption2)
                    .foregroundColor(.brandPrimary)
                }
                .buttonStyle(.plain)
                
                // Console shortcut trigger
                Button(action: {
                    openWindow(id: "log-console")
                }) {
                    HStack {
                        Image(systemName: "terminal")
                        Text("Logs Console")
                    }
                    .font(.caption2)
                    .foregroundColor(.brandPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 16)
        }
        .padding(.leading, 16)
    }
}

// MARK: - Sheet view: New Project View
struct NewProjectView: View {
    @ObservedObject var vm: ProjectViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = "My Project Name"
    @State private var src = "English"
    @State private var tgt = "Arabic"
    @State private var videoPath = ""
    @State private var subtitlePath = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create Dub Session")
                .font(.title2)
                .fontWeight(.bold)
            
            Form {
                TextField("Project Name", text: $name)
                TextField("Source Language", text: $src)
                TextField("Target Language", text: $tgt)

                MediaSourcePicker(videoPath: $videoPath, subtitlePath: $subtitlePath)
            }
            .padding()
            
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Initialize Project") {
                    vm.createNewProject(name: name, src: src, tgt: tgt, video: videoPath, subtitle: subtitlePath.isEmpty ? nil : subtitlePath)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(videoPath.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 680, height: 650)
    }
}
