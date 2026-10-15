//
//  ImageLoader.swift
//  JPG → PSD 批量无损转换
//
//  用 ImageIO 解码 JPG，再把像素整理成 PSD 需要的「通道优先 8bit 平面」。
//
//  无损要点：
//    - 渲染到与原图**同一色彩空间**的 bitmap 上下文里，CoreGraphics 不做任何色彩转换，
//      像素值与解码结果逐字节一致（渲染为 1:1 整数对齐，无重采样）；
//    - EXIF 方向摆正是在平面数据上做纯索引重排（见 PSDWriter.applyOrientation），
//      不像真旋转那样会引入重采样误差。
//

import Foundation
import ImageIO
import CoreGraphics

enum ImageLoaderError: LocalizedError {
    case cannotOpen
    case cannotDecode
    case cannotCreateContext

    var errorDescription: String? {
        switch self {
        case .cannotOpen: return "无法打开文件（可能不是图片或已损坏）"
        case .cannotDecode: return "无法解码图像数据"
        case .cannotCreateContext: return "无法创建绘图上下文"
        }
    }
}

/// 解码并整理好的图像
struct LoadedImage {
    var planar: PlanarImage
    var icc: Data?
    var dpi: (h: Double, v: Double)?
    /// EXIF 方向值 1…8（未标注为 1）
    var orientation: Int
}

enum ImageLoader {
    /// 解码单个文件。`keepOrientation = true` 时不做 EXIF 摆正。
    static func load(path: String, keepOrientation: Bool) throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
            throw ImageLoaderError.cannotOpen
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageLoaderError.cannotDecode
        }

        // 灰度 JPG -> 灰度 PSD（单通道）；其余（含 CMYK）-> RGB
        let wantsGray = (properties?[kCGImagePropertyColorModel] as? String) == "Gray"
            || image.colorSpace?.model == .monochrome
        let channels = wantsGray ? 1 : 3
        let colorMode = wantsGray ? PSDWriter.colorModeGrayscale : PSDWriter.colorModeRGB

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { throw ImageLoaderError.cannotDecode }

        // 与原图一致的色彩空间，保证渲染是恒等变换（不做色彩管理）
        let space: CGColorSpace
        if let sourceSpace = image.colorSpace,
           sourceSpace.model == (wantsGray ? .monochrome : .rgb) {
            space = sourceSpace
        } else {
            space = wantsGray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        }

        // 交错缓冲区：灰度 1 字节/像素；RGB 用 32bit 的 RGBX（末字节被忽略），随后拆成平面
        let bytesPerRow = wantsGray ? width : width * 4
        let bitmapInfo = wantsGray ? CGImageAlphaInfo.none.rawValue
                                   : CGImageAlphaInfo.noneSkipLast.rawValue
        var interleaved = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn = interleaved.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: width, height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow,
                                          space: space,
                                          bitmapInfo: bitmapInfo) else { return false }
            context.setShouldAntialias(false)
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw ImageLoaderError.cannotCreateContext }

        var planar = PlanarImage.empty(width: width, height: height,
                                       channels: channels, colorMode: colorMode)
        planar.data.withUnsafeMutableBytes { dstRaw in
            guard let dst = dstRaw.bindMemory(to: UInt8.self).baseAddress else { return }
            interleaved.withUnsafeBufferPointer { src in
                guard let source = src.baseAddress else { return }
                if wantsGray {
                    dst.update(from: source, count: width * height)
                } else {
                    let planeSize = width * height
                    for y in 0..<height {
                        let rowStart = y * bytesPerRow
                        var out = y * width
                        for x in 0..<width {
                            let p = rowStart + x * 4
                            dst[out] = source[p]
                            dst[planeSize + out] = source[p + 1]
                            dst[2 * planeSize + out] = source[p + 2]
                            out += 1
                        }
                    }
                }
            }
        }

        // EXIF 方向
        var orientation = 1
        if let raw = properties?[kCGImagePropertyOrientation] as? Int, raw >= 1, raw <= 8 {
            orientation = raw
        }
        if !keepOrientation, orientation > 1 {
            planar = PSDWriter.applyOrientation(planar, orientation)
        }

        // ICC 与 DPI 直接按 JPEG 标记段解析，口径与 Pillow 一致
        let metadata = JPEGMarker.metadata(at: path)

        return LoadedImage(planar: planar, icc: metadata.icc, dpi: metadata.dpi,
                           orientation: orientation)
    }
}
