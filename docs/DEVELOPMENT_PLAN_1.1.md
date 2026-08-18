# LectureCaption 1.1.0 开发计划

> 文档状态：Planned
> 最后更新：2026-08-17
> 基线版本：1.0.1
> 目标版本：1.1.0
> 目标平台：macOS 14+ / Apple Silicon

## 1. 目标

1.1.0 在不破坏现有实时原文链路的前提下，补全课堂记录、导出和窗口能力。本轮包含以下四个独立 feature：

1. 使用阿里云 ASR 返回的句级时间戳建立连续课堂时间轴。
2. 从历史记录导出 UTF-8 TXT 和 JSON，并可选择是否包含时间戳。
3. 支持主窗口原生全屏。
4. 提供显式的防止系统自动息屏按钮。

低延迟实时翻译和悬浮字幕追踪改由 [LectureCaption 1.2.0 开发计划](DEVELOPMENT_PLAN_1.2.md) 在 1.1.0 完成后依次交付。本轮不包含系统音频采集、MiMo ASR、旧记录格式迁移、云同步或 App Store 发布。

## 2. 交付原则

- 原文链路优先。翻译、导出和 UI 状态不得阻塞音频采集、STT 事件处理或字幕稳定器。
- 每个 feature 使用独立分支和 Draft PR，默认 Squash Merge；前一个 feature 完成全部质量门禁后才能开始下一个。
- 现有 `TranscriptStabilizer` 继续作为原文 segment 数组的唯一写入入口。
- 无效的 `Sessions.json` 必须原样保留并明确报错，不迁移、不重命名、不隔离、不删除、不自动替换。
- Debug 与 Release 继续使用独立 Bundle ID、配置目录、密钥和课堂记录。
- 旧历史记录不做回填或重写；新字段或新行为必须避免破坏现有解码规则。

每个 feature 的固定完成流程：

```text
实现 -> 子代理代码审查 -> 修复阻断问题 -> 自动化测试
     -> 主代理可操作的手动测试 -> 用户手工测试清单 -> 用户确认
     -> PR Ready / 合并 -> 下一个 feature
```

功能正确性是当前个人 MVP 的首要目标。对主要功能没有影响或影响极低的缺陷可以记录后暂缓；安全性问题可降低优先级，但 API Key 仍不得进入 Git、日志、课堂记录或导出文件。

## 3. 界面范围

- 维持 1.0.1 主窗口的操作结构和现有配置、历史记录入口。
- 主窗口操作逻辑和视觉层级的重设计从 1.1.0 范围移除，后续由 Issue #36 单独规划、原型验证和交付。
- 本版本的导出入口在现有历史记录界面中实现；不得以未规划导航作为前置条件。

## 4. Feature 交付顺序

### Feature 1：连续课堂时间轴与时间戳显示

目标：使用阿里云服务端时间戳，为实时字幕和历史记录提供准确、稳定的时间。

阿里云 `result-generated` 已提供：

- `sentence.begin_time`：句子开始时间，单位 ms。
- `sentence.end_time`：句子结束时间，单位 ms。
- `sentence.words[]`：字级时间戳，本轮不持久化。
- `sentence_id` 与 `sentence_end`：句子身份及 partial/final 状态。

时间线方案：

- 保留 `CaptionSegment.startedAt` 和 `endedAt`，不引入不必要的历史记录结构迁移。
- 阿里云原始时间属于当前 ASR 任务的音频时间线。自动待机恢复或重连创建新任务时，为任务记录会话偏移量。
- 统一计算：`sessionTime = providerTaskOffset + providerTimestamp`。
- 任务偏移按实际发送音频的位置确定，并包含恢复识别时的预滚音频，避免恢复后的字幕时间跳跃、倒退或重叠。
- 同一 `sentence_id` 的 partial 更新必须保持开始时间稳定；final 只确认文本与结束时间。
- UI 使用 `LectureSession.startedAt + sessionTime` 显示本地 `HH:mm:ss`。
- 仅对新会话保证连续时间轴，不自动改写旧记录。

验收：

- 一次连续识别中时间戳递增，partial 更新不跳动。
- 自动待机恢复和网络重连后，时间戳仍处于同一课堂时间轴且不倒退。
- 实时字幕和已保存记录显示相同时间。
- 原文 segment 数量、文本、状态与加入时间轴前完全一致。

预计：1～2 天。

