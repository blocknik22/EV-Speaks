import Foundation
import AVFoundation

class AudioPlayer: NSObject, ObservableObject {
    private var player: AVAudioPlayer?
    @Published var isPlaying = false
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            print("Audio player session setup successfully")
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    func playAudio(data: Data) {
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                // Stop any existing playback
                await MainActor.run {
                    self?.stop()
                }
                
                // Configure audio session for playback on background thread
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
                
                // Configure and start new playback
                let newPlayer = try AVAudioPlayer(data: data)
                newPlayer.delegate = self
                newPlayer.prepareToPlay()
                
                await MainActor.run {
                    self?.player = newPlayer
                    if newPlayer.play() == true {
                        self?.isPlaying = true
                    }
                }
                print("Started playing audio successfully")
            } catch {
                print("Failed to play audio: \(error)")
                await MainActor.run {
                    self?.isPlaying = false
                }
            }
        }
    }
    
    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.player = nil
            self.isPlaying = false
            print("Audio playback finished")
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("Audio player decode error: \(error)")
            }
            self.player = nil
            self.isPlaying = false
        }
    }
} 