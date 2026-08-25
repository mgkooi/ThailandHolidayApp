import SwiftUI
import UIKit

struct TripMediaImage: View {
    @Environment(TripStore.self) private var store
    let media: TripMedia?
    var body: some View {
        Group {
            if let filename = media?.filename,
               let url = store.attachmentURL(for: filename),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable()
            } else if let url = media?.remoteURL {
                AsyncImage(url: url) { image in image.resizable() }
                    placeholder: { placeholder }
            } else { placeholder }
        }
    }
    private var placeholder: some View {
        Rectangle().fill(.quaternary).overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
    }
}
