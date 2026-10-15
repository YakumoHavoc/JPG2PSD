# JPG2PSD

把一批 JPG 图片批量转存为 PSD，方便直接用 Photoshop 打开做后期修图。

纯 Swift + AppKit 原生实现，无任何第三方依赖，也不需要 Python 运行时。

## 关于"无损"

- **JPG 本身是有损格式**，解码出来的像素就是原图能提供的全部信息，不可能再"还原"更多细节。
- 本工具做的是：把 JPG 解码后的像素 **原样** 写进 PSD（Raw 或 RLE/PackBits 无损压缩），
  逐字节与解码结果一致，**不会因为转存而二次损失画质**。
- 不会使用 PSD 内部的 JPEG 压缩（那才是二次损失）。
- 同时保留原图的 **ICC 色彩描述文件**（逐字节嵌入，颜色口径一致）与 **分辨率 DPI**。
- 默认按 EXIF 方向自动摆正（旋转 90°/180° 属于无损的像素搬移），可用 `--keep-orientation` 关闭。
- 源为灰度 JPG 时输出灰度模式 PSD（单通道），同样无损。

## 快速开始

**方式一：双击 `JPG转PSD.app`（推荐，带图形界面）**

- 双击打开图形界面；可以**把 JPG 文件 / 文件夹直接拖进窗口**，也可以把它们拖到 App 图标上，
  都会自动填入待转换列表。
- 自包含：编译好的可执行文件在包内，**无需另外安装任何东西**。
- 运行要求：macOS 13 或更高版本、Apple Silicon（arm64）。

**方式二：命令行**

App 包内的可执行文件也支持命令行批量转换（`--cli` 后的参数与下方参数表一致）：

```bash
# 转换整个文件夹（递归子目录），结果放到 PSD 目录
JPG转PSD.app/Contents/MacOS/JPG2PSD --cli ~/Pictures/旅行 -o ~/Pictures/旅行/PSD -r

# 转换若干指定文件（结果与源文件同目录）
JPG转PSD.app/Contents/MacOS/JPG2PSD --cli a.jpg b.jpg c.jpeg

# 强制无损 RLE 压缩并覆盖旧文件
JPG转PSD.app/Contents/MacOS/JPG2PSD --cli . -r --compression rle --overwrite
```

## 图形界面

界面从上到下分四块：

1. **待转换的 JPG**：`添加图片…`、`添加文件夹…`、`移除选中`、`全部清空`（非 JPG 文件会被自动忽略）。
   列表为空时显示"把 JPG 图片或文件夹拖到这里"的提示，也可以直接把文件拖进来。
2. **输出位置**：`与源文件同目录`（默认）或 `指定目录：` 后点 `选择…`。
3. **选项**：`递归子文件夹`、`按 EXIF 摆正方向（无损）`、`覆盖已存在的 PSD`，以及 `PSD 压缩方式`
   （自动 / 无损 RLE / 不压缩 Raw）。
4. **进度与日志**：底部实时显示每个文件的处理结果，结束后点 `打开输出文件夹` 直接查看。

转换在后台执行，界面不会卡住；运行中按钮会变成 `停止`，可中途取消。
界面全部使用语义色，自动适配系统浅色 / 深色外观。

## 性能

批量转换按 **CPU 核数并行**处理多个文件（并发上限 8），因此转换时 CPU 占用会接近满载；
GPU 不参与计算，这是正常的——整条管线是纯 CPU 字节搬运（JPEG 解码 + 内存重排 + PackBits），
不涉及 GPU 计算。

两项关键设计：

- **内存预算分波**：大图解码时峰值内存约为 10 字节/像素。程序先读取各文件像素总数（只读图像头，
  不解码像素），把一批文件切成若干"波"，每波总用量控制在约 2GB 内，波内再按核数并发，
  避免多张大图同时解码把内存推向交换。
