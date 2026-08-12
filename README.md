# LectureCaption

macOS 14+（Apple Silicon）课堂实时字幕 MVP。工程采用 Swift 6.3 与 SwiftUI，主应用通过 `LectureCaption.xcodeproj` 构建；Swift Package 保留用于快速模块测试。

## 开发

```bash
swift build
swift test
```

在 Xcode 中打开 `LectureCaption.xcodeproj` 后，选择 `LectureCaption` scheme 运行。`Resources/Info.plist` 仅声明麦克风权限用途。

当前工程已初始化：

- 主窗口、课程上下文、术语表和会话控制 UI。
- 麦克风音频采集、本地输入活动检测、自动待机和手动暂停。
- 阿里云实时 ASR 的 Provider 抽象。
- DeepSeek 翻译请求抽象。
- Keychain 读写封装。

DeepSeek 翻译、SwiftData 持久化和悬浮字幕窗将在对应 feature 分支中实现。MiMo 分块 ASR 与系统音频采集均不属于当前 MVP，在 MVP 验收后另行评估。实现约束见 [MVP 开发文档](docs/MVP_DEVELOPMENT.md)，协作流程见 [版本控制与 Pull Request 规范](docs/VERSION_CONTROL.md)。

## 本地配置

API Key 以明文 JSON 保存在 `~/Library/Application Support/LectureCaption/LocalCredentials.json`，供开发版和 Release 版共用。不要将该文件、业务空间私密配置、签名材料或原始课堂音频提交到 Git；`LocalCredentials.json`、`*-apiKey-*.csv` 和 `.env` 已被 `.gitignore` 排除。
