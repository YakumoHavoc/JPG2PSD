//
//  Converter.swift
//  JPG → PSD 批量无损转换
//
//  单文件转换与批量收集，逻辑与命令行/graphical 界面共用。
//

import Foundation

/// 单文件转换结果
enum ConvertOutcome {
    /// 转换成功，附带尺寸/压缩方式/体积描述
    case ok(String)
    /// 因目标已存在等原因跳过
    case skipped(String)
}

enum Converter {
    static let jpegExtensions = [".jpg", ".jpeg", ".jpe", ".jfif", ".jfi"]

    static func isJPEG(_ path: String) -> Bool {
        let lower = path.lowercased()
        return jpegExtensions.contains { lower.hasSuffix($0) }
    }

    /// 展开 `~` 与相对路径
    static func absolutePath(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    // MARK: - 单文件转换

    /// 把 `src` 转成 PSD 写到 `dst`。
    /// 写盘用临时文件 + 原子替换，中途中断不会留下半成品。
    static func convertOne(src: String,
                           dst: String,
                           compression: PSDCompression,
                           keepOrientation: Bool,
                           overwrite: Bool) throws -> ConvertOutcome {
        let manager = FileManager.default
        if manager.fileExists(atPath: dst), !overwrite {
            return .skipped("目标已存在（勾选「覆盖已存在的 PSD」可覆盖）")
        }

        let loaded = try ImageLoader.load(path: src, keepOrientation: keepOrientation)
        let (psd, method) = try PSDWriter.build(loaded.planar, icc: loaded.icc,
                                                dpi: loaded.dpi, compression: compression)

        let temporary = dst + ".part"
        try psd.write(to: URL(fileURLWithPath: temporary))
        if manager.fileExists(atPath: dst) {
            _ = try manager.replaceItemAt(URL(fileURLWithPath: dst),
                                          withItemAt: URL(fileURLWithPath: temporary))
        } else {
            try manager.moveItem(atPath: temporary, toPath: dst)
        }

        var description = "\(loaded.planar.width)x\(loaded.planar.height) \(method) "
            + String(format: "%.1fMB", Double(psd.count) / 1_048_576)
        if let icc = loaded.icc, !icc.isEmpty {
            description += " ICC:\(icc.count)B"
        }
        return .ok(description)
    }

    // MARK: - 批量收集

    /// 把「文件 / 文件夹混合的输入列表」展开成待转换的 JPG 文件列表。
    /// 返回去重并排序后的文件，以及需要提示给用户的警告。
    static func collectInputs(_ paths: [String], recursive: Bool) -> (files: [String], warnings: [String]) {
        let manager = FileManager.default
        var found: [String] = []
        var warnings: [String] = []

        for raw in paths {
            let path = absolutePath(raw)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: path, isDirectory: &isDirectory) else {
                warnings.append("找不到路径：\(raw)")
                continue
            }

            if isDirectory.boolValue {
                if recursive {
                    let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
                    if let enumerator = manager.enumerator(at: URL(fileURLWithPath: path),
                                                           includingPropertiesForKeys: [.isRegularFileKey],
                                                           options: options) {
                        for case let fileURL as URL in enumerator where isJPEG(fileURL.path) {
                            found.append(fileURL.path)
                        }
                    }
                } else {
                    let names = (try? manager.contentsOfDirectory(atPath: path)) ?? []
                    for name in names.sorted() {
                        let full = (path as NSString).appendingPathComponent(name)
                        var childIsDirectory: ObjCBool = false
                        if manager.fileExists(atPath: full, isDirectory: &childIsDirectory),
                           !childIsDirectory.boolValue,
                           isJPEG(full) {
                            found.append(full)
                        }
                    }
                }
            } else if isJPEG(path) {
                found.append(path)
            } else {
                warnings.append("跳过（非 JPG）：\(raw)")
            }
        }

        return (Array(Set(found)).sorted(), warnings)
    }
}
