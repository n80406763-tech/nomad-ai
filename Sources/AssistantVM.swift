import Foundation
import Speech
import AVFoundation

@MainActor
class AssistantVM: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isRecording = false
    @Published var isThinking = false

    private lazy var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private lazy var synthesizer = AVSpeechSynthesizer()
    private let musicPlayer = MusicPlayerService.shared

    // Приветственное сообщение
    func setup() {
        guard messages.isEmpty else { return }
        let greeting = "Привет! Я Nomad AI. Могу помочь с маршрутом, найти заправку, включить музыку или просто поговорить. Что хочешь?"
        messages.append(ChatMessage(text: greeting, isUser: false))
        speak(text: greeting)
    }

    // MARK: - Отправить текст
    func sendText(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        messages.append(ChatMessage(text: t, isUser: true))
        processInput(t)
    }

    // MARK: - Голосовой ввод
    func toggleRecording() {
        if isRecording { stopRecording() }
        else { startRecording() }
    }

    private func startRecording() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            guard granted else { return }
            SFSpeechRecognizer.requestAuthorization { status in
                guard status == .authorized else { return }
                DispatchQueue.main.async { self.beginCapture() }
            }
        }
    }

    private func beginCapture() {
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try? audioSession.setActive(true)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        guard let request = recognitionRequest else { return }
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            if let result = result, result.isFinal {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self?.sendText(text)
                    self?.stopRecording()
                }
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0) // Фикс краша при двойном нажатии
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        try? audioEngine.start()
        isRecording = true
    }

    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        isRecording = false
    }

    // MARK: - Обработка запроса
    private func processInput(_ text: String) {
        isThinking = true
        let lower = text.lowercased()

        // --- Интент: МУЗЫКА ---
        if lower.contains("включи") || lower.contains("играй") || lower.contains("поставь") {
            // Извлечь название песни после ключевого слова
            let musicKeywords = ["включи", "играй", "поставь", "запусти"]
            var songName = text
            for kw in musicKeywords {
                if let range = lower.range(of: kw) {
                    songName = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            handleMusicIntent(songName: songName)
            return
        }

        // --- Интент: ЗАПРАВКИ ---
        if lower.contains("заправк") || lower.contains("бензин") || lower.contains("топливо") {
            let reply = "Ищу заправки рядом с вами... Перейдите во вкладку «Поиск» — там уже выбрана категория «Заправки»."
            respond(reply)
            return
        }

        // --- Интент: ОСТАНОВИТЬСЯ / ОТЕЛИ ---
        if lower.contains("отель") || lower.contains("гостиниц") || lower.contains("переночевать") || lower.contains("ночевка") {
            let reply = "Найду ближайшие отели! Открой вкладку «Поиск» и выбери «Отели». Там можно задать радиус до 300 км."
            respond(reply)
            return
        }

        // --- Интент: СЛЕДУЮЩИЙ ПОВОРОТ (пример навигационного ИИ) ---
        if lower.contains("куда") && (lower.contains("ехать") || lower.contains("поворачивать")) {
            let reply = "По активному маршруту продолжайте движение прямо. Следите за синей линией на карте."
            respond(reply)
            return
        }

        // --- Свободный диалог (через простую локальную логику, без тяжёлой модели) ---
        respondWithFallback(text: text)
    }

    private func handleMusicIntent(songName: String) {
        let result = musicPlayer.play(query: songName)
        if result {
            respond("Включаю: «\(songName)»! 🎵")
        } else {
            respond("Не нашёл «\(songName)» в вашей коллекции. Добавьте музыку в папку Nomad через приложение «Файлы».")
        }
    }

    private func respondWithFallback(text: String) {
        // Простой rule-based ответ для офлайн режима (без нейросети)
        let responses: [String: String] = [
            "привет": "Привет! Как дела в дороге? Всё идёт по плану?",
            "как дела": "Всё отлично, слежу за вашим маршрутом! Как едется?",
            "скучно": "Понимаю! Хотите, включу что-нибудь? Скажи «Включи» и название песни.",
            "устал": "Давно за рулём? Может, найти ближайшую заправку или кафе для отдыха?",
            "погода": "К сожалению, без интернета не могу узнать погоду. Но по ощущениям — как там на улице? 😄",
            "сколько ехать": "По активному маршруту оставшееся расстояние показано в правом верхнем углу карты.",
            "спасибо": "Пожалуйста! Я всегда здесь. Счастливого пути! 🚗"
        ]
        let lower = text.lowercased()
        for (key, reply) in responses {
            if lower.contains(key) { respond(reply); return }
        }
        respond("Понял вас! Если нужна помощь с маршрутом, заправками или музыкой — только скажите.")
    }

    private func respond(_ text: String) {
        isThinking = false
        messages.append(ChatMessage(text: text, isUser: false))
        speak(text: text)
    }

    private func speak(text: String) {
        synthesizer.stopSpeaking(at: .word)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ru-RU")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.05
        synthesizer.speak(utterance)
    }
}
