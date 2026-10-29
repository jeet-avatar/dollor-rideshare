#if canImport(UIKit)
import SafariServices
import SwiftUI

/// In-app browser (SFSafariViewController). Use instead of UIApplication.open for any web page
/// the user reaches from the app (terms, privacy, onboarding, background-check invitation) so
/// the user is never sent out to the Safari app.
public struct SafariView: UIViewControllerRepresentable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    public func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

public extension View {
    /// Presents `url` in an in-app Safari sheet while the binding is non-nil.
    func inAppBrowser(url: Binding<URL?>) -> some View {
        sheet(isPresented: Binding(
            get: { url.wrappedValue != nil },
            set: { isPresented in
                if !isPresented { url.wrappedValue = nil }
            }
        )) {
            if let pageURL = url.wrappedValue {
                SafariView(url: pageURL).ignoresSafeArea()
            }
        }
    }
}
#endif
