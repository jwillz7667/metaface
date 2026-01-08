//
//  VoiceCommandService.swift
//  metaface
//
//  Service for handling voice commands through Meta glasses microphone.
//  Allows hands-free control of face scanning.
//

import Foundation
import Speech
import AVFoundation
import Combine

// MARK: - Voice Commands
enum VoiceCommand: String, CaseIterable, Sendable {
    case startScan = "start scan"
    case stopScan = "stop scan"
    case whatAge = "what age"
    case scanFace = "scan face"
    case howOld = "how old"
    case checkAge = "check age"
    case status = "status"
    case help = "help"

    static func match(_ text: String) -> VoiceCommand? {
        let lowercased = text.lowercased()
        return VoiceCommand.allCases.first { command in
            lowercased.contains(command.rawValue)
        }
    }
}

// MARK: - Voice Command Service
@MainActor
final class VoiceCommandService: NSObject, ObservableObject {

    // MARK: - Published Properties
    @Published var isListening = false
    @Published var isAuthorized = false
    @Published var lastRecognizedText: String = ""
    @Published var lastCommand: VoiceCommand?
    @Published var recognitionError: Error?

    // MARK: - Callbacks
    var onCommand: ((VoiceCommand) -> Void)?

    // MARK: - Private Properties
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var isRestarting = false

    // MARK: - Initialization
    override init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()

        speechRecognizer?.delegate = self
        Task {
            await checkAuthorization()
        }
    }

    // MARK: - Authorization
    func checkAuthorization() async {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    self?.isAuthorized = status == .authorized
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Listening Control
    func startListening() async throws {
        guard isAuthorized else {
            throw NSError(
                domain: "VoiceCommandService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition not authorized"]
            )
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw NSError(
                domain: "VoiceCommandService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognizer not available"]
            )
        }

        // Cancel any ongoing task
        await stopListeningInternal()

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(
                domain: "VoiceCommandService",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"]
            )
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation

        // Get input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.lastRecognizedText = text

                    // Check for commands
                    if let command = VoiceCommand.match(text) {
                        self.lastCommand = command
                        self.onCommand?(command)
                    }
                }

                if let error = error {
                    self.recognitionError = error
                }

                if error != nil || (result?.isFinal ?? false) {
                    // Restart listening for continuous recognition
                    if self.isListening && !self.isRestarting {
                        self.isRestarting = true
                        Task {
                            try? await self.restartListening()
                            await MainActor.run {
                                self.isRestarting = false
                            }
                        }
                    }
                }
            }
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()

        isListening = true
    }

    func stopListening() {
        Task {
            await stopListeningInternal()
        }
    }

    private func stopListeningInternal() async {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        await MainActor.run {
            isListening = false
        }
    }

    private func restartListening() async throws {
        await stopListeningInternal()
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
        try await startListening()
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension VoiceCommandService: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor in
            if !available && self.isListening {
                self.stopListening()
            }
        }
    }
}