参考：[阿里云实时语音识别服务端事件](https://help.aliyun.com/zh/model-studio/fun-asr-server-events)。

### Feature 2：历史记录 TXT / JSON 导出

目标：从现有历史记录界面选择一条记录并导出，不暴露内部持久化文件结构。

实现范围：

- 新增独立 `SessionExporter` 和导出 DTO。
- 格式支持 UTF-8 `.txt` 与 `.json`；本轮不实现 Markdown。
- 在历史记录详情中提供格式选择和“包含时间戳”开关。
- TXT 按字幕顺序输出原文和译文；包含时间戳时使用 `[HH:mm:ss]` 前缀。
- JSON 输出稳定、带版本号的公开结构，而不是直接复制 `Sessions.json`。
- 关闭时间戳后，TXT 不显示时间前缀，JSON 不输出会话及 segment 时间字段。
- 默认文件名由清理后的课程名称和课堂日期组成。
- 使用 SwiftUI `fileExporter` 选择保存位置，并明确显示失败原因。

JSON 建议结构：

```json
{
  "formatVersion": 1,
  "course": "Machine Learning",
  "topic": "Optimization",
  "segments": [
    {
      "sequence": 0,
      "sourceText": "Gradient descent converges.",
      "translatedText": "梯度下降会收敛。",
      "startedAtMilliseconds": 12340,
      "endedAtMilliseconds": 14820
    }
  ]
}
```

验收：

- 两种格式均可从历史记录详情导出并由常用编辑器打开。
- 有/无时间戳共四种组合内容正确，顺序与历史详情一致。
- 引号、换行、反斜杠、中文和空译文均正确处理。
- 导出不会修改原始课堂记录，也不包含 API Key、本机路径或内部错误信息。

预计：2 天。

### Feature 3：主窗口原生全屏

目标：让主窗口支持标准 macOS 全屏体验。

实现范围：

- 工具栏增加全屏图标按钮并提供 tooltip。
- 通过主 `NSWindow.toggleFullScreen` 切换，保留系统动画和 `Control-Command-F`。
- 监听窗口全屏状态，使按钮状态与菜单或快捷键触发的变化同步。
- 不改变悬浮字幕窗口层级、可见性、位置和尺寸。

验收：工具栏、系统快捷键和窗口菜单均可正确进入/退出全屏；实时字幕、历史详情和采集状态保持不变。

预计：1 天。

### Feature 4：防止系统自动息屏

目标：用户上课时可显式阻止因空闲导致的显示器睡眠。

实现范围：

- 工具栏增加 `display` 图标 Toggle，默认关闭，并清楚显示开关状态。
- 开启时调用 `ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled], reason: ...)`。
- 关闭、应用退出或状态对象释放时调用 `endActivity`，保证 token 不泄漏。
- 仅阻止空闲息屏，不阻止用户手动睡眠、合盖、关机或锁屏。
- 不需要额外系统权限，不与采集开始/结束自动绑定。

验收：开启后系统空闲息屏计时不生效；关闭或退出后恢复系统默认行为；重复切换只保留一个有效 activity token。

预计：1 天。

## 5. 测试计划

### 5.1 每个 feature 的最低自动化门禁

- `git diff --check`
- `swift test`
- arm64 macOS Debug 构建
- 与改动范围对应的新增单元或集成测试

建议增加的重点测试：

| Feature | 自动化测试重点 |
|---|---|
| 时间轴 | partial 稳定、final 结束时间、预滚、自动待机恢复、重连偏移 |
| 导出 | 四种格式/时间戳组合、转义、空译文、文件名清理、字段排除 |
| 全屏 | 窗口命令路由和状态同步 |
| 防息屏 | activity token 单例、重复切换、退出清理 |

### 5.2 主代理手动测试

- 构建并运行 Debug App，操作所有可由代理控制的界面状态。
- 检查全屏往返、历史详情和导出文件内容。
- 使用模拟 STT 事件观察 partial、final、时间戳和主工作区状态。
- 检查控制台日志中无 API Key、原文链路错误和资源未释放警告。

### 5.3 用户手工测试

每个 feature 开始实现前，必须在 `docs/MANUAL_TEST_CHECKLIST.md` 增加对应编号、前置条件、操作步骤、明确输入、预期输出和记录字段。需要用户实际操作的重点包括：

- 真实麦克风下自动待机、预滚恢复和网络重连后的时间戳连续性。
- Finder 保存面板中的 TXT/JSON 导出和第三方编辑器打开结果。
- macOS 原生全屏、多个桌面和悬浮字幕之间的行为。
- 依据系统实际息屏时长验证防息屏开关。

用户确认必测项全部通过前，对应 feature 不得标记完成或合并。

## 6. 发布与工期

预计总工期：7～9 个开发日，不含等待用户手工测试和外部 API 故障时间。

计划发布为 `1.1.0`。发布前除各 feature 门禁外，还需执行：

- 从 1.0.1 升级启动并读取原有配置与有效历史记录。
- 连续运行 2 小时，覆盖自动待机和恢复。
- 完整回归开始、暂停、继续、结束、保存、历史、悬浮字幕和 Debug/Release 隔离。
- 生成标准命名的 `LectureCaption.app`、ZIP 和 DMG，并同时上传 GitHub Release。

低延迟实时翻译和悬浮字幕追踪在 1.1.0 发布后，按照 [LectureCaption 1.2.0 开发计划](DEVELOPMENT_PLAN_1.2.md) 实施。MiMo ASR 适配继续放在 1.2.0 完成之后，不与本计划中的任何 feature 混合。
