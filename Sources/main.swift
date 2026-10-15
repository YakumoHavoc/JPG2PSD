//
//  main.swift
//  JPG → PSD 批量无损转换
//
//  默认启动图形界面；带 `--cli` 时走命令行批量转换（便于脚本调用）。
//

import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())

// 自检用：把解码后的平面像素原样导出，便于逐字节核对写入 PSD 的像素
if let index = arguments.firstIndex(of: "--dump-planar") {
    let rest = Array(arguments[(index + 1)...])
    guard let directory = rest.first else {
        FileHandle.standardError.write(Data("用法：--dump-planar <输出目录> <文件…>\n".utf8))
        exit(2)
    }
    exit(CLIRunner.dumpPlanar(outputDirectory: directory, paths: Array(rest.dropFirst())))
}

if let index = arguments.firstIndex(of: "--cli") {
    var passthrough = arguments
    passthrough.remove(at: index)
    exit(CLIRunner.run(passthrough))
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
