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
            if let url = library.artworkURL(for: item),
               let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.12))
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
            if let url = library.artworkURL(for: item),
               let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: item.kind.systemImage)
                        .font(.system(size: 82, weight: .light))
                        .foregroundColor(.secondary)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
