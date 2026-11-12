import Foundation
import AVFoundation

/// تسجيل الصوت.
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var level: Float = 0
    @Published var error: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileName = ""

    @MainActor
    func start() async -> Bool {
        error = nil
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            error = tr("اسمح للتطبيق باستخدام المايك من الإعدادات ← ذاكر.", "Allow microphone access in Settings → Zaker.")
            return false
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            fileName = UUID().uuidString + ".m4a"
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let r = try AVAudioRecorder(url: MediaFiles.audioDir.appendingPathComponent(fileName), settings: settings)
            r.isMeteringEnabled = true
            guard r.record() else {
                error = tr("ما قدرت أبدأ التسجيل.", "Couldn't start recording.")
                return false
            }
            recorder = r
            isRecording = true
            elapsed = 0
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let r = self.recorder else { return }
                r.updateMeters()
                self.elapsed = r.currentTime
                self.level = max(0, (r.averagePower(forChannel: 0) + 60) / 60)
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// يوقف التسجيل ويرجع اسم الملف ومدته.
    func stop() -> (fileName: String, duration: Double)? {
        guard let r = recorder else { return nil }
        let d = r.currentTime
        r.stop()
        timer?.invalidate()
        timer = nil
        recorder = nil
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return (fileName, d)
    }
}

/// تشغيل التسجيلات.
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playingFile: String?
    @Published var progress: Double = 0
    @Published var isPlaying = false

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(_ url: URL) {
        if playingFile == url.lastPathComponent, let p = player {
            if p.isPlaying { p.pause(); isPlaying = false } else { p.play(); isPlaying = true }
            return
        }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
            playingFile = url.lastPathComponent
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let p = self.player, p.duration > 0 else { return }
                self.progress = p.currentTime / p.duration
            }
        } catch {
            stop()
        }
    }

    func seek(_ fraction: Double) {
        guard let p = player else { return }
        p.currentTime = p.duration * fraction
        progress = fraction
    }

    func stop() {
        player?.stop()
        player = nil
        timer?.invalidate()
        timer = nil
        playingFile = nil
        isPlaying = false
        progress = 0
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stop()
    }
}

extension TimeInterval {
    var clock: String {
        let t = Int(self)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
