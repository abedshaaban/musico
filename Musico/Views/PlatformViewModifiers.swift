import SwiftUI

extension TextField where Label == Text {
    /// Gray placeholder instead of the default accent/link tint (notably on URL fields).
    init(musicoPrompt placeholder: String, text: Binding<String>) {
        self.init("", text: text, prompt: Text(placeholder).foregroundColor(.secondary))
    }
}

extension View {
    /// Primary input text and caret for form fields.
    func musicoFormTextField() -> some View {
        foregroundColor(.primary)
            .tint(.primary)
    }

    @ViewBuilder
    func musicoInsetGroupedListStyle() -> some View {
#if os(iOS)
        listStyle(.insetGrouped)
#else
        self
#endif
    }

    @ViewBuilder
    func musicoStackNavigationStyle() -> some View {
#if os(iOS)
        navigationViewStyle(.stack)
#else
        self
#endif
    }

    @ViewBuilder
    func musicoInlineNavigationTitle() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }

    @ViewBuilder
    func musicoURLKeyboard() -> some View {
#if os(iOS)
        keyboardType(.URL)
            .textInputAutocapitalization(.never)
#else
        self
#endif
    }
}
