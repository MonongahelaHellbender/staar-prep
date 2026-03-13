import Foundation
import AVFoundation
import Speech
import Combine

class AudioService: NSObject, ObservableObject {
    @Published var isListening: Bool = false
    @Published var transcribedText: String = ""
    @Published var audioLevel: Float = 0.0
    @Published var permissionStatus: PermissionStatus = .notDetermined

    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var levelTimer: Timer?

    enum PermissionStatus {
        case notDetermined, authorized, denied
    }

    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.delegate = self
        checkPermissions()
    }

    // MARK: - Permissions

    func checkPermissions() {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let audioStatus = AVAudioSession.sharedInstance().recordPermission

        if speechStatus == .authorized && audioStatus == .granted {
            permissionStatus = .authorized
        } else if speechStatus == .denied || audioStatus == .denied {
            permissionStatus = .denied
        }
    }

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            AVAudioSession.sharedInstance().requestRecordPermission { audioGranted in
                DispatchQueue.main.async {
                    let granted = speechStatus == .authorized && audioGranted
                    self?.permissionStatus = granted ? .authorized : .denied
                    completion(granted)
                }
            }
        }
    }

    // MARK: - Listening Control

    func startListening() {
        guard permissionStatus == .authorized else {
            requestPermissions { [weak self] granted in
                if granted { self?.startListening() }
            }
            return
        }

        if isListening {
            stopListening()
            return
        }

        do {
            try beginListening()
        } catch {
            print("Audio service error: \(error)")
        }
    }

    func stopListening() {
        stopRecognition()
        isListening = false
        silenceTimer?.invalidate()
        levelTimer?.invalidate()
        audioLevel = 0.0
    }

    private func beginListening() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        audioEngine = engine

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateAudioLevel(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
        isListening = true

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                DispatchQueue.main.async {
                    self.transcribedText = result.bestTranscription.formattedString
                }
                self.resetSilenceTimer()
            }

            if error != nil || result?.isFinal == true {
                DispatchQueue.main.async {
                    self.stopListening()
                }
            }
        }

        startLevelMonitoring()
    }

    private func stopRecognition() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - Silence Detection

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            // Silence for 3 seconds - stop recognition but keep transcript
            DispatchQueue.main.async {
                self?.stopListening()
            }
        }
    }

    // MARK: - Audio Level

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride)
            .map { channelDataValue[$0] }
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        let avgPower = 20 * log10(rms)
        let normalizedLevel = max(0, min(1, (avgPower + 60) / 60))

        DispatchQueue.main.async {
            self.audioLevel = normalizedLevel
        }
    }

    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            // Level updates happen in the tap callback above
            if !(self?.isListening ?? false) {
                self?.levelTimer?.invalidate()
            }
        }
    }

    // MARK: - Always-On Mode

    func startContinuousListening() {
        // Restart recognition after it ends to create continuous listening
        startListening()
    }
}

extension AudioService: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available && isListening {
            stopListening()
        }
    }
}