- **写盘串行化**：解码与打包并行，但写盘排队执行。同时写多个几十 MB 的 PSD 会触发系统脏页限流，
  写出速度反而下降；串行写能让整个流程形成流水线并跑满磁盘带宽。

实测（43 个文件 / 40 张 12MP 照片 / 输出约 1.4GB）：整体耗时较串行版本下降约 3 倍。

## 重新构建

```bash
./build_swift.sh          # 产物：JPG转PSD.app（arm64）
```

脚本用 `swiftc` 直接编译 `Sources/*.swift`，再手工组装 App 包（写入 `Info.plist`、
装入 `assets/icon.icns` 图标）并做临时签名。只需 macOS 自带的 Xcode Command Line Tools，
不需要完整的 Xcode。

隐藏用法：`--dump-planar <目录> <输入…>` 会把手动解码后的平面像素连同方向 / ICC / DPI 元信息
导出成 `.raw` + `.meta` 文件，用于逐字节核对 PSD 内写入的像素与解码结果是否一致（自检用）。

## 参数

| 参数 | 说明 |
| --- | --- |
| `inputs` | JPG 文件、文件夹，或两者混合，可多个 |
| `-o, --output` | 输出目录；省略则与源文件同目录 |
| `-r, --recursive` | 递归扫描子文件夹 |
| `--compression` | `auto`（默认，自动在 Raw / RLE 中选体积更小者，均无损）、`raw`、`rle` |
| `--keep-orientation` | 不按 EXIF 方向摆正 |
| `--overwrite` | 覆盖已存在的 PSD（默认跳过） |
| `-q, --quiet` | 只输出汇总，不逐个打印 |
| `-h, --help` | 显示帮助 |

输出文件名与源文件同名，仅扩展名改为 `.psd`；写盘使用临时文件 + 原子替换，中途中断不会留下半成品。

## 说明与常见问题

- **打开后的图层**：PSD 为合并图像，Photoshop 打开后是单个「背景」层，这正是修图的起点。
- **文件体积**：照片类图像 RLE 收益很小，工具会自动选择 Raw（更小更快）；
  纯色、截图、扫描件等大面积平坦的图像会自动用 RLE，体积可缩小几十倍。
- **CMYK 等其它色彩模式**的 JPG 会先转成 RGB 再写入（用 Photoshop 直接转更稳妥）。
- **输出文件重名**：指定输出目录时，若不同子目录下有同名文件（如 `a/x.jpg` 与 `b/x.jpg`），
  只会写出先出现的那个，其余在日志中提示"输出文件重名，已跳过"，不会互相覆盖。
- **图像过宽**：RLE 每行长度用 2 字节记录，宽度超出上限时会提示改用「不压缩 Raw」。
- 个别文件损坏或无法识别时会跳过并提示，不影响批量中其它文件。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `JPG转PSD.app` | 图形界面应用（自包含，双击即可用，arm64） |
| `build_swift.sh` | 重新构建 `.app` 的脚本 |
| `assets/icon.icns` | 应用图标 |
| `Sources/main.swift` | 程序入口（GUI / `--cli` / `--dump-planar` 分流） |
| `Sources/PSDWriter.swift` | PSD 二进制写入（Raw / RLE / auto、ICC、DPI、EXIF 方向重排） |
| `Sources/ImageLoader.swift` | ImageIO 解码并拆成通道平面 |
| `Sources/JPEGMarker.swift` | 解析 JPEG 标记段，取出原始 ICC 与 DPI（对齐 Pillow 口径） |
| `Sources/Converter.swift` | 单文件转换、批量并行调度与原子写盘 |
| `Sources/MainWindowController.swift` | 主窗口界面与后台转换调度 |
| `Sources/DropView.swift` | 窗口内文件拖放 |
| `Sources/AppDelegate.swift` | 应用生命周期、菜单、图标拖放 |
| `Sources/CLIRunner.swift` | 命令行入口与自检导出 |
| `Sources/Info.plist` | 应用包信息（名称、图标、文档类型、系统要求） |
