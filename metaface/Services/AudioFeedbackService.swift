//
//  AudioFeedbackService.swift
//  metaface
//
//  Service for providing audio feedback through Meta glasses speakers.
//  Uses Text-to-Speech to announce age estimation results hands-free.
//

import Foundation
import AVFoundation
import Combine

// MARK: - Speech Configuration
struct SpeechConfiguration {
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    var pitch: Float = 1.0
    var volume: Float = 1.0
    var voice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice(language: "en-US")
    var preUtteranceDelay: TimeInterval = 0.0
    var postUtteranceDelay: TimeInterval = 0.3

    static var `default`: SpeechConfiguration {
        SpeechConfiguration()
    }

    static var fast: SpeechConfiguration {
        SpeechConfiguration(rate: AVSpeechUtteranceDefaultSpeechRate * 1.3)
    }

    static var slow: SpeechConfiguration {
        SpeechConfiguration(rate: AVSpeechUtteranceDefaultSpeechRate * 0.7)
    }
}

// MARK: - Announcement Types
enum AnnouncementType {
    case ageResult(age: Double, confidence: Double)
    case ageRange(low: Int, high: Int)
    case multiplefaces(count: Int, ages: [Double])
    case noFaceDetected
    case scanStarted
    case scanStopped
    case connected(deviceName: String)
    case disconnected
    case error(message: String)
    case custom(message: String)

    var message: String {
        switch self {
        case .ageResult(let age, let confidence):
            let confidenceDesc = confidence > 0.8 ? "high confidence" : confidence > 0.5 ? "moderate confidence" : "low confidence"
            return "Age estimated: \(Int(age)) years, \(confidenceDesc)"

        case .ageRange(let low, let high):
            return "Age range: \(low) to \(high) years"

        case .multiplefaces(let count, let ages):
            let ageStrings = ages.prefix(3).map { "\(Int($0))" }.joined(separator: ", ")
            if count > 3 {
                return "\(count) faces detected. Ages: \(ageStrings), and \(count - 3) more"
            } else {
                return "\(count) faces detected. Ages: \(ageStrings)"
            }

        case .noFaceDetected:
            return "No face detected"

        case .scanStarted:
            return "Scanning started"

        case .scanStopped:
            return "Scanning stopped"

        case .connected(let deviceName):
            return "Connected to \(deviceName)"

        case .disconnected:
            return "Glasses disconnected"

        case .error(let message):
            return "Error: \(message)"

        case .custom(let message):
            return message
        }
    }

    var priority: Int {
        switch self {
        case .error: return 100
        case .connected, .disconnected: return 90
        case .scanStarted, .scanStopped: return 80
        case .ageResult: return 50
        case .multiplefaces: return 50
        case .ageRange: return 40
        case .noFaceDetected: return 30
        case .custom: return 20
        }
    }
}

// MARK: - Audio Feedback Service
@MainActor
class AudioFeedbackService: NSObject, ObservableObject {

    // MARK: - Published Properties
    @Published var isSpeaking = false
    @Published var isEnabled = true
    @Published var configuration: SpeechConfiguration = .default

    // MARK: - Private Properties
    private let synthesizer = AVSpeechSynthesizer()
    private var announcementQueue: [AnnouncementType] = []
    private var lastAnnouncement: Date = .distantPast
    private var minimumInterval: TimeInterval = 2.0 // Minimum time between age announcements
    private var lastAgeAnnounced: Double?

    // Debounce settings to avoid spamming
    private var ageAnnouncementDebounce: TimeInterval = 3.0
    private var significantAgeChange: Double = 5.0

    // MARK: - Initialization
    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    // MARK: - Audio Session Configuration
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Use playback category to ensure audio plays through speakers
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            #if DEBUG
            NSLog("[AudioFeedback] Failed to configure audio session: \(error)")
            #endif
        }
    }

    // MARK: - Public Methods
    func announce(_ type: AnnouncementType) {
        guard isEnabled else { return }

        // For age results, apply debouncing
        if case .ageResult(let age, _) = type {
            guard shouldAnnounceAge(age) else { return }
            lastAgeAnnounced = age
            lastAnnouncement = Date()
        }

        speak(type.message)
    }

    func announceAgeResult(_ result: AgeEstimationResult) {
        guard isEnabled else { return }
        guard shouldAnnounceAge(result.estimatedAge) else { return }

        lastAgeAnnounced = result.estimatedAge
        lastAnnouncement = Date()

        let message = formatAgeMessage(result)
        speak(message)
    }

    func announceMultipleFaces(_ results: [FaceAnalysisResult]) {
        guard isEnabled, !results.isEmpty else { return }

        let ages = results.compactMap { $0.ageEstimation?.estimatedAge }
        guard !ages.isEmpty else { return }

        if ages.count == 1 {
            if let result = results.first?.ageEstimation {
                announceAgeResult(result)
            }
        } else {
            announce(.multiplefaces(count: ages.count, ages: ages))
        }
    }

    func speakCustom(_ message: String) {
        guard isEnabled else { return }
        speak(message)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // MARK: - Configuration
    func setMinimumInterval(_ interval: TimeInterval) {
        minimumInterval = interval
    }

    func setAgeChangeThreshold(_ threshold: Double) {
        significantAgeChange = threshold
    }

    func setVoice(_ voice: AVSpeechSynthesisVoice?) {
        configuration.voice = voice
    }

    func setRate(_ rate: Float) {
        configuration.rate = rate
    }

    // MARK: - Private Methods
    private func shouldAnnounceAge(_ age: Double) -> Bool {
        let timeSinceLastAnnouncement = Date().timeIntervalSince(lastAnnouncement)

        // Always announce if enough time has passed
        if timeSinceLastAnnouncement >= ageAnnouncementDebounce {
            return true
        }

        // Announce if age changed significantly
        if let lastAge = lastAgeAnnounced {
            let ageDifference = abs(age - lastAge)
            if ageDifference >= significantAgeChange {
                return true
            }
        }

        return false
    }

    private func formatAgeMessage(_ result: AgeEstimationResult) -> String {
        let age = Int(result.estimatedAge)
        let confidence = result.confidence

        // Build message based on confidence level
        if confidence >= 0.85 {
            return "Age: \(age) years"
        } else if confidence >= 0.7 {
            return "\(age) years, range \(result.ageRangeLow) to \(result.ageRangeHigh)"
        } else if confidence >= 0.5 {
            return "Approximately \(age) years, low confidence"
        } else {
            return "Uncertain, possibly around \(age) years"
        }
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = configuration.rate
        utterance.pitchMultiplier = configuration.pitch
        utterance.volume = configuration.volume
        utterance.voice = configuration.voice
        utterance.preUtteranceDelay = configuration.preUtteranceDelay
        utterance.postUtteranceDelay = configuration.postUtteranceDelay

        // Stop current speech if speaking
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }

        synthesizer.speak(utterance)
        isSpeaking = true

        #if DEBUG
        NSLog("[AudioFeedback] Speaking: \(text)")
        #endif
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension AudioFeedbackService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}

// MARK: - Voice Options Helper
extension AudioFeedbackService {
    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.hasPrefix("en")
        }
    }

    static var defaultVoice: AVSpeechSynthesisVoice? {
        // Prefer enhanced/premium voices if available
        let voices = availableVoices
        return voices.first { $0.quality == .enhanced } ?? voices.first
    }
}
