//
//  MainWindowController.swift
//  JPG → PSD 批量无损转换
//
//  主窗口：待转换列表、输出位置、选项、进度与日志。
//  界面全部用语义色（NSColor.labelColor 等），自动适配浅色 / 深色外观。
//

import AppKit

/// 线程安全的取消标记
final class CancellationFlag {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

final class MainWindowController: NSWindowController {

    static let windowTitle = "JPG → PSD 批量转换"

    // 状态
    private var sources: [String] = []
    private var worker: DispatchQueue?
    private var cancelFlag: CancellationFlag?
    private var isRunning = false
    private var lastOutputDir: String?

    // 控件
    private var tableView: NSTableView!
    private var placeholder: NSTextField!
    private var sourceScroll: NSScrollView!
    private var sameDirRadio: NSButton!
    private var customDirRadio: NSButton!
    private var outputField: NSTextField!
    private var outputButton: NSButton!
    private var recursiveCheck: NSButton!
    private var orientCheck: NSButton!
    private var overwriteCheck: NSButton!
    private var compressionPopup: NSPopUpButton!
    private var startButton: NSButton!
    private var progressBar: NSProgressIndicator!
    private var openOutputButton: NSButton!
    private var statusLabel: NSTextField!
    private var logView: NSTextView!

    // MARK: - 构建窗口

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = Self.windowTitle
        window.minSize = NSSize(width: 760, height: 640)
        window.setFrameAutosaveName("JPG2PSDMainWindow")
        window.center()
        self.init(window: window)

        let drop = DropView()
        drop.onDrop = { [weak self] urls in
            self?.addSources(urls.map { $0.path })
        }
        window.contentView = drop

        buildInterface(in: drop)
        appendLog("请添加 JPG 图片或文件夹，然后点击「开始转换」。")
        appendLog("提示：可以把文件 / 文件夹直接拖进本窗口，或拖到应用图标上。")
    }

    // MARK: - 界面搭建

