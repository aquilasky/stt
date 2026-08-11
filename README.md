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
- 阿里云实时与 MiMo 分块 ASR 的 Provider 抽象。
- DeepSeek 翻译请求抽象。
- Keychain 读写封装。

云端 API 调用、SwiftData 持久化和悬浮字幕窗将在对应 feature 分支中实现。系统音频采集暂不属于当前 MVP。实现约束见 [MVP 开发文档](docs/MVP_DEVELOPMENT.md)，协作流程见 [版本控制与 Pull Request 规范](docs/VERSION_CONTROL.md)。

## 安全

不要提交 API Key、业务空间私密配置、签名材料或原始课堂音频。`*-apiKey-*.csv`、`.env` 和本地密钥配置已被 `.gitignore` 排除。
