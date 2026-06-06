import ImageIO
import UIKit

/// 封面裁剪的纯几何核心：把"缩放/平移后的滚动状态 + 裁剪框"换算成图片上的归一化矩形，
/// 再按该矩形裁出 UIImage。抽成无 UIKit 视图依赖的纯函数，便于单测坐标映射与朝向处理。
enum CoverCropGeometry {

    /// 进入裁剪编辑器的图片最长边像素上限。
    /// 防 pixel-bomb：恶意图可在 10MB 字节限内编码出极大像素（如 100k×100k 纯色），
    /// 若用 UIImage(data:) 全量解码会瞬间 OOM。改用 ImageIO 限尺寸解码，从不分配全量缓冲。
    /// 2048px 对 ~400px 的最终封面仍有充足裁剪余量。
    static let maxCropPixel: CGFloat = 2048

    /// 用 ImageIO 限尺寸解码图片字节，供裁剪编辑器使用（已烘焙朝向）。
    /// 超大图被降采样到 ≤maxCropPixel；小图不放大；坏数据返回 nil。
    static func decodeForCropping(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // 烘焙 EXIF 朝向
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxCropPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// 由滚动视图状态推导出裁剪框覆盖的图片区域（归一化到 [0,1]）。
    ///
    /// - contentOffset: scrollView.contentOffset（视图点）
    /// - zoomScale:     scrollView.zoomScale
    /// - cropFrame:     裁剪框在 scrollView 坐标系中的位置/大小（视图点）
    /// - fitSize:       图片在 1x 缩放下铺满 scrollView 的尺寸（视图点）
    ///
    /// 返回值与图片朝向无关（基于"显示尺寸"），落在单位方框内；fitSize 退化时返回 `.zero`。
    static func normalizedRect(contentOffset: CGPoint, zoomScale: CGFloat,
                               cropFrame: CGRect, fitSize: CGSize) -> CGRect {
        guard fitSize.width > 0, fitSize.height > 0, zoomScale > 0 else { return .zero }

        // 裁剪框左上角/大小 → 内容坐标（除以缩放）→ 归一化（除以铺满尺寸）
        let originX = (cropFrame.minX + contentOffset.x) / zoomScale / fitSize.width
        let originY = (cropFrame.minY + contentOffset.y) / zoomScale / fitSize.height
        let width = cropFrame.width / zoomScale / fitSize.width
        let height = cropFrame.height / zoomScale / fitSize.height

        let raw = CGRect(x: originX, y: originY, width: width, height: height)
        // 越界（橡皮筋回弹时偏移可为负）夹回单位方框
        return raw.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// 按归一化矩形裁剪图片。先把朝向烘焙成 .up（保证像素坐标与显示一致），
    /// 再换算成像素矩形裁切。空/退化/越界矩形返回 nil。
    static func crop(_ image: UIImage, to normalized: CGRect) -> UIImage? {
        guard normalized.width > 0, normalized.height > 0,
              normalized.minX >= 0, normalized.minY >= 0,
              normalized.maxX <= 1.0001, normalized.maxY <= 1.0001 else { return nil }

        guard let baked = bakedUp(image), let cg = baked.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let pixelRect = CGRect(x: (normalized.minX * w).rounded(),
                               y: (normalized.minY * h).rounded(),
                               width: (normalized.width * w).rounded(),
                               height: (normalized.height * h).rounded())
        guard pixelRect.width >= 1, pixelRect.height >= 1,
              let cropped = cg.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped, scale: baked.scale, orientation: .up)
    }

    /// 把图片旋转 90°（clockwise=true 顺时针），返回烘焙成 .up 的新图（宽高互换）。
    /// 先用朝向重解释 + bakedUp 烘焙成真实像素，避免手写 CTM 旋转矩阵，
    /// 且裁剪/压缩下游拿到的仍是 .up 图。
    static func rotated90(_ image: UIImage, clockwise: Bool) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        // .right：内容需顺时针 90° 才正；.left：逆时针 90°
        let oriented = UIImage(cgImage: cg, scale: image.scale,
                               orientation: clockwise ? .right : .left)
        return bakedUp(oriented)
    }

    /// 把带朝向信息的图片重绘成 .up，使后续像素裁剪与肉眼所见一致。
    /// 已是 .up 直接返回，避免无谓重绘。
    private static func bakedUp(_ image: UIImage) -> UIImage? {
        guard image.imageOrientation != .up else { return image }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = image.scale
        fmt.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: fmt)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
