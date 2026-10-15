# JPG → PSD 批量无损转换
 
把一批 JPG 图片批量转存为 PSD，方便直接用 Photoshop 打开做后期修图。
 
纯 Swift + AppKit 实现，无任何第三方依赖，也不需要 Python 运行时。
 
## 关于"无损"
 
- **JPG 本身是有损格式**，解码出来的像素就是原图能提供的全部信息，不可能再"还原"更多细节。
9 行已隐藏
 
- 双击打开图形界面；可以**把 JPG 文件 / 文件夹直接拖进窗口**，也可以把它们拖到 App 图标上，
  都会自动填入待转换列表。
- 自包含：编译好的可执行文件在包内，**无需另外安装任何东西**。
- 运行要求：macOS 13 或更高版本、Apple Silicon（arm64）。
 
**方式二：命令行**
 
`JPG转PSD.app` 包内的可执行文件也支持命令行批量转换（`--cli` 后的参数与下表一致）：
 
```bash
# 转换整个文件夹（递归子目录），结果放到 PSD 目录
JPG转PSD.app/Contents/MacOS/JPG2PSD --cli ~/Pictures/旅行 -o ~/Pictures/旅行/PSD -r
 
# 转换若干指定文件（结果与源文件同目录）
JPG转PSD.app/Contents/MacOS/JPG2PSD --cli a.jpg b.jpg c.jpeg
 
# 强制无损 RLE 压缩并覆盖旧文件
JPG转PSD.app/Contents/MacOS/JPG2PSD --cli . -r --compression rle --overwrite
```
 
## 图形界面（`JPG转PSD.app`）
7 行已隐藏
4. **进度与日志**：底部实时显示每个文件的处理结果，结束后点 `打开输出文件夹` 直接查看。
 
转换在后台线程执行，界面不会卡住；运行中按钮会变成 `停止`，可中途取消。
界面跟随系统深浅色自动适配。
 
**重新构建**（改代码后重建 `.app`）：
 
```bash
./build_swift.sh          # 产物：JPG转PSD.app（arm64）
```
 
脚本用 `swiftc` 直接编译 `Sources/*.swift`，再手工组装 App 包（写入 `Info.plist`、
装入 `assets/icon.icns` 图标）并做临时签名。只需 macOS 自带的 Xcode Command Line Tools，
不需要完整的 Xcode。
 
隐藏用法：`--dump-planar <目录> <输入…>` 会把手动解码后的平面像素连同方向/ICC/DPI 元信息
导出成 `.raw` + `.meta` 文件，用于逐字节核对 PSD 内写入的像素与解码结果是否一致（自检用）。
 
## 参数
 
| 参数 | 说明 |
15 行已隐藏
  纯色、截图、扫描件等大面积平坦的图像会自动用 RLE，体积可缩小几十倍。
- **灰度图**：源为灰度 JPG 时，输出为灰度模式 PSD（单通道），同样无损。
- **CMYK 等其它色彩模式**的 JPG 会先转成 RGB 再写入（用 Photoshop 直接转更稳妥）。
- 个别文件损坏或无法识别时会跳过并提示，不影响批量中其它文件。
 
## 文件说明
 
| 文件 | 作用 |
| --- | --- |
| `JPG转PSD.app` | 图形界面应用（自包含，双击即可用，arm64） |
| `Sources/` | Swift 源码 |
| `Sources/PSDWriter.swift` | PSD 二进制写入（Raw / RLE / auto、ICC、DPI、EXIF 方向重排） |
| `Sources/ImageLoader.swift` | ImageIO 解码并拆成通道平面 |
| `Sources/JPEGMarker.swift` | 解析 JPEG 标记段，取出原始 ICC 与 DPI（对齐 Pillow 口径） |
| `Sources/Converter.swift` | 单文件转换、批量收集与原子写盘 |
| `Sources/MainWindowController.swift` | 主窗口界面与后台转换调度 |
| `Sources/DropView.swift` | 窗口内文件拖放 |
| `Sources/AppDelegate.swift` | 应用生命周期、菜单、图标拖放 |
| `Sources/CLIRunner.swift` | 命令行入口与自检导出 |
| `Sources/main.swift` | 程序入口（GUI / `--cli` / `--dump-planar` 分流） |
| `Sources/Info.plist` | 应用包信息（名称、图标、文档类型、系统要求） |
| `build_swift.sh` | 重新构建 `.app` 的脚本 |
| `assets/icon.icns` | 应用图标 |
