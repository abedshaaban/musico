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

    /// Plain list rows so swipe actions use full-height rectangular backgrounds.
    @ViewBuilder
    func musicoPlainLibraryListStyle() -> some View {
#if os(iOS)
        listStyle(.plain)
#else
        self
#endif
    }

    /// Makes a library row tappable without wrapping it in `Button`, so trailing
    /// swipe actions render as full-height iOS-style actions instead of compact circles.
    func musicoLibraryRowTap(action: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    func musicoFullBleedSwipeRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0))
            .listRowBackground(Color(UIColor.systemBackground))
            .clipShape(Rectangle())
    }

    func musicoMediaSwipeActions(
        editLabel: String = "Edit",
        onEdit: @escaping () -> Void,
        deleteLabel: String = "Delete",
        onDelete: @escaping () -> Void
    ) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Text(deleteLabel)
            }
            Button(action: onEdit) {
                Text(editLabel)
            }
            .tint(.blue)
        }
    }
}
