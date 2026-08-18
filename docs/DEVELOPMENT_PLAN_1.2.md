# LectureCaption 1.2.0 开发计划

> 文档状态：Planned
> 最后更新：2026-08-17
> 基线版本：1.1.0
> 目标版本：1.2.0
> 目标平台：macOS 14+ / Apple Silicon

## 1. 目标与顺序

`1.2.0` 是 `1.1.0` 完成后的独立迭代，只包含两项对实时阅读体验影响最大的功能：

1. 悬浮字幕最新原文下边界追踪。
2. 不改变原文链路的低延迟实时翻译。

低延迟实时翻译必须最后开发。它会引入 partial 翻译草稿、请求取消和流式显示，只有在 `1.1.0` 的时间轴、导出、全屏和防息屏功能全部完成后才能开始。

本版本不包含系统音频采集、MiMo ASR、旧记录格式迁移、云同步、离线模型或 App Store 发布。

所有 feature 必须遵守仓库根目录的 [`AGENTS.md`](../AGENTS.md)：一个 feature 完整通过子代理审查、自动化测试、主代理手动测试和用户必测确认后，才能开始下一项。

## 2. 共同约束

- 原文识别链路优先。翻译与浮窗 UI 不得阻塞音频采集、STT 事件处理或 `TranscriptStabilizer`。
- `TranscriptStabilizer` 继续作为原文 segment 数组唯一的权威写入入口。
- 无效的 `Sessions.json` 必须原样保留并明确报错；不自动迁移、重命名、隔离、删除或替换。
- Debug 和 Release 保持独立的 Bundle ID、配置目录、API Key 与课堂记录。
- 只实现本计划明确范围，避免增加未要求的兼容层、静默兜底或预设扩展框架。

## 3. Feature 1：悬浮字幕最新原文下边界追踪

目标：让刚加载或持续增长的原文始终保持在悬浮字幕框的可视下边界以内，而不是把最近一条已完成字幕简单居中。

实现方案：

- 使用 `ScrollViewReader`，并在每条原文 `Text` 后放置稳定的 source-bottom anchor。
- 新增 segment、当前 partial 原文变化、显示模式变化、字号变化和面板尺寸变化时，重新追踪最新 source-bottom anchor。
- 以 `.bottom` 对齐可视区域并保留少量底部阅读间距。
- 译文返回不得把追踪目标切换为译文，也不得将刚出现的原文推出字幕框底部。
- 单条原文高于窗口时，保证其最新尾部仍可见。
- 用户主动向上查看旧字幕时的行为必须在原型阶段确认；默认优先保证实时自动跟随。

非目标：不调整原文 partial/final 合并、不改变悬浮窗控制按钮行为、不引入新的窗口类型。

验收：

- 新增和增长中的原文尾部始终在字幕框内。
- 改变字号或窗口大小后追踪位置会重新计算，不出现无限高度、黑框、空白或省略号回归。
- 仅译文变化时不发生无意义跳动。
- 原文、译文和双语三种模式均正常工作。

预计：1～2 天。

## 4. Feature 2：不改变原文链路的低延迟实时翻译

目标：在 ASR 仍输出 partial 时提前获得译文，降低阅读延迟，同时保持现有原文 partial/final 显示、刷新、去重和 final 提交行为不变。

架构：

```text
ASR events -> TranscriptStabilizer -> 原文 segments（保持不变）
                         |
                         +-> LiveTranslationCoordinator
                                  -> partial 翻译草稿
                                  -> final 权威译文
```

实现方案：

- 翻译协调器只订阅 segment 快照，禁止写入或重排原文。
- 使用稳定的 `CaptionSegment.id` 关联 partial 草稿、final 译文和 UI。
- partial 文本稳定约 200～250 ms 后启动翻译，不依赖句号或本地断句。
- 每个 segment 维护单调递增 revision。文本变化后取消或淘汰旧 revision，过期响应不得显示或写回。
- DeepSeek 使用 SSE 流式响应时，将可见 token 更新节流至约 80～120 ms，避免逐 token 刷新造成抖动。
- partial 译文仅保存在独立内存态，不写入历史记录、不进入上下文、不改变 `CaptionState`。
- final 与已经翻译的 partial 完全一致时，提升草稿为正式译文；文本不一致时废弃草稿并立即请求 final 权威译文。
- 连续翻译上下文只包含已确认字幕，避免不稳定 partial 污染后续请求。
- 会话停止、重新开始、Provider 替换或 generation 改变时，取消所有旧任务和流。
- partial 翻译失败只清除草稿，绝不能影响 final 翻译、原文或后续 segment。

核心回归标准：给定相同的 partial/final 事件序列，功能加入前后的原文 segment 数组在 ID、顺序、文本、状态和提交时机上完全一致。

验收：

- 连续讲话时，译文通常在 ASR final 前开始出现。
- 原文仍按既有 partial/final 逻辑实时显示，不因译文刷新而延后、消失、重复或整页刷新。
- 快速修订 partial 时不会显示旧 revision 译文。
- final 后保存的只有与 final 原文对应的正式译文。
- DeepSeek 超时、断网、限流和取消不会影响原文链路。

预计：3～4 天。

## 5. 测试与发布

每个 feature 的最低门禁：

- `git diff --check`
- `swift test`
- arm64 macOS Debug 构建
- 独立子代理代码审查并修复阻断问题
- 主代理可操作的手动测试
- `docs/MANUAL_TEST_CHECKLIST.md` 中对应用户必测用例全部通过

重点自动化测试：

| Feature | 自动化测试重点 |
|---|---|
| 悬浮追踪 | 锚点选择、触发条件、尺寸变化和追踪状态计算 |
| 低延迟翻译 | debounce、revision 淘汰、取消、草稿提升、final 回退和原文零差异 |

用户手工测试必须覆盖：多尺寸悬浮窗、长字幕、字号、三种显示模式、真实 ASR/DeepSeek 网络下的首个译文延迟、partial 修订和 final 一致性。

预计总工期：4～6 个开发日，不含等待用户手工测试、真实 API 延迟和外部服务故障时间。

计划发布为 `1.2.0`。发布前完成 1.1.0 到 1.2.0 升级启动、完整核心流程回归、2 小时运行验证，并生成标准命名的 `LectureCaption.app`、ZIP 和 DMG。

MiMo ASR 与系统音频采集继续放在 `1.2.0` 完成之后独立评估。
