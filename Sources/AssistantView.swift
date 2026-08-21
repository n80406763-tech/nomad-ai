import SwiftUI
import Speech
import AVFoundation

/// ИИ-Ассистент с голосом и музыкой
struct AssistantView: View {
    @StateObject private var vm = AssistantVM()
    @State private var inputText = ""

    var body: some View {
        ZStack {
            // Фоновый градиент
            LinearGradient(colors: [Color(hex: "0A0A0F"), Color(hex: "0D1A2B")],
                           startPoint: .top, endPoint: .bottom)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // История диалога
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(vm.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: vm.messages.count) { _ in
                        if let last = vm.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                // Индикатор печатания
                if vm.isThinking {
                    HStack {
                        Image(systemName: "ellipsis.bubble.fill")
                            .foregroundColor(.cyan)
                        Text("Ассистент думает...")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }

                if let status = vm.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                // Нижняя панель ввода
                VStack(spacing: 10) {
                    Divider().background(Color.gray.opacity(0.3))

                    HStack(spacing: 12) {
                        // Кнопка микрофона
                        Button(action: vm.toggleRecording) {
                            ZStack {
                                Circle()
                                    .fill(vm.isRecording ? Color.red : Color.cyan.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                if vm.isRecording {
                                    Circle()
                                        .stroke(Color.red, lineWidth: 2)
                                        .frame(width: 54, height: 54)
                                        .scaleEffect(vm.isRecording ? 1.1 : 1.0)
                                        .animation(.easeInOut(duration: 0.8).repeatForever(), value: vm.isRecording)
                                }
                                Image(systemName: vm.isRecording ? "stop.fill" : "mic.fill")
                                    .foregroundColor(vm.isRecording ? .white : .cyan)
                                    .font(.title3)
                            }
                        }

                        // Текстовое поле
                        TextField("Спросите что-нибудь...", text: $inputText)
                            .padding(10)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(20)
                            .foregroundColor(.white)
                            .onSubmit { vm.sendText(inputText); inputText = "" }

                        // Кнопка отправки
                        Button(action: { vm.sendText(inputText); inputText = "" }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(inputText.isEmpty ? .gray : .cyan)
                        }
                        .disabled(inputText.isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .background(Color(hex: "0D1A2B"))
            }
        }
        .navigationTitle("Nomad AI")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.setup() }
    }
}

// MARK: - Сообщение
struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp = Date()
}

struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.isUser { Spacer() }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.isUser ? Color.cyan : Color(UIColor.secondarySystemBackground))
                    .foregroundColor(message.isUser ? .black : .white)
                    .cornerRadius(18)
                    .cornerRadius(message.isUser ? 4 : 18, corners: message.isUser ? .topRight : .topLeft)
                Text(message.timestamp.formatted(.dateTime.hour().minute()))
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 4)
            }
            if !message.isUser { Spacer() }
        }
    }
}
