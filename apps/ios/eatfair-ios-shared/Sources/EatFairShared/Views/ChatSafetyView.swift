import SwiftUI

/// Report / block safeguards for ride chat (App Store Guideline 1.2, Google Play UGC policy).
/// One controller per chat screen. It owns a single `presentation` (report form OR block
/// confirmation, never both) plus a transient banner, so a chat screen never stacks alerts and sheets.

public enum ChatReportReason: String, CaseIterable, Identifiable {
    case harassment
    case inappropriate
    case spam
    case safety
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .harassment: return "Harassment"
        case .inappropriate: return "Inappropriate content"
        case .spam: return "Spam"
        case .safety: return "Safety concern"
        case .other: return "Other"
        }
    }
}

public final class ChatSafetyController: ObservableObject {
    public struct Banner: Equatable, Identifiable {
        public let id = UUID()
        public let text: String
        public let isError: Bool
    }

    public enum Presentation: String, Identifiable {
        case report
        case blockConfirm

        public var id: String { rawValue }
    }

    @Published public var presentation: Presentation?
    @Published public var banner: Banner?
    @Published public private(set) var isBlocked = false
    @Published public private(set) var isWorking = false

    private let rideRequestId: Int
    /// "customer" or "driver": the OTHER participant in this chat.
    private let otherUserType: String
    private var otherUserId: Int?
    public let otherName: String

    public init(rideRequestId: Int, otherUserType: String, otherUserId: Int?, otherName: String) {
        self.rideRequestId = rideRequestId
        self.otherUserType = otherUserType
        self.otherUserId = otherUserId
        self.otherName = otherName
    }

    /// Fallback when the caller did not know the other user's id: learn it from their messages.
    public func learnOtherUser(from messages: [RideChatMessage]) {
        guard otherUserId == nil,
              let theirs = messages.first(where: { $0.senderType == otherUserType }) else { return }
        otherUserId = theirs.senderId
        refreshBlocks()
    }

    public func refreshBlocks() {
        guard let otherUserId = otherUserId else { return }
        P2PAPIService.shared.fetchChatBlocks { [weak self] result in
            guard let self = self, case .success(let blocks) = result else { return }
            self.isBlocked = blocks.contains { $0.userType == self.otherUserType && $0.userId == otherUserId }
        }
    }

    public func submitReport(reason: ChatReportReason, details: String) {
        isWorking = true
        P2PAPIService.shared.reportChat(
            rideRequestId: rideRequestId,
            reason: reason.rawValue,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines)
        ) { [weak self] result in
            guard let self = self else { return }
            self.isWorking = false
            switch result {
            case .success:
                self.presentation = nil
                self.banner = Banner(text: "Thanks. Your report was sent and our team will review it.", isError: false)
            case .failure(let error):
                self.presentation = nil
                self.banner = Banner(text: error.userMessage, isError: true)
            }
        }
    }

    public func setBlocked(_ block: Bool) {
        guard let otherUserId = otherUserId else {
            presentation = nil
            banner = Banner(text: "You can block \(otherName) once they have sent a message.", isError: true)
            return
        }
        isWorking = true
        P2PAPIService.shared.setChatBlock(block: block, userType: otherUserType, userId: otherUserId) { [weak self] result in
            guard let self = self else { return }
            self.isWorking = false
            self.presentation = nil
            switch result {
            case .success:
                self.isBlocked = block
                let text = block ? "\(self.otherName) is blocked. You won't receive their messages." : "\(self.otherName) is unblocked."
                self.banner = Banner(text: text, isError: false)
            case .failure(let error):
                self.banner = Banner(text: error.userMessage, isError: true)
            }
        }
    }
}

// MARK: - Menu

/// Ellipsis menu for a chat navigation bar.
public struct ChatSafetyMenu: View {
    @ObservedObject var controller: ChatSafetyController

    public init(controller: ChatSafetyController) {
        self.controller = controller
    }

