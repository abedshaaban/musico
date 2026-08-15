import SwiftUI

extension View {
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
