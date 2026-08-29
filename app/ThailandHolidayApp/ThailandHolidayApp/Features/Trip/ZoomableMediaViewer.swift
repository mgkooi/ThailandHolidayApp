import SwiftUI
import UIKit

struct ZoomableMediaViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZoomableImageScrollView(image: image)
                .ignoresSafeArea(edges: .bottom)
                .background(Color.black)
                .navigationTitle("Document")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(.black.opacity(0.75), for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .gray)
                        }
                        .accessibilityLabel("Sluit document")
                    }
                }
        }
        .accessibilityIdentifier("zoomableMediaViewer")
    }
}

private struct ZoomableImageScrollView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomingScrollView {
        let view = ZoomingScrollView()
        view.setImage(image)
        return view
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        view.setImage(image)
    }
}

private final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var currentImage: UIImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 8
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:))).configured {
            $0.numberOfTapsRequired = 2
        })
    }

    required init?(coder: NSCoder) { nil }

    func setImage(_ image: UIImage) {
        guard currentImage !== image else { return }
        currentImage = image
        imageView.image = image
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let size = currentImage?.size, bounds.width > 0, bounds.height > 0 else { return }
        let previousBounds = imageView.bounds.size
        let wasAtMinimum = zoomScale <= minimumZoomScale + 0.01
        let fit = min(bounds.width / size.width, bounds.height / size.height)
        let fittedSize = CGSize(width: size.width * fit, height: size.height * fit)
        if previousBounds != fittedSize {
            imageView.frame = CGRect(origin: .zero, size: fittedSize)
            contentSize = fittedSize
        }
        minimumZoomScale = 1
        maximumZoomScale = 8
        if wasAtMinimum { zoomScale = minimumZoomScale }
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let targetScale = min(3, maximumZoomScale)
            let point = recognizer.location(in: imageView)
            let width = bounds.width / targetScale
            let height = bounds.height / targetScale
            zoom(to: CGRect(x: point.x - width / 2, y: point.y - height / 2,
                            width: width, height: height), animated: true)
        }
    }

    private func centerImage() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        imageView.center = CGPoint(x: contentSize.width / 2 + horizontal,
                                   y: contentSize.height / 2 + vertical)
    }
}

private extension UITapGestureRecognizer {
    func configured(_ configure: (UITapGestureRecognizer) -> Void) -> UITapGestureRecognizer {
        configure(self)
        return self
    }
}
