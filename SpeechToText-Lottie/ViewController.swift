//
//  ViewController.swift
//  SpeechToText-Lottie
//
//  Created by Phincon on 26/09/23.
//

import UIKit
import Lottie
import Speech
import Foundation
import AVFoundation
import NaturalLanguage

class ViewController: UIViewController, SFSpeechRecognizerDelegate {
    
    
    @IBOutlet weak var startStopBtn: UIButton!
    @IBOutlet weak var textView: UITextView!
    
    
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recorder: AVAudioRecorder?
    private var lastAudioReceivedTime: Date? = nil
    private var animationView: LottieAnimationView?
    private let silenceThreshold: Float = 0.1
    private let silenceThresholdSeconds: TimeInterval = 1.0
    
    var audioWavePath = UIBezierPath()
    var lang: String = "id-ID"
    var speechText: String?
    var isSoundDetected = false // Melacak apakah suara saat ini terdeteksi
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        startStopBtn.isEnabled = false
        speechRecognizer = SFSpeechRecognizer(locale: Locale.init(identifier: lang))
        speechRecognizer?.delegate = self
        requestSpeechAuthorization()
        self.textView.isHidden = true
    }
    
    func showAnimation() {
        animationView = LottieAnimationView(name: "voice-command-vero")
        animationView?.frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        animationView?.center = self.view.center
        animationView?.contentMode = .scaleAspectFit
        view.addSubview(animationView!)
        animationView?.play()
        animationView?.loopMode = .loop
        
        // Set textView.isHidden menjadi true ketika animasi Lottie ditampilkan
            textView.isHidden = true
    }
    
    
    func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { (authStatus) in
            var isButtonEnabled = false
            
            switch authStatus {
            case .authorized:
                isButtonEnabled = true
                self.isSoundDetected = true
            case .denied:
                isButtonEnabled = false
                print("User denied access to speech recognition")
                
            case .restricted:
                isButtonEnabled = false
                print("Speech recognition restricted on this device")
                
            case .notDetermined:
                isButtonEnabled = false
                print("Speech recognition not yet authorized")
            @unknown default:
                print("Unknown authorization status")
            }
            
            OperationQueue.main.addOperation() {
                self.startStopBtn.isEnabled = isButtonEnabled
            }
        }
    }
    
    @IBAction func startStopAct(_ sender: Any) {
        if audioEngine.isRunning {
            audioEngine.stop()
            recorder?.stop() // Stop the audio recording
            isSoundDetected = false
            hideAnimation()
            recognitionRequest?.endAudio()
            startStopBtn.isEnabled = false
            startStopBtn.setTitle("Listen...", for: .normal)
        } else {
            startRecording()
            startStopBtn.setTitle("Stop", for: .normal)
        }
    }
    
    func startRecording() {
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Mengatur kategori audio sesuai dengan kebutuhan aplikasi Anda
            try audioSession.setCategory(AVAudioSession.Category.record)
            try audioSession.setMode(AVAudioSession.Mode.measurement)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Memulai perekaman audio dengan AVAudioRecorder
            let audioSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let audioURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("audioRecording.m4a")

            recorder = try AVAudioRecorder(url: audioURL, settings: audioSettings)
            recorder?.prepareToRecord()
            recorder?.record()

            // Memulai pengenalan suara
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                fatalError("Unable to create an SFSpeechAudioBufferRecognitionRequest object")
            }
            recognitionRequest.shouldReportPartialResults = true

            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest, resultHandler: { [self] (result, error) in
                var isFinal = false

                if result != nil {
                    if let resultText = result?.bestTranscription.formattedString {
                        let languageIdentifier = NLLanguageRecognizer.dominantLanguage(for: resultText)
                        if let languageCode = languageIdentifier?.rawValue {
                            if languageCode == "id" {
                                print("Indonesian Language")
                            } else if languageCode == "en" {
                                print("English Language")
                            }
                        }
                        self.speechText = resultText
                    }
                    isFinal = (result?.isFinal)!
                    // Set lastAudioReceivedTime saat audio diterima
                    self.lastAudioReceivedTime = Date()
                }
                self.isSoundDetected = (self.lastAudioReceivedTime != nil)
//                self.updateAudioAnimation()

                if error != nil || isFinal {
                    isSoundDetected = false
                    audioEngine.stop()
                    recorder?.stop() // Stop the audio recording

                    let inputNode = self.audioEngine.inputNode
                    inputNode.removeTap(onBus: 0)

                    self.recognitionRequest = nil
                    self.recognitionTask = nil

                    startStopBtn.isEnabled = true

                    // Sembunyikan animasi setelah proses pengenalan selesai
                    hideAnimation()
                }
            })

            // Memasang audio input dari AVAudioRecorder ke SFSpeechAudioBufferRecognitionRequest
            let inputNode = audioEngine.inputNode
            inputNode.removeTap(onBus: 0)
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, when) in
                self.recognitionRequest?.append(buffer)

                // Menghitung amplitudo dari buffer audio
                let bufferArray = Array(UnsafeBufferPointer(start: buffer.floatChannelData?[0], count: Int(buffer.frameLength)))
                let maxAmplitude = bufferArray.reduce(-Float.greatestFiniteMagnitude, { max($0, $1) })

                DispatchQueue.main.async {
                    // Mengatur animasi berdasarkan amplitudo yang diukur.
                    if maxAmplitude < self.silenceThreshold {
                        self.hideLottie()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            if let speechText = self.speechText, !speechText.isEmpty {
                                self.textView.text = speechText
                                self.textView.isHidden = false
                            } else {
                                self.textView.isHidden = false
                            }
                        }
                    } else {
                        self.showAnimation()
                    }
                }
            }

            // Menyiapkan dan memulai AVAudioEngine
            audioEngine.prepare()

            do {
                try audioEngine.start()
            } catch {
                print("audioEngine couldn't start because of an error.")
            }

        } catch {
            print("audioSession properties or AVAudioRecorder couldn't be set due to an error.")
        }
    }
    
    func hideAnimation() {
        if !isSoundDetected {
            hideLottie()
            DispatchQueue.main.async {
                if let speechText = self.speechText, !speechText.isEmpty {
                    self.textView.text = speechText
                    self.textView.isHidden = false
                } else {
                    self.textView.text = "No speech detected."
                    self.textView.isHidden = false
                }
            }
        } else {
            // Sembunyikan animasi jika ada suara yang terdeteksi
            hideLottie()
        }
    }
    
    //hide animation lottie
    func hideLottie(){
        for subview in self.view.subviews {
            if subview is LottieAnimationView {
                subview.removeFromSuperview()
            }
        }
    }

}

