import SwiftUI
import EatFairShared

/// LiveChatView - Deterministic rule-based text support chat
/// Connects to POST /api/support/chat backend endpoint
/// Simple request/response pattern (no polling needed)
struct LiveChatView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [(id: UUID, text: String, isFromUser: Bool)] = []
    @State private var messageText = ""
    @State private var isLoading = false
    @FocusState private var isInputFocused: Bool

    private let suggestions = [
        "Where is my ride?",
        "Cancel my ride",
        "Refund request",
        "Ride issue",
        "Ride status",
        "Pricing info"
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                messagesScrollView
                if !isLoading {
                    inputBar
                }
            }
            .background(Theme.lxBg.ignoresSafeArea())
            .navigationTitle("Live Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(Theme.lxOrange)
                }
            }
            .onAppear {
                // Add initial AI greeting
                if messages.isEmpty {
                    messages.append((
                        id: UUID(),
                        text: "Hi! I'm Dollor Support. I can help you check order status, cancel orders, check refund eligibility, and more. What do you need help with?",
                        isFromUser: false
                    ))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Messages Scroll View

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Quick suggestion buttons (show only before user sends first message)
                    if messages.count <= 1 {
                        suggestionsView
                    }

                    ForEach(messages, id: \.id) { message in
                        ChatBubble(text: message.text, isFromUser: message.isFromUser)
                            .id(message.id)
                    }

                    if isLoading {
                        HStack {
                            TypingIndicator()
                            Spacer()
                        }
                        .padding(.horizontal)
                        .id("typing")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: isLoading) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                if isLoading {
                    proxy.scrollTo("typing", anchor: .bottom)
                } else if let lastMessage = messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Suggestions View

    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick topics")
                .font(.caption)
                .foregroundColor(Theme.lxTextMuted)
                .padding(.horizontal, 4)

            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(action: { sendSuggestion(suggestion) }) {
                        Text(suggestion)
                            .font(.subheadline)
                            .foregroundColor(Theme.lxText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Theme.lxSurface2)
                            .cornerRadius(Lx.Radius.sheet)
                            .overlay(
                                RoundedRectangle(cornerRadius: Lx.Radius.sheet)
                                    .stroke(Theme.lxHairline, lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("", text: $messageText, prompt: Text("Type a message...").foregroundColor(Theme.lxTextMuted))
                .textFieldStyle(.plain)
                .foregroundColor(Theme.lxText)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.lxSurface2)
                .cornerRadius(Lx.Radius.sheet)
                .overlay(
                    RoundedRectangle(cornerRadius: Lx.Radius.sheet)
                        .stroke(Theme.lxHairline, lineWidth: 1)
                )
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit {
                    sendCurrentMessage()
                }

            Button(action: sendCurrentMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.title3)
                    .foregroundColor(Lx.Palette.onAccent)
                    .frame(width: 44, height: 44)
                    .background(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.lxTextMuted : Theme.lxOrange)
                    .clipShape(Circle())
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
        .padding()
        .background(Theme.lxSurface)
    }

    // MARK: - Actions

    private func sendSuggestion(_ suggestion: String) {
        messageText = suggestion
        sendCurrentMessage()
    }

    private func sendCurrentMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Append user message
        messages.append((id: UUID(), text: text, isFromUser: true))
        messageText = ""
        isLoading = true

        // Call AI support endpoint
        P2PAPIService.shared.sendSupportChatMessage(message: text) { result in
            isLoading = false
            switch result {
            case .success(let aiResponse):
                messages.append((id: UUID(), text: aiResponse, isFromUser: false))
            case .failure:
                messages.append((
                    id: UUID(),
                    text: "Sorry, I couldn't process that. Please try again.",
                    isFromUser: false
                ))
            }
        }
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let text: String
    let isFromUser: Bool

    var body: some View {
        HStack {
            if isFromUser { Spacer(minLength: 60) }

            VStack(alignment: isFromUser ? .trailing : .leading) {
                if !isFromUser {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundColor(Theme.lxOrange)
                        Text("Dollor Support")
                            .font(.caption2)
                            .foregroundColor(Theme.lxTextMuted)
                    }
                }

                Text(text)
                    .font(.subheadline)
                    .foregroundColor(isFromUser ? .white : Theme.lxText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(isFromUser ? Theme.lxOrange : Theme.lxSurface2)
                    .cornerRadius(Lx.Radius.card)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }

            if !isFromUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var dotOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundColor(Theme.lxOrange)

            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.lxTextMuted)
                    .frame(width: 8, height: 8)
                    .offset(y: dotOffset)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: dotOffset
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.lxSurface2)
        .cornerRadius(Lx.Radius.card)
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .onAppear { dotOffset = -4 }
    }
}

// Note: FlowLayout is defined in FlowLayout.swift and reused here

#Preview {
    LiveChatView()
}
