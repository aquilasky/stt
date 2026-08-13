# LectureCaption

macOS 14+（Apple Silicon）课堂实时字幕 MVP。工程采用 Swift 6.3 与 SwiftUI，主应用通过 `LectureCaption.xcodeproj` 构建；Swift Package 保留用于快速模块测试。

## 开发

```bash
swift build
swift test
```

在 Xcode 中打开 `LectureCaption.xcodeproj` 后，选择 `LectureCaption` scheme 运行。`Resources/Info.plist` 仅声明麦克风权限用途。

1.0.0 已提供：

- 主窗口、课程上下文、术语表和会话控制 UI。
- 麦克风音频采集、本地输入活动检测、自动待机和手动暂停。
- 阿里云实时 ASR、临时/最终字幕稳定与断句后的原文保存。
- DeepSeek `deepseek-v4-flash` 异步翻译、术语表和有界上下文。
- 本地 JSON 课堂记录与历史查看。
- 跨桌面、全屏可见且不抢键盘焦点的悬浮双语字幕窗。

当前限制：仅支持麦克风输入；系统音频采集和 MiMo 分块 ASR 均已推迟到后续版本。课堂记录目前可在应用内查看，Markdown/JSON 导出和完整的睡眠恢复验证不包含在 1.0.0。实现约束见 [MVP 开发文档](docs/MVP_DEVELOPMENT.md)，协作流程见 [版本控制与 Pull Request 规范](docs/VERSION_CONTROL.md)。

## 本地配置

API Key 以明文 JSON 保存在 `~/Library/Application Support/LectureCaption/LocalCredentials.json`，供开发版和 Release 版共用。不要将该文件、业务空间私密配置、签名材料或原始课堂音频提交到 Git；`LocalCredentials.json`、`*-apiKey-*.csv` 和 `.env` 已被 `.gitignore` 排除。
