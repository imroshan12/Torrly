import SwiftUI

enum Theme {
    /// TorrDroid's colorPrimary (#8BC34A, #9CCC65 at night) via the AccentColor asset.
    static let primary = Color("AccentColor")
    static let primaryDark = Color("PrimaryDark")
    static let cardHeader = Color(.systemGray)
}

/// The round "?" button next to form fields, showing TorrDroid-style help text.
struct HelpButton: View {
    let title: String
    let message: String
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What's this?")
        .alert(title, isPresented: $showing) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

/// Short message shown at the bottom of the screen, like an Android toast.
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.8), in: Capsule())
                    .padding(.bottom, 90)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { self.message = nil }
                    }
            }
        }
        .animation(.easeInOut, value: message)
    }
}

extension View {
    /// Green title bar with white text, like TorrDroid's toolbar.
    func greenNavigationBar() -> some View {
        toolbarBackground(Theme.primary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

    func toast(_ message: Binding<String?>) -> some View { modifier(ToastModifier(message: message)) }
}
