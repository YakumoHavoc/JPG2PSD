//
//  DropView.swift
//  JPG → PSD 批量无损转换
//
//  接收拖进窗口的文件 / 文件夹。整个窗口都是投放区，
//  列表、文本框等子视图没有注册文件拖放，事件会落到这里。
//

import AppKit

final class DropView: NSView {
    /// 收到投放时回调（已过滤为本地文件 URL，文件夹也算）
    var onDrop: (([URL]) -> Void)?

    /// 拖拽悬停时高亮边框
    private var isHighlighted = false {
        didSet {
            if isHighlighted != oldValue { needsDisplay = true }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHighlighted else { return }
        let inset = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(roundedRect: inset, xRadius: 8, yRadius: 8)
        path.lineWidth = 2
        // 语义色：浅色/深色模式都可见
        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }

    // MARK: - NSDraggingDestination

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                          options: options) as? [URL]
        return items ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return [] }
        isHighlighted = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return fileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isHighlighted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isHighlighted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHighlighted = false
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}
