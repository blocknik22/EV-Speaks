import Foundation
import AVFoundation

class AudioRecorder: NSObject, ObservableObject {
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    @Published var isRecording = false
    @Published var audioData: Data?
    @Published var errorMessage: String?
    
    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("recording.m4a")
    }
    
    override init() {
        super.init()
    }
    
    private func setupAudioSessionForRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            print("Audio session setup for recording")
        } catch {
            print("Failed to set up audio session: \(error)")
            errorMessage = "Failed to set up audio: \(error.localizedDescription)"
        }
    }
    
    private func setupAudioSessionForPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Deactivate session first to prevent conflicts
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            // Set category for playback only (no recording)
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            print("Audio session setup for playback")
        } catch {
            print("Failed to set up audio session: \(error)")
            errorMessage = "Failed to set up audio: \(error.localizedDescription)"
        }
    }
    
    func startRecording() {
        // Request microphone permission
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
            Task { @MainActor in
                if allowed {
                    await self?.initiateRecordingAsync()
                } else {
                    print("Microphone permission denied")
                    self?.errorMessage = "Microphone access denied. Please enable it in Settings."
                }
            }
        }
    }
    
    private func initiateRecordingAsync() async {
        // Set up audio session for recording on background thread
        await Task.detached(priority: .userInitiated) {
            self.setupAudioSessionForRecording()
        }.value
        
        // Remove any existing recording
        try? FileManager.default.removeItem(at: recordingURL)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.delegate = self
            
            if audioRecorder?.prepareToRecord() == true {
                audioRecorder?.record()
                await MainActor.run {
                    isRecording = true
                }
                print("Started recording successfully")
            } else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare recording"])
            }
        } catch {
            print("Could not start recording: \(error)")
            await MainActor.run {
                errorMessage = "Recording failed: \(error.localizedDescription)"
                isRecording = false
            }
        }
    }
    
    func stopRecording() {
        print("Stopping recording...")
        audioRecorder?.stop()
        
        Task.detached(priority: .userInitiated) { [weak self] in
            // Load the recorded audio data on background thread
            do {
                let data = try Data(contentsOf: self?.recordingURL ?? URL(fileURLWithPath: ""))
                await MainActor.run {
                    self?.audioData = data
                    self?.isRecording = false
                }
                print("Successfully loaded audio data: \(data.count) bytes")
            } catch {
                print("Failed to load recorded audio data: \(error)")
                await MainActor.run {
                    self?.errorMessage = "Failed to save recording: \(error.localizedDescription)"
                    self?.audioData = nil
                    self?.isRecording = false
                }
            }
        }
    }
    
    func playRecording() {
        guard let data = audioData else {
            print("No audio data available to play")
            return
        }
        
        // Stop any ongoing recording first to prevent conflicts
        if isRecording {
            stopRecording()
            // Wait a moment for recording to fully stop
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.setupAudioSessionForPlayback()
                self.startPlayback(data: data)
            }
        } else {
            // Set up audio session for playback
            setupAudioSessionForPlayback()
            startPlayback(data: data)
        }
    }
    
    private func startPlayback(data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            
            if audioPlayer?.prepareToPlay() == true {
                audioPlayer?.play()
                print("Started playing audio")
            } else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare audio playback"])
            }
        } catch {
            print("Failed to play recording: \(error)")
            errorMessage = "Playback failed: \(error.localizedDescription)"
        }
    }
    
    func deleteRecording() {
        // Stop any ongoing recording
        if isRecording {
            stopRecording()
        }
        
        // Stop any ongoing playback
        audioPlayer?.stop()
        audioPlayer = nil
        
        // Clear audio data
        audioData = nil
        
        // Remove temporary recording file
        try? FileManager.default.removeItem(at: recordingURL)
        
        print("Recording deleted")
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        DispatchQueue.main.async {
            if flag {
                do {
                    self.audioData = try Data(contentsOf: self.recordingURL)
                    print("Recording finished successfully: \(self.audioData?.count ?? 0) bytes")
                } catch {
                    print("Failed to load recorded audio data: \(error)")
                    self.errorMessage = "Failed to save recording: \(error.localizedDescription)"
                    self.audioData = nil
                }
            } else {
                print("Recording failed to complete successfully")
                self.errorMessage = "Recording failed to complete"
            }
            self.isRecording = false
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("Audio recorder encode error: \(error)")
                self.errorMessage = "Recording error: \(error.localizedDescription)"
            }
            self.isRecording = false
        }
    }
}

extension AudioRecorder: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.audioPlayer = nil
            if !flag {
                print("Audio playback did not finish successfully")
                self.errorMessage = "Playback did not complete successfully"
            }
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("Audio player decode error: \(error)")
                self.errorMessage = "Playback error: \(error.localizedDescription)"
            }
            self.audioPlayer = nil
        }
    }
} 
