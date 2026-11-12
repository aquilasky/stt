# LectureCaption

LectureCaption 是一款面向课堂和网课的 macOS 实时双语字幕应用。它从默认麦克风采集音频，通过阿里云百炼实时 ASR 显示原文，并可使用 DeepSeek `deepseek-v4-flash` 生成中文译文。

当前版本为 `1.1.3`，支持 macOS 14 及以上版本，仅构建和测试 Apple Silicon (`arm64`)。

## 功能

- 麦克风实时采集和输入音量显示。
- 阿里云 `qwen-audio-3.0-asr-flash-streaming` partial/final 原文识别。
- DeepSeek `deepseek-v4-flash` 异步翻译，支持课程、主题、近期上下文和术语表。
- 本地输入活动检测，静音后停止云端 ASR，重新说话时带 800 ms 预滚自动恢复。
- 完整字幕滚动查看、字号调整和本地课堂记录。
- 阿里云句级时间戳、时间戳显示开关，以及 TXT/JSON 历史记录导出。
- 主窗口原生全屏、防止系统自动息屏，以及从一条或多条历史记录继续录制。
- 始终置顶、不抢键盘焦点的悬浮字幕，支持原文、译文和双语模式。
- Debug 与 Release 的配置、API Key 和课堂记录完全隔离。

