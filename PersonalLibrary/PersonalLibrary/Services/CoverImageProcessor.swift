import Foundation
import ImageIO
import UIKit

/// 封面图片压缩工具：把任何来源的封面统一压成小缩略图后再存库/缓存，
/// 避免大图内联进 SwiftData 主表（曾导致库膨胀到 196MB、主线程 save 卡顿、看门狗崩溃）。
///
/// 设计：在"图片进入 App 的入口"（下载器、相册选择）统一调用，
/// 下游的内存缓存与 SwiftData 持久化拿到的都是小图。
enum CoverImageProcessor {
    /// 缩略图最长边像素（详情页封面约 160pt，800px 给 3x Retina 留足余量，封面清晰不虚）
    static let maxPixelSize: CGFloat = 800
    static let jpegQuality: CGFloat = 0.7
    /// 已经足够小的数据直接放行，避免重复解码（≈40KB 以内）
    static let passthroughBelowBytes = 40_000

    /// 把封面数据压成 ≤maxPixelSize 的 JPEG 缩略图。
    /// - 数据已经很小、无法解码、或压缩后反而更大时，原样返回（绝不丢数据）。
    /// - 线程安全（ImageIO / UIImage(cgImage:).jpegData 均可在后台调用）。
    static func thumbnailData(from data: Data) -> Data {
        guard data.count > passthroughBelowBytes else { return data }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let jpeg = UIImage(cgImage: cgThumb).jpegData(compressionQuality: jpegQuality)
        else {
            return data
        }
        return jpeg.count < data.count ? jpeg : data
    }
}
