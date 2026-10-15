//
//  JPEGMarker.swift
//  JPG → PSD 批量无损转换
//
//  一趟扫描 JPEG 标记段，取出 PSD 要用到的两项元数据：
//    1. 内嵌 ICC 色彩描述文件（APP2 `ICC_PROFILE`，多段按序号拼接）
//    2. 分辨率 DPI（JFIF APP0 密度优先，其次 EXIF APP1 的 IFD0 XResolution）
//
//  口径刻意与 Pillow 保持一致：
//    - 文件里没有内嵌 ICC 就返回 nil，不会把 ImageIO 自动补上的默认 sRGB /
//      灰度描述文件当成本图信息写进 PSD；
//    - DPI 的取值与回退规则（JFIF units=1/2；EXIF 有 APP1 但解析不出时回退 72）
//      与 Pillow 的 `JpegImagePlugin` 相同。
//

import Foundation

/// 从 JPEG 文件中读出的元数据
struct JPEGMetadata {
    var icc: Data?
    var dpi: (h: Double, v: Double)?
}

enum JPEGMarker {
    static func metadata(at path: String) -> JPEGMetadata {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path),
                                   options: .mappedIfSafe) else {
            return JPEGMetadata()
        }
        return data.withUnsafeBytes { metadata(in: $0) }
    }

    static func metadata(in bytes: UnsafeRawBufferPointer) -> JPEGMetadata {
        var result = JPEGMetadata()
        let count = bytes.count
        guard count > 4 else { return result }
        let b = bytes.bindMemory(to: UInt8.self)

        var iccChunks: [Int: Data] = [:]
        var iccExpected = 0
        var jfifDPI: (Double, Double)?
        var exifPresent = false
        var exifDPI: (Double, Double)?

        var i = 2  // 跳过 SOI(FFD8)
        while i + 4 <= count {
            guard b[i] == 0xFF else { break }
            let marker = b[i + 1]
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) {
                i += 2
                continue
            }
            if marker == 0xDA { break }  // SOS 之后是压缩数据，标记段到此为止
            let length = Int(b[i + 2]) << 8 | Int(b[i + 3])
            guard length >= 2 else { break }
            let payload = i + 4
            let end = i + 2 + length
            guard end <= count else { break }
            let body = UnsafeBufferPointer(rebasing: b[payload..<end])

            switch marker {
            case 0xE0 where jfifDPI == nil:
                // JFIF：units 1 = 像素/英寸，2 = 像素/厘米（1 dpcm = 2.54 dpi）
                if body.count >= 12, hasPrefix(body, Array("JFIF".utf8)) {
                    let units = Int(body[7])
                    let x = Int(body[8]) << 8 | Int(body[9])
                    let y = Int(body[10]) << 8 | Int(body[11])
                    if units == 1 {
                        jfifDPI = (Double(x), Double(y))
                    } else if units == 2 {
                        jfifDPI = (Double(x) * 2.54, Double(y) * 2.54)
                    }
                }

            case 0xE1 where !exifPresent:
                if body.count >= 6, hasPrefix(body, Array("Exif\0\0".utf8)) {
                    exifPresent = true
                    exifDPI = exifResolution(fromTIFF: body, at: 6)
                }

            case 0xE2:
                // ICC_PROFILE 分段：签名(11) + 0x00 + 序号 + 总数 + 数据
                if body.count >= 14, hasPrefix(body, Array("ICC_PROFILE".utf8)), body[11] == 0 {
                    let sequence = Int(body[12])
                    let total = Int(body[13])
                    if sequence >= 1, total >= 1, sequence <= total, body.count > 14 {
                        iccExpected = total
                        iccChunks[sequence] = Data(bytes: body.baseAddress!.advanced(by: 14),
                                                   count: body.count - 14)
                    }
                }

            default:
                break
            }
            i = end
        }

        if iccExpected > 0, iccChunks.count == iccExpected {
            var icc = Data()
            var complete = true
            for index in 1...iccExpected {
                guard let chunk = iccChunks[index] else { complete = false; break }
                icc.append(chunk)
            }
            if complete { result.icc = icc }
        }

        if let jfif = jfifDPI {
            result.dpi = (h: jfif.0, v: jfif.1)
        } else if exifPresent {
            // 与 Pillow 一致：有 EXIF 但解析不出分辨率时回退 72
            let resolved = exifDPI ?? (72, 72)
            result.dpi = (h: resolved.0, v: resolved.1)
        }

        return result
    }

    // MARK: - EXIF IFD0

    /// 从 APP1 载荷里的 TIFF 头读 IFD0 的 XResolution(0x011A) 与 ResolutionUnit(0x0128)。
    /// 两者缺一即返回 nil（调用方按 Pillow 的规则回退 72 DPI）。
    private static func exifResolution(fromTIFF payload: UnsafeBufferPointer<UInt8>, at tiff: Int) -> (Double, Double)? {
        guard payload.count >= tiff + 8 else { return nil }
        let marker = payload[tiff]
        let little: Bool
        switch marker {
        case 0x49: little = true    // "II"
        case 0x4D: little = false   // "MM"
        default: return nil
        }
        func u16(_ o: Int) -> Int {
            o + 2 <= payload.count ? (little ? Int(payload[o]) | Int(payload[o + 1]) << 8
                                              : Int(payload[o]) << 8 | Int(payload[o + 1])) : -1
        }
        func u32(_ o: Int) -> Int {
            guard o + 4 <= payload.count else { return -1 }
            return little
                ? Int(payload[o]) | Int(payload[o + 1]) << 8 | Int(payload[o + 2]) << 16 | Int(payload[o + 3]) << 24
                : Int(payload[o]) << 24 | Int(payload[o + 1]) << 16 | Int(payload[o + 2]) << 8 | Int(payload[o + 3])
        }
        guard u16(tiff + 2) == 42 else { return nil }
        let ifdOffset = u32(tiff + 4)
        guard ifdOffset > 0 else { return nil }
        let base = tiff + ifdOffset
        let entryCount = u16(base)
        guard entryCount > 0 else { return nil }

        var xResolution: Double?
        var resolutionUnit: Int?
        for index in 0..<entryCount {
            let entry = base + 2 + index * 12
            guard entry + 12 <= payload.count else { break }
            let tag = u16(entry)
            let type = u16(entry + 2)
            let count = u32(entry + 4)
            guard tag == 0x011A || tag == 0x0128 else { continue }
            if tag == 0x0128 {
                if type == 3, count == 1 { resolutionUnit = u16(entry + 8) }
            } else if count == 1 {
                if type == 5 {
                    // RATIONAL：值是 8 字节，前 4 字节为偏移
                    let offset = tiff + u32(entry + 8)
                    let numerator = u32(offset)
                    let denominator = u32(offset + 4)
                    if numerator >= 0, denominator > 0 { xResolution = Double(numerator) / Double(denominator) }
                } else if type == 4 {
                    let value = u32(entry + 8)
                    if value >= 0 { xResolution = Double(value) }
                }
            }
        }
        guard let x = xResolution, let unit = resolutionUnit else { return nil }
        let dpi = unit == 3 ? x * 2.54 : x   // 3 = 像素/厘米
        guard dpi.isFinite, dpi > 0 else { return nil }
        return (dpi, dpi)
    }

    private static func hasPrefix(_ body: UnsafeBufferPointer<UInt8>, _ needle: [UInt8]) -> Bool {
        guard body.count >= needle.count else { return false }
        for (offset, byte) in needle.enumerated() where body[offset] != byte { return false }
        return true
    }
}