当前不支持系统音频采集、Intel Mac、MiMo ASR、离线识别和云同步。详细限制见[已知限制](#已知限制)。

## 系统要求

### 使用发布版本

- Apple Silicon Mac。
- macOS 14 Sonoma 或更高版本。
- 可访问阿里云百炼和 DeepSeek API 的网络。
- 阿里云百炼 Workspace ID 与 API Key。
- DeepSeek API Key，可选；不配置时只显示原文。

### 自行构建

- 上述运行环境。
- Xcode 16 或更高版本，包含 Swift 6 和 macOS SDK。
- Xcode Command Line Tools。
- Git。

项目没有第三方 Swift Package 依赖，也不需要后端服务或数据库。

## 安装与部署

### 使用 DMG 安装（推荐）

1. 打开 [GitHub Releases](https://github.com/aquilasky/stt/releases)，下载最新的 `LectureCaption.dmg`。
2. 双击打开 DMG，将 `LectureCaption.app` 拖入 `Applications`。
3. 推出 DMG，从“应用程序”目录启动 LectureCaption。
4. 第一次启动时允许麦克风权限。

当前发布包使用 ad-hoc 签名，尚未经过 Apple 公证。如果 macOS 阻止首次启动，可在 Finder 中右键点击 `LectureCaption.app`，选择“打开”并确认；也可以前往“系统设置 -> 隐私与安全性”，在安全提示中选择“仍要打开”。

### 使用 ZIP 安装

从 [GitHub Releases](https://github.com/aquilasky/stt/releases) 下载 `LectureCaption.zip`，解压后将 `LectureCaption.app` 移入“应用程序”目录。首次启动和权限处理与 DMG 相同。

安装新版本时退出旧版本并替换 `LectureCaption.app`。应用配置与历史记录位于 `~/Library/Application Support`，替换应用本身不会删除这些数据。

## API 准备

### 阿里云百炼实时 ASR（必需）

1. 在阿里云百炼开通实时语音识别服务。
2. 创建 API Key，并取得对应业务空间的 Workspace ID。
3. 确认 Workspace 所在地域是“北京”还是“新加坡”。
4. 在 LectureCaption 工具栏的“API 配置 -> 阿里云识别”中填写：
   - `Workspace ID`
   - 地域
   - API Key

Workspace ID、API Key 和地域必须属于同一个百炼业务空间。应用使用的 WebSocket 地址由 Workspace ID 和地域组合生成，地域选错通常会导致“阿里云 WebSocket 连接失败”或服务器响应错误。

接口参考：[阿里云实时语音识别 WebSocket API](https://help.aliyun.com/zh/model-studio/fun-asr-realtime-websocket-api)。

### DeepSeek 翻译（可选）

1. 创建可调用 DeepSeek API 的 API Key。
2. 在工具栏的“API 配置 -> DeepSeek 翻译”中填写 API Key。
3. 从未保存 DeepSeek Key 时，输入框留空即可只识别和保存原文。

当前客户端直接请求 `https://api.deepseek.com/chat/completions`，模型固定为 `deepseek-v4-flash`。翻译请求只包含确认后的字幕、课程上下文和术语表，不包含音频。

保存过 DeepSeek Key 后，输入框留空表示继续使用本地已保存值，不会关闭翻译。当前版本没有应用内清除按钮；如需停用翻译，请退出应用，在对应的 `LocalCredentials.json` 中移除 `deepseek_api_key` 字段并保持文件为有效 JSON。

## 应用配置

工具栏提供两个同级入口：“课程配置”（书本图标）和“API 配置”（钥匙图标）。各自打开独立表单，点击左上角返回箭头回到实时字幕；关闭重开会保留已编辑的字段与已添加术语。窗口较窄时部分按钮会进入原生工具栏溢出区。

“API 配置”包含供应商连接和自动待机设置：

| 配置 | 说明 |
|---|---|
| 识别 | 当前仅支持阿里云实时 ASR。 |
| 自动待机 | 可选择关闭、15 秒、30 秒或 60 秒；默认 30 秒。持续静音后停止云端任务，本地麦克风检测仍继续。 |
| Workspace ID | 阿里云百炼业务空间 ID，必须与地域和 API Key 匹配。 |
| 地域 | 支持北京和新加坡。 |
| 阿里云 API Key | 必需。点击“开始”时保存到本机，输入框随后清空。 |
| DeepSeek API Key | 可选。点击“开始”时保存到本机，输入框随后清空；之后留空仍会使用已保存值。 |

“课程配置”包含课堂上下文：

| 配置 | 说明 |
|---|---|
| 课程名称 | 可选，用于本地记录标题和翻译上下文。 |
| 本节主题 | 可选，帮助翻译模型理解当前内容。 |
| 原文语言 | 自动、英语或中文；明确选择通常比自动检测更稳定。 |
| 译文语言 | 支持简体中文和英语。 |
| 术语表 | 填写“原文 -> 译文”。原文词会同时用于阿里云词表增强，完整映射用于 DeepSeek 翻译。 |

## 使用方法

1. 启动应用，打开“API 配置”，至少填写阿里云 Workspace ID、地域和 API Key，按需填写 DeepSeek API Key。
2. 打开“课程配置”，按需填写课程名称、主题、语言和术语表。
3. 点击工具栏“开始”。首次使用时在 macOS 权限弹窗中允许麦克风访问。
4. 对默认系统麦克风说话。应用先进行本地输入检测，检测到声音后才建立阿里云 ASR 任务：
   - 较浅文字是仍在变化的临时原文。
   - 确认后的原文不再变化，并进入翻译和保存流程。
   - 配置 DeepSeek 后，译文在确认原文之后异步出现。
5. 使用“暂停”停止当前云端任务；点击“继续”后，本地检测恢复，并在检测到声音时重新连接。
6. 使用主窗口的字号减小/增大按钮调整字幕大小。
7. 启用“悬浮字幕”后，可拖动和调整浮窗尺寸。鼠标移入浮窗可调整字号、显示模式、背景不透明度或关闭浮窗。
8. 点击“保存记录”可在会话进行中保存当前已确认字幕；点击“结束”会结束采集并保存已确认内容。
9. 从工具栏的“本地课堂记录”查看或删除已保存课程。

自动待机期间不会向阿里云发送音频。重新检测到声音时，应用会创建新任务并发送约 800 ms 的内存预滚音频，减少句首丢失。手动暂停不会被声音自动解除。

## 本地数据与隐私

在“API 配置”中向下滚动可查看“API 用量”，支持今天、最近 7 天、最近 30 天和全部。语音按实际成功发送的音频秒数统计，每 30 秒及任务结束更新；翻译使用成功响应的 Token 明细。跨本地日期的语音分桶保存，任务数去重。

费用为独立的 CNY/USD 估算，价格快照核实于 2026-10-05；每条记录保留当时单价，更新应用不会重新定价旧记录。DeepSeek 旧模型名称按当前 Flash 价格，考虑 UTC 峰谷、周末和内置的 2026 中国节假日；未知模型或日历未覆盖的年份显示无法估算。最终费用以供应商账单为准，免费额度、优惠、税费、舍入和失败/取消请求费用不计入本地估算。[阿里云价格](https://help.aliyun.com/zh/model-studio/model-pricing)、[DeepSeek 价格](https://api-docs.deepseek.com/quick_start/pricing/)。

统计仅从此版本的新请求开始，旧课堂不回填。用量写入错误单独显示在 API 配置中，不阻断字幕；异常退出可能损失最近 30 秒尚未提交的语音快照。无效 APIUsage.json 原样保留并报告完整路径，需手动检查后重启；不自动修复。

客户端直接连接阿里云和 DeepSeek，不经过项目自有服务器：

- 检测到输入后，麦克风 PCM 音频发送至阿里云实时 ASR。
- 只有在配置 DeepSeek 后，确认的原文及有限课程上下文才发送至 DeepSeek。
- 音频默认不落盘。
- API Key 以明文 JSON 保存于本机，不使用 Keychain。
- API Key 不应出现在日志、课堂记录、导出文件或 Git 中。
- 云端请求可能产生供应商费用，请在对应控制台查看用量和限额。

Release 数据目录：

```text
~/Library/Application Support/LectureCaption/
├── LocalCredentials.json
├── Sessions.json
└── APIUsage.json
```

Debug 数据目录：

```text
~/Library/Application Support/LectureCaption-Debug/
├── LocalCredentials.json
├── Sessions.json
└── APIUsage.json
```

两套目录互不读取。如果 `Sessions.json` 格式无效，应用会报告文件完整路径，并保留原文件；不会自动迁移、重命名、隔离、删除或替换它。

卸载 `LectureCaption.app` 不会自动删除上述目录。需要清除本地配置或记录时，请先退出应用，在 Finder 中使用“前往 -> 前往文件夹”打开对应目录，确认内容后手动处理。

## 从源码构建

### 获取源码

```bash
git clone git@github.com:aquilasky/stt.git
cd stt
```

没有配置 GitHub SSH 时，也可以使用：

```bash
git clone https://github.com/aquilasky/stt.git
cd stt
```

### 使用 Xcode 运行

1. 打开 `LectureCaption.xcodeproj`。
2. 选择 `LectureCaption` scheme 和“My Mac”目标。
3. 按 `Command-R` 构建并运行 Debug App。
4. 在系统提示时授予 Debug App 麦克风权限。

Debug Bundle ID 为 `com.aquilasky.LectureCaption.debug`，使用 `LectureCaption-Debug` 数据目录，因此不会读取已安装 Release App 的 API Key 或历史记录。

### 使用命令行构建完整 App

```bash
xcodebuild \
  -project LectureCaption.xcodeproj \
  -scheme LectureCaption \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/xcode-debug \
  build
```

构建结果位于：

```text
.build/xcode-debug/Build/Products/Debug/LectureCaption.app
```

可以在 Finder 中打开，或执行：

```bash
open .build/xcode-debug/Build/Products/Debug/LectureCaption.app
```

### SwiftPM 编译与测试

```bash
swift build
swift test
```

`swift build` 用于快速检查核心模块，不会生成带 `Info.plist`、应用图标和麦克风用途说明的完整 `.app`。需要实际使用或测试权限时，应通过 Xcode 工程构建。

公开仓库使用标准 GitHub 托管 macOS runner 执行测试与构建；工作流拒绝在私有仓库运行，不使用 larger runner、缓存/产物上传或自动发布。提交前仍须在本机执行空白检查、`swift test` 与 arm64 Xcode App 构建。

敏感文件检查使用固定版本的本地 Gitleaks，运行 `bash Scripts/check-secrets.sh staged`、`worktree` 和 `history` 三种模式。安装与扫描范围见 [本地敏感文件检查](docs/LOCAL_SECURITY_CHECKS.md)。

## 打包 Release

仓库提供 `Scripts/create-release.sh`，使用 Xcode Release 配置构建 arm64 App，并生成 APP、ZIP 和 DMG：

```bash
Scripts/create-release.sh
```

默认输出：

```text
Release/LectureCaption.app
Release/LectureCaption.zip
Release/LectureCaption.dmg
```

如果这些目标已存在，脚本会停止而不是覆盖。确认需要替换这三个产物时执行：

```bash
Scripts/create-release.sh --replace
```

未指定签名身份时使用 ad-hoc 签名。需要使用本机已有证书签名时：

```bash
CODE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  Scripts/create-release.sh
```

脚本使用本次打包独有的临时 DerivedData，显式关闭 Release coverage/profile 插桩，并映射 Release 源码路径（不改变 Debug）。签名前检查 App，再检查最终 APP、ZIP 和只读挂载的 DMG 中的主可执行文件；发现插桩或开发机路径时返回非零，不报告打包成功。可单独运行 `bash Scripts/check-release-privacy.sh <资产路径>`，回归测试为 `bash Scripts/test-release-privacy.sh`（需要本机 Xcode、ripgrep 和磁盘镜像挂载能力）。详见 [发布隐私检查](docs/RELEASE_PRIVACY.md)。

脚本会执行 `codesign --verify --deep --strict`，但不会自动完成 Apple notarization。发布前还应核对版本号、运行 Release App，并计算产物校验值：

```bash
shasum -a 256 Release/LectureCaption.zip Release/LectureCaption.dmg
```

发布资产文件名不包含版本号；版本由应用元数据、Git tag 和 GitHub Release 表示。每次正式发布必须同时准备 `LectureCaption.app`、`LectureCaption.zip` 和 `LectureCaption.dmg`。

## 常见问题

### 偶发识别延迟很大，如何定位

可开启默认关闭的本地耗时诊断，查看采集交付、发送积压、ASR 返回间隔与主线程等待。Xcode 使用环境变量 `LECTURE_CAPTION_DIAGNOSTICS=1`；独立运行使用对应 Bundle ID 的本地 defaults 开关。具体命令、指标含义与限制见 [识别延迟诊断](docs/RECOGNITION_DIAGNOSTICS.md)。只记录数值，不记录音频、字幕正文或 API Key，不使用远端监控服务。

### 点击“开始”后仍显示“本地监听”

这是正常的成本控制行为。应用先在本机检测输入，只有检测到足够音量后才连接阿里云。开始说话后状态应切换为“正在连接”或“正在识别”。

### 音量持续显示 `-96 dBFS`

确认已授予麦克风权限，并在“系统设置 -> 声音 -> 输入”中选择有信号的默认麦克风。更换默认输入设备后，结束当前会话并重新开始。

### 麦克风权限被拒绝

前往“系统设置 -> 隐私与安全性 -> 麦克风”，为 LectureCaption 打开权限，然后重新启动应用。Debug 与 Release Bundle ID 不同，系统可能分别请求授权。

### 无法连接阿里云或提示服务器响应错误

在 `1.1.1` 端点校验修复发布前，Workspace ID 只能从阿里云百炼控制台直接复制，不要填入 URL、主机名或第三方提供的值。当前版本会用该字段组成携带 API Key 的 WebSocket 地址。

依次确认：

1. Workspace ID 没有多余空格。
2. API Key 属于对应业务空间且仍有效。
3. 北京/新加坡地域与 Workspace 一致。
4. 当前网络可以访问对应阿里云 WebSocket 服务。

应用只在检测到声音后建立连接，因此排查时需要持续说话或向默认麦克风提供清晰输入。

### 有原文但没有译文

确认已经配置有效的 DeepSeek API Key。当前版本只翻译 ASR 确认后的 final 原文，临时原文不会触发翻译；翻译失败不会中断原文识别。

### 提示本地课堂记录文件格式无效

错误消息会给出 `Sessions.json` 的完整路径。应用不会自动修复或替换该文件。先退出应用并备份原文件，再手动检查 JSON 内容或根据实际需要处理；不要用 Debug 的 `Sessions.json` 覆盖 Release 文件。

### LLDB RPC Server 占用大量内存

该进程属于 Xcode 调试环境，不包含在独立 Release App 中。停止 Xcode 调试或直接运行 `Release/LectureCaption.app` 可判断问题是否仅存在于调试器。

## 已知限制

- 仅支持默认麦克风输入；不采集浏览器、会议软件或播放器的系统音频。
- 仅支持 Apple Silicon，未针对 Intel Mac 优化或发布。
- MiMo ASR 已推迟到 MVP 后评估。
- DeepSeek 当前只翻译 final 原文；partial 流式低延迟翻译是 `1.2.0` 计划的唯一 feature。
- 支持 TXT/JSON 导出，但不支持 Markdown 导出或历史记录编辑。
- 阿里云端点校验、本地敏感文件防护和 Release 隐私清理安排在 `1.1.1`～`1.1.3`，并优先于后续界面改进。
- 当前开发分支已包含悬浮字幕下边界追踪、主界面智能跟随、动态开始/继续入口及课程与 API 配置分离；本地 API 用量与估算费用正在 `1.1.8` 验收。正式发布功能以对应 Release 为准。
- 历史发布产物可能包含 LLVM coverage/profile 字符串或开发机绝对源码路径；静态检查未发现真实凭据，后续产物由 `1.1.3` 增加强制检查，旧 Release 不重写。
- 在持续、低音量且稳定的输入下，本地活动检测可能误触发自动待机，详见 [Issue #53](https://github.com/aquilasky/stt/issues/53)。
- 应用未经过 Apple 公证，也没有自动更新机制。
- 2 小时稳定性和完整睡眠/唤醒恢复仍需继续验证。

## 开发文档

- [1.1.0 开发计划](docs/DEVELOPMENT_PLAN_1.1.md)
- [1.1.x 开发计划](docs/DEVELOPMENT_PLAN_1.1_X.md)
- [1.2.0 开发计划](docs/DEVELOPMENT_PLAN_1.2.md)
- [MVP 架构与实现说明](docs/MVP_DEVELOPMENT.md)
- [版本控制与 Pull Request 规范](docs/VERSION_CONTROL.md)
- [手工测试清单](docs/MANUAL_TEST_CHECKLIST.md)
- [1.0.1 发布说明](docs/releases/1.0.1.md)
- [1.1.0 发布说明](docs/releases/1.1.0.md)
- [Agent 开发约束](AGENTS.md)

提交代码前请阅读 `AGENTS.md`。项目严格按单 feature 顺序开发，每个 feature 必须完成独立子代理审查、自动化测试、主代理手动测试和用户必测确认后才能合并。
