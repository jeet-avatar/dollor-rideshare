import SwiftUI
import Speech
import AVFoundation
import Combine
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "eatffairdelivery", category: "VoiceAssistantManager")

/// VoiceAssistantManager handles speech recognition and text-to-speech
/// Enables hands-free operation for drivers during deliveries
/// Issues #23-26 Fixed: Error handling, task cleanup, guard statements, configurable timeout
class VoiceAssistantManager: NSObject, ObservableObject {
    static let shared = VoiceAssistantManager()

    // MARK: - Published Properties
    @Published var isListening = false
    @Published var transcribedText = ""
    @Published var isSpeaking = false
    @Published var isAvailable = false
    @Published var errorMessage: String?
    @Published var recognizedCommands: [VoiceCommand] = []

    // MARK: - Private Properties
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let speechSynthesizer = AVSpeechSynthesizer()

    // Issue #25: Configurable auto-stop timeout
    private let autoStopTimeout: TimeInterval = 10.0
    private var autoStopWorkItem: DispatchWorkItem?

    // MARK: - Commands
    enum VoiceCommand: String, CaseIterable {
        case navigateToPickup = "navigate to pickup"
        case navigateToDropoff = "navigate to dropoff"
        case markDelivered = "mark delivered"
        case callCustomer = "call customer"
        case sendMessage = "send message"
        case readMessages = "read messages"
        case acceptOrder = "accept order"
        case declineOrder = "decline order"
        case goOnline = "go online"
        case goOffline = "go offline"
        case checkEarnings = "check earnings"
        case help = "help"

        var confirmationMessage: String {
            switch self {
            case .navigateToPickup: return "Opening navigation to pickup location"
            case .navigateToDropoff: return "Opening navigation to drop-off location"
            case .markDelivered: return "Marking delivery as complete"
            case .callCustomer: return "Calling customer now"
            case .sendMessage: return "Ready to send message. What would you like to say?"
            case .readMessages: return "Reading your messages"
            case .acceptOrder: return "Order accepted"
            case .declineOrder: return "Order declined"
            case .goOnline: return "You are now online and receiving orders"
            case .goOffline: return "You are now offline"
            case .checkEarnings: return "Checking your earnings"
            case .help: return "Available commands: navigate to pickup, navigate to dropoff, mark delivered, call customer, send message, read messages, accept order, decline order, go online, go offline, check earnings"
            }
        }
    }

    override init() {
        super.init()
        speechSynthesizer.delegate = self
        checkPermissions()
    }

    /// Issue #24 Fixed: Cancel recognition task on deinit
    deinit {
        autoStopWorkItem?.cancel()
        recognitionTask?.cancel()
        recognitionTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        #if DEBUG
        logger.info("[VoiceAssistantManager] Deinitialized, recognition cancelled")
        #endif
    }

    // MARK: - Permissions
    func checkPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.isAvailable = true
                case .denied, .restricted, .notDetermined:
                    self?.isAvailable = false
                    self?.errorMessage = "Speech recognition not available"
                @unknown default:
                    self?.isAvailable = false
                }
            }
        }

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if !granted {
                    self?.isAvailable = false
                    self?.errorMessage = "Microphone access required"
                }
            }
        }
    }

    // MARK: - Start Listening
    /// Issue #23 Fixed: Show user-facing error alerts
    func startListening() {
        guard isAvailable else {
            DispatchQueue.main.async {
                self.errorMessage = "Voice assistant not available. Please enable speech recognition in Settings."
            }
            return
        }

        if isListening {
            stopListening()
            return
        }

        do {
            try startRecognition()
        } catch {
            // Issue #23: Show meaningful error to user
            DispatchQueue.main.async {
                let errMsg = error.localizedDescription.lowercased()
                if errMsg.contains("permission") || errMsg.contains("denied") {
                    self.errorMessage = "Microphone access denied. Please enable in Settings."
                } else if errMsg.contains("unavailable") || errMsg.contains("not supported") {
                    self.errorMessage = "Voice recognition is not available on this device."
                } else {
                    self.errorMessage = "Voice assistant could not start. Please try again."
                }
            }
            #if DEBUG
            logger.info("[VoiceAssistantManager] startListening error: \(error)")
            #endif
        }
    }

    private func startRecognition() throws {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "VoiceAssistant", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        // Get input node
        let inputNode = audioEngine.inputNode

        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            var isFinal = false

            if let result = result {
                let transcription = result.bestTranscription.formattedString.lowercased()
                DispatchQueue.main.async {
                    self.transcribedText = transcription
                }
                isFinal = result.isFinal

                // Check for commands
                self.processCommand(transcription)
            }

            if error != nil || isFinal {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self.recognitionRequest = nil
                self.recognitionTask = nil

                DispatchQueue.main.async {
                    self.isListening = false
                }
            }
        }

        // Issue #26 Fixed: Guard against nil recognitionRequest before appending
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let request = self?.recognitionRequest else { return }
            request.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()

        DispatchQueue.main.async {
            self.isListening = true
            self.transcribedText = ""
        }

        // Issue #25 Fixed: Configurable auto-stop with cancellable work item
        autoStopWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isListening else { return }
            #if DEBUG
            logger.info("[VoiceAssistantManager] Auto-stopping after \(self.autoStopTimeout)s timeout")
            #endif
            self.stopListening()
        }
        autoStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autoStopTimeout, execute: workItem)
    }

    // MARK: - Stop Listening
    func stopListening() {
        // Issue #25: Cancel auto-stop timer
        autoStopWorkItem?.cancel()
        autoStopWorkItem = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        DispatchQueue.main.async {
            self.isListening = false
        }
    }

    // MARK: - Process Commands
    /// Voice is used for dictation only. No screen acts on spoken commands, so matching them here would
    /// announce actions ("Calling customer now", "Order accepted") that never happen and would cut off dictation.
    private func processCommand(_ text: String) {}

    // MARK: - Text to Speech
    func speak(_ text: String) {
        // Stop any current speech
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        DispatchQueue.main.async {
            self.isSpeaking = true
        }

        speechSynthesizer.speak(utterance)
    }

    func stopSpeaking() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }

    // MARK: - Read Messages
    func readMessages(_ messages: [String]) {
        let combinedText = messages.joined(separator: ". ")
        speak("You have \(messages.count) messages. \(combinedText)")
    }

    // MARK: - Announce Delivery Info
    func announceDelivery(restaurant: String, customer: String, distance: String, earnings: String) {
        let announcement = "New delivery from \(restaurant) to \(customer). Distance: \(distance). Earnings: \(earnings). Say accept order or decline order."
        speak(announcement)
    }

    // MARK: - Navigation Announcement
    func announceNavigation(to destination: String, eta: String) {
        speak("Navigating to \(destination). Estimated arrival: \(eta)")
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension VoiceAssistantManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let voiceCommandRecognized = Notification.Name("voiceCommandRecognized")
}
