import SwiftUI
import EatFairShared
import os

private let logger = Logger(subsystem: "com.dollorai.customer", category: "DriverChatView")

/// DriverChatView - Chat with driver during a ride (Customer side)
/// Uses REST API: /api/p2p/ride-requests/{id}/chat
struct DriverChatView: View {
    let rideRequestId: Int
    let driverName: String
    let driverPhone: String?

    @StateObject private var safety: ChatSafetyController
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""
    @State private var messages: [RideChatMessage] = []
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool
    @State private var pollingTimer: Timer?

    init(rideRequestId: Int, driverName: String, driverPhone: String?, driverId: Int? = nil) {
        self.rideRequestId = rideRequestId
        self.driverName = driverName
        self.driverPhone = driverPhone
        _safety = StateObject(wrappedValue: ChatSafetyController(
            rideRequestId: rideRequestId,
            otherUserType: "driver",
            otherUserId: driverId,
            otherName: driverName
        ))
    }

    private let quickMessages = [
        "On my way out!",
        "I'll be right there",
        "Where are you exactly?",
        "I'm at the pickup spot",
        "Running a few minutes late",
        "Can you wait a moment?"
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                messagesScrollView
                if safety.isBlocked {
                    ChatBlockedBar(controller: safety)
                } else {
                    quickMessagesBar
                    inputBar
                }
            }
            .background(Theme.lxBg.ignoresSafeArea())
            .chatSafety(safety)
            .navigationTitle(driverName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(Theme.lxOrange)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        if let phone = driverPhone, !phone.isEmpty {
                            Button(action: callDriver) {
                                Image(systemName: "phone.fill")
                                    .foregroundColor(Theme.lxOrange)
                            }
                        }
                        ChatSafetyMenu(controller: safety)
                    }
                }
            }
            .onAppear {
                safety.refreshBlocks()
                loadMessages()
                startPolling()
            }
            .onDisappear {
                stopPolling()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Messages Scroll View

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if isLoading {
                        ProgressView()
                            .padding(.top, 40)
                    } else if let error = errorMessage {
                        errorStateView(error)
                    } else if messages.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(visibleMessages) { message in
                            RideChatBubbleCustomer(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Messages from a blocked driver are hidden on this device.
    private var visibleMessages: [RideChatMessage] {
        safety.isBlocked ? messages.filter { !$0.isFromDriver } : messages
    }

    // MARK: - Error State

    private func errorStateView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Lx.Typography.iconLarge)
                .foregroundColor(Theme.lxOrange)

            Text("Connection Error")
                .font(.headline)
                .foregroundColor(Theme.lxText)

            Text(error)
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                loadMessages()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.lxOrange)
        }
        .padding(.top, 60)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "message.badge.filled.fill")
                .font(Lx.Typography.iconLarge)
                .foregroundColor(Theme.lxTextMuted)

            Text("No messages yet")
                .font(.headline)
                .foregroundColor(Theme.lxText)

            Text("Send a message to \(driverName)!")
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    // MARK: - Quick Messages Bar

    private var quickMessagesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickMessages, id: \.self) { message in
                    Button(action: { sendMessage(message) }) {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(Theme.lxOrange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.lxOrange.opacity(0.12))
                            .cornerRadius(Lx.Radius.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: Lx.Radius.card)
                                    .stroke(Theme.lxHairline, lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Theme.lxSurface)
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

            Button(action: { sendMessage(messageText) }) {
                if isSending {
                    ProgressView()
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                        .foregroundColor(Lx.Palette.onAccent)
                        .frame(width: 44, height: 44)
                        .background(messageText.isEmpty ? AnyShapeStyle(Theme.lxTextMuted) : AnyShapeStyle(Theme.lxButtonGradient))
                        .clipShape(Circle())
                        .shadow(color: messageText.isEmpty ? Color.clear : Theme.lxOrange.opacity(0.4), radius: 10, x: 0, y: 4)
                }
            }
            .disabled(messageText.isEmpty || isSending)
        }
        .padding()
        .background(Theme.lxSurface)
    }

    // MARK: - Actions

    private func loadMessages() {
        isLoading = true
        errorMessage = nil

        P2PAPIService.shared.fetchRideChatMessages(rideRequestId: rideRequestId) { result in
            isLoading = false
            switch result {
            case .success(let fetchedMessages):
                messages = fetchedMessages.sorted { $0.id < $1.id }
                safety.learnOtherUser(from: messages)
                errorMessage = nil
            case .failure(let error):
                logger.info("[DriverChatView] Failed to load messages: \(error)")
                errorMessage = "Failed to load messages"
            }
        }
    }

    private func sendMessage(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        isSending = true
        // Clear the field as soon as the message is on its way; a failed send restores the draft below.
        let typedDraft = messageText
        if text == typedDraft {
            messageText = ""
        }
        isInputFocused = false

        P2PAPIService.shared.sendRideChatMessage(
            rideRequestId: rideRequestId,
            message: trimmedText,
            senderType: "customer"
        ) { result in
            isSending = false
            switch result {
            case .success(let newMessage):
                if !messages.contains(where: { $0.id == newMessage.id }) {
                    messages.append(newMessage)
                }
            case .failure(let error):
                logger.info("[DriverChatView] Failed to send message: \(error)")
                if case P2PAPIError.serverError(let detail) = error {
                    errorMessage = detail
                    if messageText.isEmpty, text == typedDraft {
                        messageText = typedDraft
                    }
                    return
                }
                // A decoding error means the server accepted the message; the poll will show it.
                if !(error is DecodingError), messageText.isEmpty, text == typedDraft {
                    messageText = typedDraft
                }
            }
        }
    }

    private func callDriver() {
        guard let phone = driverPhone, !phone.isEmpty else { return }
        let cleanPhone = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard let url = URL(string: "tel://\(cleanPhone)") else { return }
        UIApplication.shared.open(url)
    }

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            P2PAPIService.shared.fetchRideChatMessages(rideRequestId: rideRequestId) { result in
                if case .success(let fetchedMessages) = result {
                    let sortedMessages = fetchedMessages.sorted { $0.id < $1.id }
                    if sortedMessages.count != messages.count {
                        messages = sortedMessages
                    }
                }
            }
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
}

// MARK: - Chat Bubble (Customer perspective)

private struct RideChatBubbleCustomer: View {
    let message: RideChatMessage

    // In customer app, customer messages are "from me"
    private var isFromMe: Bool {
        !message.isFromDriver
    }

    var body: some View {
        HStack {
            if isFromMe { Spacer() }

            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                Text(message.message)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(isFromMe ? Theme.lxOrange : Theme.lxSurface2)
                    .foregroundColor(isFromMe ? .white : Theme.lxText)
                    .cornerRadius(Lx.Radius.card)

                Text(message.timeText)
                    .font(.caption2)
                    .foregroundColor(Theme.lxTextMuted)
            }

            if !isFromMe { Spacer() }
        }
    }

}
