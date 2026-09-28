# 识别延迟诊断

默认关闭，无后台服务器，不调用额外 API，不记录音频、字幕正文、Workspace ID、API Key 或错误正文。仅记录计数与耗时。每个指标最多每 2 秒输出一次，数值是当前进程启动以来的累计 samples/mean/max/total；重启后清零，不是滚动窗口。极短任务的最后一组样本可能未触发下一次输出，不能把无日志解释为零延迟。

## 开启

Xcode：Scheme → Run → Arguments → Environment Variables 添加 `LECTURE_CAPTION_DIAGNOSTICS=1`，重新启动。仅变量值为 1 时开启。

独立运行：完全退出 App 后在终端选择对应版本执行：

```bash
# Release
defaults write com.aquilasky.LectureCaption recognition-diagnostics-enabled -bool true
# Debug（不要混用）
defaults write com.aquilasky.LectureCaption.debug recognition-diagnostics-enabled -bool true
```

随后启动 App，并先在另一个终端运行下列命令再复现延迟：

```bash
/usr/bin/log stream --level info --style compact --predicate 'category == "RecognitionLatency"'
```

也可使用 macOS Console，选当前 Mac 开始流式传输，筛选 `RecognitionLatency`；Xcode 控制台会显示同类消息。记录卡顿发生的本地时间，保留该时刻前后日志。多个版本同时运行时，按 PID/subsystem 区分。日志实时留存最可靠，系统可能回收旧日志。诊断有少量测量开销，不代表完全无扰动性能分析。

关闭：将相应 defaults 值写为 false、移除 Xcode 环境变量并重启。环境变量和 defaults 任一开启即启用。

## 判断卡在哪

| 指标 | 单位 / 含义 |
|---|---|
| captureConversionMS | 音频回调内转换与本地处理耗时；不测量硬件到回调的延迟 |
| captureDeliveryMS | 第一个待交付批次到主线程取走的等待，覆盖批次时仍保留最初等待时间 |
| captureOverwrittenBatches | 待交付批次被覆盖次数，看 total；不是丢失音频秒数 |
| captureConversionFailures | 转换失败次数，看 total，不含错误正文 |
| queuedAudioAgeMS | 普通音频块从采集时间戳到出队的年龄，包括转换、交付、握手及发送排队；排除预滚块 |
| queuedChunks | 入队时队列长度，最大值可略高于既有 250 块上限（测量发生在裁剪之前） |
| droppedChunks | 超过队列上限被丢弃的块数，看 total |
| audioSendMS | await WebSocket send 返回耗时，包括失败发送；不是服务端接收确认或网络 RTT |
| taskReadyMS | 开始建立 Provider 到收到 ready，含建连/鉴权/服务端准备 |
| asrEventGapMS | partial/final 到达的间隔，首个结果从任务开始算；包含静音/断句等待，不能直接等同服务端计算延迟 |
| asrDecodeMS | 收到服务端数据后的本地事件解析耗时 |
| mainActorSchedulingMS | ASR 事件到达后独立 MainActor 探针的等待（含解析），不是实际屏幕呈现耗时 |
| transcriptApplyMS | 主线程字幕稳定与状态赋值耗时，不含 SwiftUI 布局、GPU、翻译或磁盘保存 |

先看积压/丢弃、主线程等待，再看 send 和 ready。若本地指标低，但持续说话时 ASR 间隔很大，只能将范围缩小到云端/网络/断句等待，无法仅凭客户端日志区分它们。可对照供应商状态与网络环境进一步排查，不能直接判定为模型慢。

当前已发现的批次覆盖与队列裁剪是既有行为，本 feature 只观测，不静默修改或“修复”。翻译响应、SwiftUI/GPU 实际帧呈现及音频设备内部延迟不在本轮诊断范围。
