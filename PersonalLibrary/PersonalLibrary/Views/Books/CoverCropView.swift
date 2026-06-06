import SwiftUI
import UIKit

/// 封面裁剪编辑器：图片可捏合缩放 + 拖动平移，上面叠一个自由比例裁剪框（四角可调、框体可移动）。
/// 「确定」时按 `CoverCropGeometry` 把裁剪框区域裁出，回传裁剪后的 UIImage。
///
/// 压缩在调用方完成（统一走 CoverImageProcessor，§4.1），此处只负责裁剪。
struct CoverCropView: View {
    let image: UIImage
    let onConfirm: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    // 桥接 SwiftUI 工具栏按钮 → UIKit 裁剪控制器
    @State private var bridge = CropBridge()

    var body: some View {
        NavigationStack {
            CropEditorRepresentable(image: image, bridge: bridge)
                .ignoresSafeArea(edges: .bottom)
                .background(Color.black)
                .navigationTitle("裁剪封面")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确定") {
                            if let cropped = bridge.crop() { onConfirm(cropped) }
                            dismiss()
                        }
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button { bridge.rotate(clockwise: false) } label: {
                            Image(systemName: "rotate.left")
                        }
                        Spacer()
                        Button { bridge.rotate(clockwise: true) } label: {
                            Image(systemName: "rotate.right")
                        }
                    }
                }
        }
    }
}

/// 待裁剪图片的包装（UIImage 非 Identifiable，用它驱动 .fullScreenCover(item:)）
struct CropTarget: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 持有裁剪控制器的弱引用，让 SwiftUI 按钮能触发裁剪/旋转
private final class CropBridge {
    weak var controller: CropViewController?
    func crop() -> UIImage? { controller?.croppedImage() }
    func rotate(clockwise: Bool) { controller?.rotate(clockwise: clockwise) }
}

private struct CropEditorRepresentable: UIViewControllerRepresentable {
    let image: UIImage
    let bridge: CropBridge

    func makeUIViewController(context: Context) -> CropViewController {
        let vc = CropViewController(image: image)
        bridge.controller = vc
        return vc
    }

    func updateUIViewController(_ uiViewController: CropViewController, context: Context) {}
}

// MARK: - 裁剪控制器（UIScrollView 缩放/平移 + 裁剪框覆盖层）

private final class CropViewController: UIViewController, UIScrollViewDelegate {
    private var image: UIImage  // 旋转会替换为新图；改此属性后必须 fitSize=.zero + layoutImage()
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let overlay = CropOverlayView()

    /// 图片在 1x 缩放下铺满 scrollView 的尺寸（aspect-fit），用于归一化换算
    private var fitSize: CGSize = .zero

