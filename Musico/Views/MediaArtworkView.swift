import SwiftUI
import UIKit

struct MediaArtworkView: View {
    @EnvironmentObject private var library: LibraryStore
    let item: LibraryItem
    var size: CGFloat = 32
    var cornerRadius: CGFloat?

    private var resolvedCornerRadius: CGFloat {
        cornerRadius ?? size * 0.16
    }

    var body: some View {
        Group {
            if let uiImage = library.artworkImage(for: item, targetSize: size) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    MusicoTheme.surfaceGradient
                    MusicoTheme.brandGradient.opacity(0.22)
                    Image(systemName: item.kind.systemImage)
                        .font(.system(size: size * 0.40, weight: .medium))
                        .foregroundColor(.white.opacity(0.88))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous))
    }
}

struct LargeMediaArtworkView: View {
    @EnvironmentObject private var library: LibraryStore
    let item: LibraryItem

    var body: some View {
        Group {
            if let uiImage = library.artworkImage(for: item, targetSize: 420) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    MusicoTheme.surfaceGradient
                    MusicoTheme.brandGradient.opacity(0.18)
                    Image(systemName: item.kind.systemImage)
                        .font(.system(size: 82, weight: .light))
                        .foregroundColor(.white.opacity(0.78))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
