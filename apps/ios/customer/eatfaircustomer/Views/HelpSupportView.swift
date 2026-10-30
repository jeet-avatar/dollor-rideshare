import SwiftUI
import EatFairShared

/**
 * Help & Support View
 * Matches Android HelpSupportScreen for platform parity
 * Provides FAQ, contact options, and support resources
 */

struct HelpSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    @State private var selectedCategory: FAQCategory = .all
    @State private var expandedFAQs: Set<String> = []
    @State private var showLiveChat = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Search Bar
                    searchBar

                    // Contact Us Section
                    contactUsSection

                    // FAQ Categories
                    faqCategoriesSection

                    // FAQ List
                    faqListSection

                    // Still Need Help Card
                    stillNeedHelpCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Theme.lxBg.ignoresSafeArea())
            .navigationTitle("Help & Support")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Theme.lxOrange)
                }
            }
            .sheet(isPresented: $showLiveChat) {
                LiveChatView()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.lxTextMuted)

            TextField("", text: $searchQuery, prompt: Text("Search for help...").foregroundColor(Theme.lxTextMuted))
                .textFieldStyle(.plain)
                .foregroundColor(Theme.lxText)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.lxTextMuted)
                }
            }
        }
        .padding(12)
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.button)
        .overlay(
            RoundedRectangle(cornerRadius: Lx.Radius.button)
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
    }

    // MARK: - Contact Us Section
    private var contactUsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contact Us")
                .font(.headline)
                .foregroundColor(Theme.lxText)

            HStack(spacing: 12) {
                ContactOptionCard(
                    icon: "message.fill",
                    title: "Live Chat",
                    subtitle: AppConfig.shared.supportResponseMinutes.map { "Replies in ~\($0) min" } ?? "Chat with us",
                    color: Theme.lxOrange
                ) {
                    showLiveChat = true
                }

                ContactOptionCard(
                    icon: "envelope.fill",
                    title: "Email",
                    subtitle: AppConfig.shared.supportEmail,
                    color: Theme.lxOrange
                ) {
                    openEmail()
                }

                ContactOptionCard(
                    icon: "phone.fill",
                    title: "Phone",
                    subtitle: AppConfig.shared.supportHoursText ?? "Call us",
                    color: Theme.lxOrange
                ) {
                    openPhone()
                }
            }
        }
    }

    // MARK: - FAQ Categories
    private var faqCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FAQ Categories")
                .font(.headline)
                .foregroundColor(Theme.lxText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FAQCategory.allCases, id: \.self) { category in
                        FAQCategoryChip(
                            category: category,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
            }
        }
    }

    // MARK: - FAQ List
    private var faqListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Frequently Asked Questions")
                .font(.headline)
                .foregroundColor(Theme.lxText)

            VStack(spacing: 8) {
                ForEach(filteredFAQs) { faq in
                    FAQItemView(
                        faq: faq,
                        isExpanded: expandedFAQs.contains(faq.id)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedFAQs.contains(faq.id) {
                                expandedFAQs.remove(faq.id)
                            } else {
                                expandedFAQs.insert(faq.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Still Need Help Card
    private var stillNeedHelpCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle.fill")
                .font(Lx.Typography.icon)
                .foregroundColor(Theme.lxOrange)

            Text("Still need help?")
                .font(.headline)
                .foregroundColor(Theme.lxText)

            Text("Our support team can help with any questions or concerns.")
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                openEmail()
            } label: {
                Text("Contact Support")
                    .fontWeight(.bold)
                    .foregroundColor(Lx.Palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.lxButtonGradient)
                    .cornerRadius(Lx.Radius.button)
                    .shadow(color: Theme.lxOrange.opacity(0.4), radius: 14, y: 6)
            }
        }
        .padding(20)
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Lx.Radius.card)
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
    }

    // MARK: - Filtered FAQs
    private var filteredFAQs: [FAQItem] {
        let categoryFiltered = selectedCategory == .all
            ? allFAQs
            : allFAQs.filter { $0.category == selectedCategory }

        if searchQuery.isEmpty {
            return categoryFiltered
        }

        return categoryFiltered.filter {
            $0.question.localizedCaseInsensitiveContains(searchQuery) ||
            $0.answer.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    // MARK: - Actions
    private func openEmail() {
        if let url = URL(string: "mailto:\(AppConfig.shared.supportEmail)") {
            UIApplication.shared.open(url)
        }
    }

    private func openPhone() {
        let phone = AppConfig.shared.supportPhone.replacingOccurrences(of: "-", with: "")
        if let url = URL(string: "tel:\(phone)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - FAQ Category
enum FAQCategory: String, CaseIterable {
    case all = "All"
    case orders = "Orders"
    case payments = "Payments"
    case account = "Account"
    case delivery = "Rides"

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .orders: return "bag"
        case .payments: return "creditcard"
        case .account: return "person"
        case .delivery: return "car"
        }
    }
}

// MARK: - FAQ Item
struct FAQItem: Identifiable {
    let id: String
    let question: String
    let answer: String
    let category: FAQCategory
}

// MARK: - All FAQs Data
private var allFAQs: [FAQItem] { [
    FAQItem(
        id: "1",
        question: "How do I track my ride?",
        answer: "You can track your ride in real-time from the Trips tab. Once your ride is confirmed, you'll see a map showing your driver's location and estimated arrival time.",
        category: .orders
    ),
    FAQItem(
        id: "2",
        question: "What are the platform fees?",
        answer: "We charge a flat connection fee of \(AppConfig.shared.rideshareFeeSummary), plus a $0.05 CPUC Access for All charge. Drivers pay the same fee tier and charge separately. 100% of tips go directly to drivers.",
        category: .payments
    ),
    FAQItem(
        id: "3",
        question: "How do I change my saved address?",
        answer: "Go to your Profile, then tap 'Saved Addresses'. You can add, edit, or delete addresses. Set your preferred address as default for faster checkout.",
        category: .account
    ),
    FAQItem(
        id: "4",
        question: "Can I cancel my ride?",
        answer: "You can cancel before the ride starts, with no cancellation fee, and your card authorization is released. You cannot cancel once the trip is in progress. If you are not at pickup after the driver has arrived and waited at least 5 minutes, the driver may mark a no-show and your saved card is charged a $5.00 no-show fee.",
        category: .orders
    ),
    FAQItem(
        id: "5",
        question: "How do I add a payment method?",
        answer: "Go to Profile > Payment Methods > Add Card. We accept all major credit and debit cards.",
        category: .payments
    ),
    FAQItem(
        id: "6",
        question: "What if there's an issue with my ride?",
        answer: "Email support@dollor.ai with your trip ID and we will review the issue.",
        category: .orders
    ),
    FAQItem(
        id: "7",
        question: "How do I tip my driver?",
        answer: "You can add a tip during checkout or after your trip. 100% of your tip goes directly to the driver - we never take a cut!",
        category: .delivery
    ),
    FAQItem(
        id: "8",
        question: "How do I delete my account?",
        answer: "Go to Profile > Settings > Delete Account. This action is permanent and will remove all your data including ride history and saved addresses.",
        category: .account
    ),
    FAQItem(
        id: "9",
        question: "Why is my ride taking longer than expected?",
        answer: "Ride times can vary due to traffic, weather, or high demand. You can track your driver in real-time and contact them through the app if needed.",
        category: .delivery
    ),
] }

// MARK: - Contact Option Card
struct ContactOptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(Lx.Typography.title)
                    .foregroundColor(color)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.lxText)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(Theme.lxTextMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.lxSurface)
            .cornerRadius(Lx.Radius.button)
            .overlay(
                RoundedRectangle(cornerRadius: Lx.Radius.button)
                    .stroke(Theme.lxHairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
        }
    }
}

// MARK: - FAQ Category Chip
struct FAQCategoryChip: View {
    let category: FAQCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.caption)
                Text(category.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Theme.lxOrange : Theme.lxSurface)
            .foregroundColor(isSelected ? .white : Theme.lxText)
            .cornerRadius(Lx.Radius.sheet)
            .overlay(
                RoundedRectangle(cornerRadius: Lx.Radius.sheet)
                    .stroke(isSelected ? Color.clear : Theme.lxHairline, lineWidth: 1)
            )
        }
    }
}

// MARK: - FAQ Item View
struct FAQItemView: View {
    let faq: FAQItem
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack {
                    Text(faq.question)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(Theme.lxText)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(Theme.lxOrange)
                }
                .padding(16)
            }

            if isExpanded {
                Text(faq.answer)
                    .font(.subheadline)
                    .foregroundColor(Theme.lxTextSecondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.button)
        .overlay(
            RoundedRectangle(cornerRadius: Lx.Radius.button)
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

// Note: Color extension with init(hex:) is in EatFairShared/Theme.swift

#Preview {
    HelpSupportView()
}