    private func buildInterface(in root: NSView) {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(column)

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])

        let inputs = buildInputsSection()
        let output = buildOutputSection()
        let options = buildOptionsSection()
        let actions = buildActionsSection()
        let log = buildLogSection()

        for view in [inputs, output, options, actions, log] {
            column.addArrangedSubview(view)
            view.leadingAnchor.constraint(equalTo: column.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: column.trailingAnchor).isActive = true
        }
        // 空白高度全部给日志区
        actions.setContentHuggingPriority(.defaultHigh, for: .vertical)
        log.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        log.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)
        log.heightAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
    }

    /// 统一的边框分组框，效果等同于原版的 LabelFrame
    private func makeBox(_ title: String, content: NSView) -> NSBox {
        let box = NSBox()
        box.title = title
        box.titlePosition = .atTop
        box.boxType = .primary
        box.contentViewMargins = NSSize(width: 10, height: 10)
        box.translatesAutoresizingMaskIntoConstraints = false
        box.contentView = NSView()

        content.translatesAutoresizingMaskIntoConstraints = false
        if let holder = box.contentView {
            holder.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                content.topAnchor.constraint(equalTo: holder.topAnchor),
                content.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            ])
        }
        return box
    }

    private func makeList() -> NSTableView {
        let table = NSTableView()
        table.headerView = nil
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = false
        table.style = .plain
        table.rowHeight = 20
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        return table
    }

    private func buildInputsSection() -> NSView {
        tableView = makeList()

        sourceScroll = NSScrollView()
        sourceScroll.documentView = tableView
        sourceScroll.hasVerticalScroller = true
        sourceScroll.autohidesScrollers = true
        sourceScroll.borderType = .bezelBorder
        sourceScroll.drawsBackground = true
        sourceScroll.translatesAutoresizingMaskIntoConstraints = false
        sourceScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        // 列表为空时居中显示的提示（拖拽引导）
        placeholder = NSTextField(labelWithString: "把 JPG 图片或文件夹拖到这里")
        placeholder.textColor = .secondaryLabelColor
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        sourceScroll.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: sourceScroll.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: sourceScroll.centerYAnchor),
        ])

        let buttons = NSStackView(views: [
            makeButton("添加图片…", action: #selector(pickFiles)),
            makeButton("添加文件夹…", action: #selector(pickFolder)),
            makeButton("移除选中", action: #selector(removeSelected)),
            makeButton("全部清空", action: #selector(clearSources)),
        ])
        buttons.orientation = .vertical
        buttons.spacing = 6
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalToConstant: 122).isActive = true

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .top
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(sourceScroll)
        row.addArrangedSubview(buttons)

        let box = makeBox(" 1. 待转换的 JPG ", content: row)
        box.heightAnchor.constraint(greaterThanOrEqualToConstant: 195).isActive = true
        return box
    }

    private func buildOutputSection() -> NSView {
        sameDirRadio = NSButton(radioButtonWithTitle: "与源文件同目录",
                                target: self, action: #selector(outputModeChanged))
        customDirRadio = NSButton(radioButtonWithTitle: "指定目录：",
                                  target: self, action: #selector(outputModeChanged))
        sameDirRadio.state = .on

        outputField = NSTextField(string: "")
        outputField.placeholderString = "选择一个输出文件夹"
        outputField.translatesAutoresizingMaskIntoConstraints = false
        outputButton = makeButton("选择…", action: #selector(pickOutputDir))
        outputButton.widthAnchor.constraint(equalToConstant: 76).isActive = true

        let customRow = NSStackView()
        customRow.orientation = .horizontal
        customRow.spacing = 8
        customRow.translatesAutoresizingMaskIntoConstraints = false
        customRow.addArrangedSubview(customDirRadio)
        customRow.addArrangedSubview(outputField)
        customRow.addArrangedSubview(outputButton)

        let column = NSStackView(views: [sameDirRadio, customRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.translatesAutoresizingMaskIntoConstraints = false

        syncOutputState()
        return makeBox(" 2. 输出位置 ", content: column)
    }

    private func buildOptionsSection() -> NSView {
        recursiveCheck = NSButton(checkboxWithTitle: "递归子文件夹",
                                  target: nil, action: nil)
        recursiveCheck.state = .on
        orientCheck = NSButton(checkboxWithTitle: "按 EXIF 摆正方向（无损）",
                               target: nil, action: nil)
        orientCheck.state = .on
        overwriteCheck = NSButton(checkboxWithTitle: "覆盖已存在的 PSD",
                                  target: nil, action: nil)

        let checkRow = NSStackView(views: [recursiveCheck, orientCheck, overwriteCheck])
        checkRow.orientation = .horizontal
        checkRow.spacing = 16
        checkRow.translatesAutoresizingMaskIntoConstraints = false

        compressionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for mode in PSDCompression.allCases {
            compressionPopup.addItem(withTitle: mode.label)
            compressionPopup.lastItem?.representedObject = mode.rawValue
        }
        compressionPopup.selectItem(at: 0)
        compressionPopup.translatesAutoresizingMaskIntoConstraints = false
        compressionPopup.widthAnchor.constraint(equalToConstant: 320).isActive = true

        let popupRow = NSStackView(views: [NSTextField(labelWithString: "PSD 压缩方式："),
                                           compressionPopup])
        popupRow.orientation = .horizontal
        popupRow.spacing = 8
        popupRow.translatesAutoresizingMaskIntoConstraints = false

        let column = NSStackView(views: [checkRow, popupRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        return makeBox(" 3. 选项 ", content: column)
    }

    private func buildActionsSection() -> NSView {
        startButton = makeButton("开始转换", action: #selector(startOrCancel))
        startButton.keyEquivalent = "\r"
        startButton.widthAnchor.constraint(equalToConstant: 118).isActive = true

        progressBar = NSProgressIndicator()
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0
        progressBar.controlSize = .regular
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.setContentHuggingPriority(.defaultLow, for: .horizontal)

        openOutputButton = makeButton("打开输出文件夹", action: #selector(openOutput))
        openOutputButton.isEnabled = false
        openOutputButton.widthAnchor.constraint(equalToConstant: 118).isActive = true

        let row = NSStackView(views: [startButton, progressBar, openOutputButton])
        row.orientation = .horizontal
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = NSTextField(labelWithString: "就绪")
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle

        let column = NSStackView(views: [row, statusLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        row.leadingAnchor.constraint(equalTo: column.leadingAnchor).isActive = true
        row.trailingAnchor.constraint(equalTo: column.trailingAnchor).isActive = true
        return column
    }

    private func buildLogSection() -> NSView {
        logView = NSTextView()
        logView.isEditable = false
        logView.isRichText = false
        logView.drawsBackground = true
        logView.backgroundColor = .textBackgroundColor
        logView.textColor = .textColor
        logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logView.isVerticallyResizable = true
        logView.isHorizontallyResizable = false
        logView.autoresizingMask = [.width]
        logView.textContainer?.widthTracksTextView = true
        logView.textContainerInset = NSSize(width: 4, height: 6)
        // 不接管文件拖放，保证拖到日志区也能被窗口接收
        logView.unregisterDraggedTypes()

        let scroll = NSScrollView()
        scroll.documentView = logView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        let box = makeBox(" 日志 ", content: scroll)
        box.setContentHuggingPriority(.defaultLow, for: .vertical)
        return box
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // MARK: - 交互辅助

    private func appendLog(_ text: String) {
        logView.string += text + "\n"
        logView.scrollToEndOfDocument(nil)
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    @objc private func outputModeChanged() {
        let custom = customDirRadio.state == .on
        sameDirRadio.state = custom ? .off : .on
        syncOutputState()
        if custom, outputField.stringValue.isEmpty {
            pickOutputDir()
        }
    }

    private func syncOutputState() {
        let custom = customDirRadio.state == .on
        outputField.isEnabled = custom
        outputButton.isEnabled = custom
    }

    // MARK: - 添加 / 移除输入

    /// 从窗口拖放或 Finder 图标拖放进来的路径
    func addSources(_ paths: [String]) {
        var added = 0
        var ignored = 0
        var duplicate = 0
        for raw in paths {
            let path = Converter.absolutePath(raw)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            if sources.contains(path) {
                duplicate += 1
                continue
            }
            if !isDirectory.boolValue && !Converter.isJPEG(path) {
                ignored += 1
                continue
            }
            sources.append(path)
            added += 1
        }
        refreshTable()
        if added > 0 {
            appendLog("已添加 \(added) 项（列表共 \(sources.count) 项）。")
        }
        if ignored > 0 {
            appendLog("忽略 \(ignored) 个非 JPG 文件。")
        }
        if duplicate > 0 {
            appendLog("\(duplicate) 项已在列表中，已忽略。")
        }
        activateWindow()
    }

    private func activateWindow() {
        guard let window else { return }
        if !window.isVisible { window.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshTable() {
        tableView.reloadData()
        placeholder.isHidden = !sources.isEmpty
    }

    @objc private func pickFiles() {
        let panel = NSOpenPanel()
        panel.title = "选择要转换的 JPG"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.jpeg]
        guard panel.runModal() == .OK else { return }
        addSources(panel.urls.map { $0.path })
    }

    @objc private func pickFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择包含 JPG 的文件夹"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK else { return }
        addSources(panel.urls.map { $0.path })
    }

    @objc private func removeSelected() {
        let indexes = tableView.selectedRowIndexes
        guard !indexes.isEmpty else {
            appendLog("没有选中任何项。")
            return
        }
        for index in indexes.reversed() {
            sources.remove(at: index)
        }
        refreshTable()
        appendLog("已移除 \(indexes.count) 项（列表共 \(sources.count) 项）。")
    }

    @objc private func clearSources() {
        guard !sources.isEmpty else { return }
        let count = sources.count
        sources.removeAll()
        refreshTable()
        appendLog("已清空 \(count) 项。")
    }

    @objc private func pickOutputDir() {
        let panel = NSOpenPanel()
        panel.title = "选择输出文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputField.stringValue = url.path
        customDirRadio.state = .on
        sameDirRadio.state = .off
        syncOutputState()
    }

    @objc private func openOutput() {
        guard let directory = lastOutputDir else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: directory))
    }

    // MARK: - 转换流程

    @objc private func startOrCancel() {
        if isRunning {
            cancelFlag?.cancel()
            startButton.isEnabled = false
            setStatus("正在停止…")
            appendLog("已请求停止，正在结束当前文件…")
            return
        }
        guard !sources.isEmpty else {
            appendLog("请先添加要转换的 JPG。")
            return
        }

        let recursive = recursiveCheck.state == .on
        let keepOrientation = orientCheck.state == .off
        let overwrite = overwriteCheck.state == .on
        let compression = selectedCompression()
        let customOutput: String? = customDirRadio.state == .on
            ? Converter.absolutePath(outputField.stringValue)
            : nil

        if customDirRadio.state == .on, outputField.stringValue.isEmpty {
            appendLog("请先选择输出目录。")
            return
        }

        // 展开文件夹
        let (files, warnings) = Converter.collectInputs(sources, recursive: recursive)
        warnings.forEach { appendLog($0) }
        guard !files.isEmpty else {
            appendLog("没有找到任何 JPG 文件。")
            return
        }

        var outputDirectory: String?
        if let customOutput {
            do {
                try FileManager.default.createDirectory(atPath: customOutput,
                                                        withIntermediateDirectories: true)
                outputDirectory = customOutput
            } catch {
                appendLog("无法创建输出目录：\(error.localizedDescription)")
                return
            }
        }

        appendLog("开始转换 \(files.count) 个文件（压缩方式：\(compression.label)）。")
        setRunning(true)
        progressBar.maxValue = Double(files.count)
        progressBar.doubleValue = 0
        setStatus("转换中… 0/\(files.count)")

        let flag = CancellationFlag()
        cancelFlag = flag
        let queue = DispatchQueue(label: "com.tools.jpg2psd.convert", qos: .userInitiated)
        worker = queue

        queue.async { [weak self] in
            var succeeded = 0, skipped = 0, failed = 0
            var totalBytes = 0
            var outputDir: String?

            for (position, source) in files.enumerated() {
                if flag.isCancelled { break }

                let name = (source as NSString).lastPathComponent
                let stem = (name as NSString).deletingPathExtension
                let directory = outputDirectory ?? (source as NSString).deletingLastPathComponent
                let destination = (directory as NSString).appendingPathComponent(stem + ".psd")
                outputDir = directory
                let prefix = "[\(position + 1)/\(files.count)] \(name)"

                do {
                    switch try Converter.convertOne(src: source, dst: destination,
                                                    compression: compression,
                                                    keepOrientation: keepOrientation,
                                                    overwrite: overwrite) {
                    case .ok(let description):
                        succeeded += 1
                        if let size = try? FileManager.default
                            .attributesOfItem(atPath: destination)[.size] as? Int {
                            totalBytes += size
                        }
                        self?.onMain { self?.appendLog("\(prefix)  ->  \(stem).psd   \(description)") }
                    case .skipped(let reason):
                        skipped += 1
                        self?.onMain { self?.appendLog("\(prefix)  跳过：\(reason)") }
                    }
                } catch {
                    failed += 1
                    self?.onMain { self?.appendLog("\(prefix)  失败：\(error.localizedDescription)") }
                }

                let done = position + 1
                self?.onMain {
                    self?.progressBar.doubleValue = Double(done)
                    self?.setStatus("转换中… \(done)/\(files.count)")
                }
            }

            let cancelled = flag.isCancelled
            self?.onMain {
                let megabytes = Double(totalBytes) / 1_048_576
                let summary = String(format: "完成：成功 %d，跳过 %d，失败 %d，共 %.1fMB。",
                                     succeeded, skipped, failed, megabytes)
                self?.appendLog(cancelled ? "已停止。" + summary : summary)
                self?.setStatus(cancelled
                    ? "已停止（成功 \(succeeded)，跳过 \(skipped)，失败 \(failed)）"
                    : "完成：成功 \(succeeded)，跳过 \(skipped)，失败 \(failed)")
                if succeeded > 0, let directory = outputDir {
                    self?.lastOutputDir = directory
                    self?.openOutputButton.isEnabled = true
                }
                self?.setRunning(false)
            }
        }
    }

    private func onMain(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    private func selectedCompression() -> PSDCompression {
        let raw = compressionPopup.selectedItem?.representedObject as? String
        return raw.flatMap(PSDCompression.init(rawValue:)) ?? .auto
    }

    private func setRunning(_ running: Bool) {
        isRunning = running
        startButton.isEnabled = true
        startButton.title = running ? "停止" : "开始转换"
        startButton.keyEquivalent = running ? "" : "\r"
        progressBar.isHidden = false
        if !running {
            cancelFlag = nil
            worker = nil
        }
    }
}

// MARK: - 列表数据源

extension MainWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        sources.count
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("sourceCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        guard row < sources.count else { return cell }
        cell.textField?.stringValue = sources[row]
        cell.textField?.toolTip = sources[row]
        return cell
    }
}