    init(image: UIImage) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.bouncesZoom = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        imageView.image = image
        imageView.contentMode = .scaleToFill
        scrollView.addSubview(imageView)

        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.isUserInteractionEnabled = true
        view.addSubview(overlay)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: scrollView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard fitSize == .zero, scrollView.bounds.width > 0, image.size.width > 0 else { return }
        layoutImage()
    }

    /// 把图片 aspect-fit 进 scrollView，并初始化裁剪框为铺满图片显示区
    private func layoutImage() {
        let bounds = scrollView.bounds.size
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        fitSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        imageView.frame = CGRect(origin: .zero, size: fitSize)
        scrollView.contentSize = fitSize
        scrollView.zoomScale = 1
        centerContent()

        // 裁剪框初始 = 图片显示区域（考虑居中 inset）
        let originX = scrollView.contentInset.left
        let originY = scrollView.contentInset.top
        overlay.cropRect = CGRect(x: originX, y: originY, width: fitSize.width, height: fitSize.height)
            .intersection(overlay.bounds)
    }

    /// 内容小于 scrollView 时用 contentInset 居中
    private func centerContent() {
        let bounds = scrollView.bounds.size
        let content = scrollView.contentSize
        let insetX = max(0, (bounds.width - content.width) / 2)
        let insetY = max(0, (bounds.height - content.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    /// 按当前裁剪框裁出图片
    func croppedImage() -> UIImage? {
        guard fitSize.width > 0 else { return nil }
        let normalized = CoverCropGeometry.normalizedRect(
            contentOffset: scrollView.contentOffset,
            zoomScale: scrollView.zoomScale,
            cropFrame: overlay.cropRect,
            fitSize: fitSize)
        return CoverCropGeometry.crop(image, to: normalized)
    }

    /// 旋转图片 90°，替换当前图并重新铺满+重置裁剪框
    func rotate(clockwise: Bool) {
        guard let rotated = CoverCropGeometry.rotated90(image, clockwise: clockwise) else { return }
        image = rotated
        imageView.image = rotated
        scrollView.contentOffset = .zero   // 明确清偏移（layoutImage→centerContent 会再居中）
        fitSize = .zero                    // 触发重新 aspect-fit 布局
        layoutImage()
    }
}

// MARK: - 裁剪框覆盖层（自由比例，四角可调 + 框体可移动）

private final class CropOverlayView: UIView {
    /// 裁剪框（本视图坐标系）。设置时重绘遮罩与手柄。
    var cropRect: CGRect = .zero { didSet { setNeedsDisplay() } }

    /// 角手柄命中半径：32pt ≈ Apple HIG 44pt 最小可点区域的舒适半径，手指好按住
    private let handleHitRadius: CGFloat = 32
    /// 裁剪框最小边长，防止缩到无法操作的极小框
    private let minSide: CGFloat = 60

    /// 当前正在拖动的角（none 表示拖动框体）
    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight, none }
    private var activeCorner: Corner = .none
    private var dragStartRect: CGRect = .zero
    private var dragStartPoint: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    // 框外（遮罩区域）不拦截触摸，让 scrollView 继续缩放/平移；框内或角附近才接管
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        cornerNear(point) != .none || cropRect.insetBy(dx: -4, dy: -4).contains(point)
    }

    private func cornerNear(_ p: CGPoint) -> Corner {
        let corners: [(Corner, CGPoint)] = [
            (.topLeft, CGPoint(x: cropRect.minX, y: cropRect.minY)),
            (.topRight, CGPoint(x: cropRect.maxX, y: cropRect.minY)),
            (.bottomLeft, CGPoint(x: cropRect.minX, y: cropRect.maxY)),
            (.bottomRight, CGPoint(x: cropRect.maxX, y: cropRect.maxY)),
        ]
        for (corner, pt) in corners where hypot(p.x - pt.x, p.y - pt.y) <= handleHitRadius {
            return corner
        }
        return .none
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let p = gesture.location(in: self)
        switch gesture.state {
        case .began:
            activeCorner = cornerNear(p)
            dragStartRect = cropRect
            dragStartPoint = p
        case .changed:
            let dx = p.x - dragStartPoint.x
            let dy = p.y - dragStartPoint.y
            cropRect = activeCorner == .none
                ? movedRect(dragStartRect, dx: dx, dy: dy)
                : resizedRect(dragStartRect, corner: activeCorner, dx: dx, dy: dy)
        default:
            activeCorner = .none
        }
    }

    /// 平移框体，整体夹在视图范围内
    private func movedRect(_ rect: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        var r = rect.offsetBy(dx: dx, dy: dy)
        r.origin.x = min(max(0, r.origin.x), bounds.width - r.width)
        r.origin.y = min(max(0, r.origin.y), bounds.height - r.height)
        return r
    }

    /// 拖动某个角调整大小，约束最小边长与视图边界
    private func resizedRect(_ rect: CGRect, corner: Corner, dx: CGFloat, dy: CGFloat) -> CGRect {
        var left = rect.minX, top = rect.minY, right = rect.maxX, bottom = rect.maxY
        switch corner {
        case .topLeft: left += dx; top += dy
        case .topRight: right += dx; top += dy
        case .bottomLeft: left += dx; bottom += dy
        case .bottomRight: right += dx; bottom += dy
        case .none: break
        }
        left = max(0, min(left, right - minSide))
        top = max(0, min(top, bottom - minSide))
        right = min(bounds.width, max(right, left + minSide))
        bottom = min(bounds.height, max(bottom, top + minSide))
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), cropRect.width > 0 else { return }
        // 半透明遮罩 + 挖空裁剪框
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.5).cgColor)
        ctx.fill(bounds)
        ctx.clear(cropRect)

        // 裁剪框边线
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(cropRect)

        // 四角手柄
        ctx.setLineWidth(3)
        let len: CGFloat = 18
        let cs: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: cropRect.minX, y: cropRect.minY),
             CGPoint(x: cropRect.minX + len, y: cropRect.minY),
             CGPoint(x: cropRect.minX, y: cropRect.minY + len)),
            (CGPoint(x: cropRect.maxX, y: cropRect.minY),
             CGPoint(x: cropRect.maxX - len, y: cropRect.minY),
             CGPoint(x: cropRect.maxX, y: cropRect.minY + len)),
            (CGPoint(x: cropRect.minX, y: cropRect.maxY),
             CGPoint(x: cropRect.minX + len, y: cropRect.maxY),
             CGPoint(x: cropRect.minX, y: cropRect.maxY - len)),
            (CGPoint(x: cropRect.maxX, y: cropRect.maxY),
             CGPoint(x: cropRect.maxX - len, y: cropRect.maxY),
             CGPoint(x: cropRect.maxX, y: cropRect.maxY - len)),
        ]
        for (corner, h, v) in cs {
            ctx.move(to: h); ctx.addLine(to: corner); ctx.addLine(to: v)
        }
        ctx.strokePath()
    }
}