    public var body: some View {
        Menu {
            Button {
                controller.presentation = .report
            } label: {
                Label("Report", systemImage: "flag")
            }
            if controller.isBlocked {
                Button {
                    controller.setBlocked(false)
                } label: {
                    Label("Unblock", systemImage: "hand.raised.slash")
                }
            } else {
                Button(role: .destructive) {
                    controller.presentation = .blockConfirm
                } label: {
                    Label("Block user", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundColor(Lx.Palette.orange)
        }
        .accessibilityLabel("Chat options")
    }
}

/// Replaces the message input while the other person is blocked.
public struct ChatBlockedBar: View {
    @ObservedObject var controller: ChatSafetyController

    public init(controller: ChatSafetyController) {
        self.controller = controller
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text("You blocked \(controller.otherName).")
                .font(.subheadline)
                .foregroundColor(Lx.Palette.textSecondary)
            Spacer()
            Button("Unblock") { controller.setBlocked(false) }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Lx.Palette.orange)
                .disabled(controller.isWorking)
        }
        .padding()
        .background(Lx.Palette.surface)
    }
}

// MARK: - Presentation (single sheet) and banner

private struct ChatSafetyModifier: ViewModifier {
    @ObservedObject var controller: ChatSafetyController

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) { bannerView }
            .animation(.easeInOut(duration: 0.2), value: controller.banner)
            .sheet(item: $controller.presentation) { presentation in
                switch presentation {
                case .report:
                    ChatReportSheet(controller: controller)
                case .blockConfirm:
                    ChatBlockConfirmSheet(controller: controller)
                }
            }
    }

    @ViewBuilder
    private var bannerView: some View {
        if let banner = controller.banner {
            Text(banner.text)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(banner.isError ? Lx.Palette.error : Lx.Palette.success.opacity(0.95))
                .cornerRadius(12)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .shadow(radius: 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { controller.banner = nil }
                .task(id: banner.id) {
                    try? await Task.sleep(nanoseconds: banner.isError ? 6_000_000_000 : 4_000_000_000)
                    if controller.banner?.id == banner.id { controller.banner = nil }
                }
        }
    }
}

public extension View {
    /// Attaches the report/block sheet and success/error banner for `controller` to a chat screen.
    func chatSafety(_ controller: ChatSafetyController) -> some View {
        modifier(ChatSafetyModifier(controller: controller))
    }
}

// MARK: - Sheets

private struct ChatReportSheet: View {
    @ObservedObject var controller: ChatSafetyController
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ChatReportReason = .harassment
    @State private var details = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Why are you reporting \(controller.otherName)?")
                        .font(.headline)
                        .foregroundColor(Lx.Palette.text)

                    VStack(spacing: 0) {
                        ForEach(ChatReportReason.allCases) { option in
                            Button {
                                reason = option
                            } label: {
                                HStack {
                                    Text(option.title)
                                        .foregroundColor(Lx.Palette.text)
                                    Spacer()
                                    if reason == option {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Lx.Palette.orange)
                                    }
                                }
                                .padding()
                            }
                            if option != ChatReportReason.allCases.last {
                                Divider().overlay(Lx.Palette.hairline)
                            }
                        }
                    }
                    .background(Lx.Palette.surface)
                    .cornerRadius(Lx.Radius.button)

                    Text("Details (optional)")
                        .font(.subheadline)
                        .foregroundColor(Lx.Palette.textSecondary)
                    TextEditor(text: $details)
                        .hiddenScrollBackground()
                        .foregroundColor(Lx.Palette.text)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Lx.Palette.surface2)
                        .cornerRadius(Lx.Radius.button)

                    Text("If someone is in immediate danger, call 911.")
                        .font(.caption)
                        .foregroundColor(Lx.Palette.textMuted)

                    Button {
                        controller.submitReport(reason: reason, details: details)
                    } label: {
                        Group {
                            if controller.isWorking {
                                ProgressView().tint(Lx.Palette.onAccent)
                            } else {
                                Text("Submit Report").fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(Lx.Palette.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Lx.Palette.buttonGradient)
                        .cornerRadius(Lx.Radius.button)
                    }
                    .disabled(controller.isWorking)
                }
                .padding()
            }
            .background(Lx.Palette.bg.ignoresSafeArea())
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Lx.Palette.orange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ChatBlockConfirmSheet: View {
    @ObservedObject var controller: ChatSafetyController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.largeTitle)
                .foregroundColor(Lx.Palette.error)
            Text("Block \(controller.otherName)?")
                .font(.title3.weight(.semibold))
                .foregroundColor(Lx.Palette.text)
            Text("You will no longer receive messages from \(controller.otherName). You can unblock them later from this chat.")
                .font(.subheadline)
                .foregroundColor(Lx.Palette.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                controller.setBlocked(true)
            } label: {
                Group {
                    if controller.isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text("Block").fontWeight(.semibold)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Lx.Palette.error)
                .cornerRadius(Lx.Radius.button)
            }
            .disabled(controller.isWorking)

            Button("Cancel") { dismiss() }
                .foregroundColor(Lx.Palette.orange)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Lx.Palette.bg.ignoresSafeArea())
        .compactSheetDetent()
        .preferredColorScheme(.dark)
    }
}

private extension View {
    @ViewBuilder
    func hiddenScrollBackground() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func compactSheetDetent() -> some View {
        if #available(iOS 16.0, *) {
            presentationDetents([.height(320)])
        } else {
            self
        }
    }
}
