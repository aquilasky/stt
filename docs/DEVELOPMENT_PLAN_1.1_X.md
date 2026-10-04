# LectureCaption 1.1.x 开发计划

> 文档状态：In Progress
> 最后更新：2026-10-05
> 基线版本：1.1.0
> 目标版本：1.1.1 ～ 1.1.8
> 目标平台：macOS 14+ / Apple Silicon

## 1. 目标与版本顺序

2026-09-28 进度：Feature 1～3、macOS 27 浮窗兼容修复及延迟诊断均已获用户合并授权并合并（PR #64/#65/#66/#68/#70）。用户授权将这些已完成改动汇总发布为 1.1.3，本次不补发独立 1.1.1/1.1.2。Feature 4～8 和 1.2 尚未开始。用户同日授权公开仓库并恢复标准免费 GitHub CI，此授权与 AGENTS.md 新规则优先于本文旧的全面禁止 CI 条款。

2026-09-30 进度：Feature 4～6 已通过用户手工验收并合并（PR #73/#75/#77）。Feature 7 从 Issue #78 开始，拆分课程与 API 配置；Feature 8 和 1.2 尚未开始。

2026-10-01 进度：Feature 7 完成独立审查、76 项本地测试、arm64 Debug 构建、本地密钥扫描及主代理 UI 验证，用户确认 MAN-111 通过（PR #79）。下一项为 Feature 8：本地 API 用量与估算费用；1.2 尚未开始。

`1.1.x` 是 1.1.0 发布后的兼容改进序列。每个 feature 独立完成质量门禁、用户手工确认和发布，固定顺序如下：

| 版本 | Feature | 用户结果 |
|---|---|---|
| `1.1.1` | 阿里云端点信任边界 | 非法 Workspace ID 无法改变连接主机或接触 API Key |
| `1.1.2` | 本地敏感文件提交防护 | 运行数据、凭据和私钥材料不易被误提交 |
| `1.1.3` | Release 插桩与路径清理 | 发布产物不包含 coverage runtime 或开发机绝对路径 |
| `1.1.4` | 悬浮字幕最新内容下边界追踪 | 新原文始终完整进入浮窗可视区域 |
| `1.1.5` | 主界面智能跟随 | 用户查看历史字幕时不再被新内容强制拉回 |
| `1.1.6` | 合并开始与继续入口 | 初次开始和暂停后继续使用同一个主按钮 |
| `1.1.7` | 分离课程配置与 API 配置 | 课程上下文和供应商凭据各自拥有独立入口 |
| `1.1.8` | API 用量与估算费用 | 本地按时间查看语音时长、翻译 Token 和费用估算 |

前三个补丁版本处理已经确认的安全和发布隐私问题，优先于交互改进。悬浮字幕追踪仍保留在本计划，`1.2.0` 只包含不改变原文链路的低延迟实时翻译，并且必须等 `1.1.8` 完成后才能开始。

本计划不包含低延迟 partial 翻译、自动暂停算法修复、系统音频采集、MiMo ASR、历史记录格式迁移、云同步、离线模型或 App Store 发布。自动暂停误判仍由 [Issue #53](https://github.com/aquilasky/stt/issues/53) 独立跟踪。

## 2. 共同约束

### 临时诊断功能（2026-09-28，Issue #69）

用户已确认 PR #66 和 #68 并要求合并；新增独立诊断 feature，优先定位偶发识别高延迟。范围仅为默认关闭、Debug/Release 均可启用的本地数值日志：采集转换、主线程调度、采集批次覆盖、发送积压与丢弃、网络 send 等待、ASR 返回间隔、解码及字幕状态更新。不记录音频、文本或凭据，不上传、不改变队列/暂停/识别策略。完成审查、本机测试与用户日志验证后恢复既定版本顺序，不混入 1.1.4 或 1.2 实现。

### 临时兼容性修复（2026-09-27，Issue #67）

用户确认全区域拖动恢复后反馈缩放失效及历史缩放命中区过小，同一修复增加显式四边/四角缩放：四边 14 点、角落 24×24 点，遵守既有最小/最大尺寸，不变更字幕布局或跟随策略。

用户升级 macOS 27 后报告悬浮字幕无法拖动，临时优先处理此回归。使用独立修复分支与 PR，恢复文字及空白区域的原生窗口拖动，不使用专用箭头替代原有操作；排除按钮、原生滚动条与缩放边缘，不改变字幕刷新、跟随、滚动或非激活窗口行为。PR #66 和 #68 已于 2026-09-28 获用户确认并合并；此修复不代表开始 1.1.4。恢复原计划顺序。

- 严格按 Feature 1 到 Feature 8 顺序开发。前一项未完成子代理审查、本地自动化测试、主代理手动测试和用户必测确认前，不得开始下一项。
- 原文识别链路优先。滚动、配置、用量统计和费用计算不得阻塞或改变音频采集、STT 事件处理、`TranscriptStabilizer` 或既有 partial/final 行为。
- 任何由用户输入影响的网络端点必须先完成允许列表校验，再读取或附加 API Key；不能把 URL 解析成功视为端点可信。
- 所有滚动实现必须支持 macOS 14，不使用仅 macOS 15+ 可用的 `onScrollPhaseChange` 或 `onScrollGeometryChange`。
- 不使用 GitHub Actions、托管 CI/CD、Codespaces 或其他可能产生费用的托管服务。测试、密钥扫描、构建和发布产物检查全部在本机执行。
- Debug 与 Release 继续使用独立 Bundle ID、配置目录、API Key、课堂记录和用量记录。
- 不修改 `Sessions.json` 格式，不把用量或费用字段写入课堂记录、字幕导出或 API Key 配置文件。
- 新增的用量数据只保存在本机；无效数据必须保留原文件并明确报错，不自动修复、迁移、重命名或替换。
- 每个 feature 使用独立 Issue、分支和 PR，默认 Squash Merge。每个补丁版本完成后再按发布规范生成 APP、ZIP 和 DMG。

## 3. Feature 1：阿里云端点信任边界（1.1.1）

关联：[Issue #60](https://github.com/aquilasky/stt/issues/60)

目标：恶意 Workspace ID 必须在读取 API Key 或建立连接之前被拒绝，最终 WebSocket 请求只能发送到用户所选地域的阿里云固定端点。

已确认风险：当前实现将 Workspace ID 直接插入 URL，再为解析出的 URL 附加 `Authorization: Bearer`。输入 `attacker.example/x`、userinfo 或编码分隔符可能改变 URL 的实际主机，使 API Key、术语和后续麦克风音频离开阿里云信任边界。

输入与端点合同：

- 阿里云公开文档只说明 Workspace ID 是 Base URL 的一个主机标签，没有公开更窄的字符规范。本 feature 按单个 ASCII DNS label 校验：长度 `1...63`，仅允许 ASCII 英文字母、数字和连字符，首尾必须是字母或数字，不允许点、斜杠、冒号、`@`、百分号、Unicode、控制字符或内部空白。
- 保留当前配置入口对首尾普通空白的显式清理；清理后的值必须完整满足上述合同。不得使用会接受部分匹配的正则表达式。
- 使用 `URLComponents` 或等价结构化 API 构造端点，不再把未经验证的文本直接插入 URL 字符串。
- URL 生成后再次验证：`scheme == wss`；`user`、`password`、`port`、`query` 和 `fragment` 均为空；path 精确为 `/api-ws/v1/inference`；host 经 ASCII 小写规范化后精确等于“已校验 Workspace ID + 当前 `Region.hostSuffix`”的同样规范化结果。地域后缀只能来自现有北京/新加坡 enum 允许列表。
- `X-DashScope-WorkSpace` 请求头只能使用同一个已校验值，避免 URL 与 Header 使用不同的输入。
- Provider 的启动顺序改为“校验并生成可信端点 -> 读取 API Key -> 构造请求 -> connect”。无效端点不得调用 API Key loader 或 transport。
- UI 显示明确的 Workspace ID 格式错误；错误、日志和测试输出不得包含 API Key。

非目标：不增加证书固定、服务端代理、新地域、Provider 回退、自动修复 Workspace ID 或新的重试逻辑。

验收：

- 合法边界值能生成北京或新加坡的唯一预期 URL，并继续完成现有连接流程。
- `attacker.example/x`、`user@host`、`workspace%2Fpath`、Unicode 句点/斜杠、换行、内部空白、前后连字符和超过 63 字符的输入均在本地失败。
- 每个非法输入都满足 API Key loader 调用次数为 0、transport connect 调用次数为 0、音频发送次数为 0。
- 最终请求的 scheme、host、path、userinfo、port、query 和 fragment 全部与端点合同一致。
- 一次有效真实 Workspace 的短会话仍能识别原文，鉴权失败提示仍经过脱敏。

自动化测试重点：Workspace ID 边界与攻击样例、URL 组成字段、Provider 调用顺序、Header 值，以及无效输入不接触凭据或网络。

用户必测重点：配置一个有效 Workspace 完成短会话；分别输入带点、斜杠、`@` 和内部空格的值，确认应用立即报格式错误且不会进入连接状态。

预计：0.5～1 个开发日。

## 4. Feature 2：本地敏感文件提交防护（1.1.2）

关联：[Issue #61](https://github.com/aquilasky/stt/issues/61)

目标：在不使用托管 CI 的前提下，降低本机配置、课堂记录、发布目录和私钥材料被误提交或进入正式发布的风险。

实现方案：

- 在 `.gitignore` 中明确覆盖 `Release/`、`Sessions.json`、`APIUsage.json`、`LocalCredentials.json`、`*.pem`、`*.key`、`*.pfx`，并保留现有 `.env`、`*.p8`、`*.p12`、音频和构建目录规则。
- 新增版本固定的 Gitleaks 配置与本地脚本，提供 staged、worktree 和 history 三种明确模式；扫描命令不得上传仓库内容，也不得在缺少工具时静默跳过。
- staged 扫描用于提交前快速检查；worktree 与 history 扫描是安全相关 PR 和每次 Release 的强制本地门禁。完整扫描结果记录在 PR 或发布说明中。
- 可提供仓库内的 pre-commit hook，但只能由用户显式安装；脚本不得自动修改全局 Git 配置或从网络下载可执行文件。
- allowlist 只接受路径和内容都明确的合成测试 fixture，不允许用宽泛正则忽略真实 DashScope、DeepSeek、PEM 或证书格式。
- 扫描发现问题时返回非零状态并打印可定位证据；不得自动删除文件、轮换密钥、修改提交或重写 Git 历史。

非目标：不恢复 GitHub Actions，不使用付费扫描服务，不自动安装 Homebrew 软件，不在本 feature 处理已经泄露凭据的轮换或历史改写。

验收：

- `git check-ignore` 能确认默认运行数据、Release 目录和列出的签名材料被忽略，正常源码与测试 fixture 不被误忽略。
- 合成 API Key 或私钥出现在 staged 内容、未提交工作区或历史 fixture 时，本地扫描对应模式均明确失败。
- 当前没有需要放行的误报，因此不配置项目 allowlist；验证行内 allow 标记和 `.gitleaksignore` 不能绕过扫描。将来确有合成 fixture 误报时，才增加同时限定路径与内容的例外及回归测试。
- 本机未安装 Gitleaks 时脚本给出版本和安装说明并失败，不把“未扫描”报告为通过。
- 安全扫描全过程不调用 GitHub Actions、Marketplace App 或其他托管服务。

自动化测试重点：ignore 规则、脚本参数和退出码、三种扫描范围、私钥识别、输出脱敏、忽略标记不能绕过，以及缺少/版本不匹配的工具行为。

用户必测重点：按文档安装或确认本地 Gitleaks，创建不含真实凭据的合成敏感文件，验证提交前阻断和删除 fixture 后恢复通过。

预计：0.5～1 个开发日。

## 5. Feature 3：Release 插桩与开发机路径清理（1.1.3）

关联：[Issue #62](https://github.com/aquilasky/stt/issues/62)

目标：未来发布的 APP、ZIP 和 DMG 不包含 LLVM coverage/profile runtime、`.profraw` 标记或开发机绝对源码路径，且发现回归时打包必须失败。

已确认风险：现有本地 Release 可执行文件包含 `__llvm_profile` runtime 和 `default.profraw` 字符串；历史 `v1.0.0`/`v1.0.1` 产物还被报告包含 `/Users/<用户名>/.../Sources/...` 绝对路径。旧标签和旧 Release 保持不变，只在后续版本发布说明中记录限制。

实现方案：

- 在项目级和 App target 的 Release build settings 中显式设置 `CLANG_ENABLE_CODE_COVERAGE = NO`、`GCC_GENERATE_TEST_COVERAGE_FILES = NO` 和 `GCC_INSTRUMENT_PROGRAM_FLOW_ARCS = NO`，并关闭 Swift profile generation，不依赖 Xcode 默认值。
- `Scripts/create-release.sh` 的 `xcodebuild` 命令再次显式传入对应 Release 禁用设置，避免本机 scheme 或环境状态重新启用插桩。
- 每次打包在当前 staging 目录下使用全新的临时 DerivedData，不再复用固定的 `.build/release-package`；脚本退出时只清理本次明确创建的临时目录。
- 如关闭插桩后仍存在绝对源码路径，只对 Release 添加 Swift `-file-prefix-map`/`-debug-prefix-map`，将仓库根路径映射为稳定的非个人路径；不改变 Debug 的诊断信息。
- 新增只读的发布产物检查：拒绝 `__llvm_profile`、`default.profraw`、其他 `.profraw`、`/Users/`、当前仓库绝对路径以及绝对 `Sources/LectureCaption` 路径。
- 先检查签名前的 App，再分别从最终 APP、ZIP 和 DMG 解析出可执行文件复检。任一资产检查失败时不得打印“打包完成”或进入 GitHub Release。
- 保留现有 ad-hoc/Developer ID 签名选择、`codesign --verify --deep --strict`、标准资产命名和 Debug/Release 数据隔离。

非目标：不重写历史发布、不引入 Apple notarization、远端构建、符号服务器、混淆器或新的签名服务。

验收：

- Release 编译命令不再包含 `-profile-generate`、`-profile-coverage-mapping` 或等价 profile 插桩参数。
- APP、ZIP 和 DMG 内的 arm64 主可执行文件均不含禁止的 runtime、`.profraw` 或开发机绝对路径字符串。
- 人为注入一条禁止字符串的合成 fixture 时，发布检查以非零状态失败并指出资产与匹配类别。
- Debug 测试仍可按需收集覆盖率，Release App 可启动并完成一次本地监听/短识别，签名与三种资产结构验证通过。
- 发布说明明确记录本次修复和旧产物限制，不移动标签、不替换历史 Release 资产。

自动化测试重点：Release build settings、禁止字符串扫描、APP/ZIP/DMG 解包路径、失败退出码和无误报的干净 fixture。

用户必测重点：安装新 DMG，启动独立 Release App，确认麦克风、API 配置和课堂记录正常且没有生成 `default.profraw`。

预计：1 个开发日。

## 6. Feature 4：悬浮字幕最新内容下边界追踪（1.1.4）

目标：悬浮字幕从可视区域顶部自然排版；只有最新内容增长到可视区域下边界以外时，才向上滚动以露出其尾部。不得把短字幕或最近一条已完成字幕强行推到窗口底部。

实现方案：

- 在每条字幕的原文末尾放置稳定的 source-bottom anchor，并使用 `ScrollViewReader` 定位。
- 原文和双语模式始终追踪最新可见原文的 source-bottom；仅译文模式追踪最新可见译文的 translation-bottom。
- 新 segment、当前 partial 原文增长、显示模式变化、字号变化和面板尺寸变化后重新计算追踪位置。
- 译文返回不得在原文或双语模式下更换追踪目标，也不得把刚出现的原文推出下边界。
- 滚动内容不增加填满视口的前置占位；`ScrollView` 在内容未溢出时保持顶部位置，溢出后才用 `.bottom` 目标对齐，保留窗口原有的底部内边距。单条字幕高于窗口时仍保证其最新尾部可见。
- 保持浮窗实时自动跟随。主界面的手动浏览状态不与浮窗共享。
- 不给滚动内容施加无界高度，不改变现有面板尺寸、圆角、悬停控件层级和文本自动换行约束。

非目标：不改变浮窗按钮、窗口层级、partial/final 合并、翻译请求或主窗口滚动。

验收：

- 连续增长的长原文始终自动换行，尾部不出现省略号且位于浮窗下边界以内。
- 内容少于窗口高度时，第一行从字幕区域顶部开始显示；新增内容仍可见时不发生无意义滚动，越过下边界后才开始向上滚。
- 译文异步返回时，最新原文不被推出可视区域，浮窗不发生无意义跳动。
- 改变字号、透明度、显示模式和窗口尺寸后追踪正确，不出现无限长黑框、空白内容或单角圆角回归。
- 原文、译文和双语模式均可连续运行，浮窗仍不抢键盘焦点。

自动化测试重点：追踪目标选择、仅原文变化触发、显示模式切换、字号/尺寸触发，以及长文本布局约束。

用户必测重点：真实 ASR partial 增长、长英文与中文混排、三种模式、多种浮窗宽高和字号。

预计：1～2 个开发日。

## 7. Feature 5：主界面智能跟随（1.1.5）

目标：保留歌词式的当前确认行强调和识别中内容布局，但取消用户浏览历史字幕时的强制跟随。

跟随状态：

```text
following
  -> 用户滚轮、触控板或滚动条拖动
browsingHistory
  -> 连续 3 秒没有新的手动滚动、手动滚到最底部，或点击悬浮向下箭头
following
```

实现方案：

- 将“是否自动跟随”作为 `CaptionPreviewView` 的本地 UI 状态，不写入 `AppState`、课堂记录或用户配置。
- 用户发起滚动时进入 `browsingHistory`。此后新增 final、partial 增长、译文返回和字号变化都不得改变当前浏览位置。
- 每次新的手动滚动都重新计算 3 秒无操作期限；到期后一次性滚动到最新内容并恢复 `following`。若用户手动滚到内容最底部（容差 40 点），立即恢复跟随并取消期限。
- 浏览态提供只在需要时显示、底部居中的圆形悬浮向下箭头，使用轻量材质而非醒目的文字主按钮；保留“回到最新”辅助功能标签，点击立即恢复跟随。
- `following` 状态下仍使用现有歌词式焦点：上一条已确认内容强调，识别中的内容位于其下方；回到底部后保留舒适阅读间距。
- macOS 14 使用窄范围 AppKit bridge 观察 `NSScrollView` 的 live-scroll 通知，区分用户滚动和 `ScrollViewReader` 的程序化滚动；不为此重写整个字幕列表。
- 新会话、续录准备完成或字幕清空时重置为 `following`。遵守“减少动态效果”系统设置。

非目标：不改变字幕排序、焦点行定义、字号动画、悬浮字幕跟随或时间戳数据。

验收：

- 用户向上浏览后，即使持续产生原文和译文，视口也保持在用户选择的位置。
- 用户持续滚动时不会提前恢复；最后一次手动滚动约 3 秒后自动回到最新内容。手动滚到最底部则立即恢复跟随，箭头消失。
- 圆形悬浮向下箭头可立即恢复，且程序化滚动不会被误判为新的用户操作。
- 正常跟随时当前确认行、历史清晰度和底部识别中内容保持 1.1.0 的视觉行为。

自动化测试重点：`following`/`browsingHistory` 状态转换、3 秒期限重置、底部容差与立即恢复、过期任务取消、新会话重置和程序化滚动排除。

用户必测重点：鼠标滚轮、触控板惯性滚动、滚动条拖动、持续字幕输入和全屏窗口。

预计：1～2 个开发日。

## 8. Feature 6：合并开始与继续入口（1.1.6）

目标：初次开始会话和手动暂停后的继续使用同一个动态主按钮，去掉当前长期并列的“开始”和“继续”按钮。

行为映射：

| 会话状态 | 主按钮 | 行为 |
|---|---|---|
| `idle` / `completed` | 开始 | 调用现有异步 `startSession()` |
| `manuallyPaused` | 继续 | 调用现有 `resumeSession()` |
| 其他活动状态 | 不可用 | 不执行新的生命周期操作 |

实现方案：

- 保留独立的“暂停”和“结束”按钮；本 feature 只合并“初次开始”与“暂停后继续”。
- 主按钮的标题、图标、tooltip、辅助功能标签和 enabled 状态统一由 `SessionPhase` 映射。
- 不合并或重写 `startSession()`、`pauseSession()`、`resumeSession()` 和 `stopSession()` 的业务实现。
- 自动待机恢复仍由输入活动触发，不把 `autoPaused` 当作手动“继续”。

验收：

- 空闲时只有一个可用的“开始”入口；手动暂停后同一位置变为“继续”。
- 开始、暂停、继续、结束、再次开始的状态和按钮映射始终正确，不会重复创建 Provider 或会话。
- 自动待机、连接中和识别中不会错误触发新的开始操作。

自动化测试重点：所有 `SessionPhase` 到主动作的映射，以及快速重复点击时现有 guard 不被绕过。

用户必测重点：完整生命周期、自动待机后恢复、结束后再次开始和 VoiceOver 标签。

预计：0.5～1 个开发日。

## 9. Feature 7：分离课程配置与 API 配置（1.1.7）

目标：将课堂语境与供应商连接信息拆成两个同级入口，缩短常用配置路径并明确职责。

界面划分：

| 入口 | 内容 |
|---|---|
| 课程配置 | 课程名称、本节主题、原文语言、译文语言、术语表 |
| API 配置 | 识别 Provider、自动待机、阿里云 Workspace ID、地域与 API Key、DeepSeek API Key |

实现方案：

- 主工具栏提供“课程配置”和“API 配置”两个同级图标按钮，与历史记录等入口保持同一层级，不使用二级菜单或侧拉栏。
- 将现有 `ConfigurationView` 拆成两个范围明确的 SwiftUI View；复用现有 `AppState` 字段和凭据保存流程。
- 两个 Sheet 使用一致的左上角返回/关闭位置、尺寸约束和表单样式。
- 移动字段不得重置正在编辑的值、术语表、Provider、地域或已保存凭据。
- 本 feature 不显示空白的用量面板；Feature 8 完成后再在 API 配置中加入真实统计内容。

非目标：不实施 Issue #36 的整体主窗口重设计，不增加侧边栏，不改变 API Key 存储格式或会话启动合同。

验收：

- 两个入口均可直接打开，字段归属清晰且无重复项。
- 修改课程信息仍会进入新会话和翻译上下文；修改 API 配置仍按既有逻辑用于连接。
- 关闭并重新打开 Sheet 后状态正确，历史、字幕和采集状态不受影响。

自动化测试重点：配置路由、字段绑定和拆分前后 `LectureContext`/Provider 配置值一致。

用户必测重点：分别修改课程、术语、地域和两个 API Key，重新开始会话并验证设置生效。

预计：1 个开发日。

## 10. Feature 8：API 用量与估算费用（1.1.8）

目标：在 API 配置界面本地统计实际发生的供应商用量，按时间范围分别展示语音识别和翻译消耗。

### 7.1 供应商数据合同与可行性

两类服务的计费单位不同，界面统一称为“API 用量”，不得把语音秒数伪装成文本 Token：

| 服务 | 权威用量 | 采集方式 |
|---|---|---|
| 阿里云 `qwen-audio-3.0-asr-flash-streaming` | 成功发送到云端的输入音频秒数，输出不计费 | 按成功发送的 PCM 字节数和 `16 kHz / mono / Int16` 格式计算 |
| DeepSeek `deepseek-v4-flash` | prompt、缓存命中、缓存未命中、completion 和 total Token | 解析每个成功响应的 `usage` 字段 |

官方参考：

- [阿里云模型调用计费](https://help.aliyun.com/zh/model-studio/model-pricing)：该 ASR 按音频秒数计费。
- [阿里云实时 ASR WebSocket API](https://help.aliyun.com/zh/model-studio/fun-asr-realtime-websocket-api)：任务事件本身不提供可直接使用的 Token 账单。
- [DeepSeek Chat Completion](https://api-docs.deepseek.com/api/create-chat-completion)：成功响应提供 `usage` 明细。
- [DeepSeek 模型与价格](https://api-docs.deepseek.com/quick_start/pricing)：价格按缓存命中/未命中、输出和峰谷时段区分。

### 7.2 记录与并发边界

2026-10-05 开始实现（Issue #80）：官方 DeepSeek 价格及周末/节假日规则已更新，采用下文新快照；请求仍使用现有旧模型名称。ASR 快照按 `(task ID, 发生时本地日期)` 分桶覆盖，任务数按 task ID 去重，保证跨午夜筛选正确。

- 新增独立的 `APIUsage.json`，不复用或修改 `Sessions.json`。
- 每条记录至少包含发生时间、供应商、模型、会话 ID（若存在）、计费指标和价格版本；不得包含 API Key、Workspace ID、请求文本、译文或音频内容。
- ASR Provider 在每次音频发送成功后只更新内存字节计数；每 30 秒和 Provider 正常结束/失败/停止时提交累计快照。快照按 task ID 覆盖更新，避免重复累计。
- DeepSeek 成功响应同时返回译文和 `usage`。翻译队列继续按原路径写回译文，并将纯数字用量异步提交到记录器；记录失败不得使译文失败。
- `APIUsageStore` 使用 actor 隔离并批量原子写入。磁盘 I/O 不在音频发送、STT 事件解析或主线程渲染路径上等待。
- 应用异常退出时最多损失最近 30 秒尚未提交的 ASR 快照；不为此增加高频磁盘写入或复杂恢复日志。
- 无效 `APIUsage.json` 原样保留并显示完整路径；不自动替换为空记录。

### 7.3 API 配置界面

提供四个简单时间筛选：今天、最近 7 天、最近 30 天、全部。筛选使用记录发生时的本地日期边界。

语音识别区域显示：

- 云端音频总时长。
- Provider 任务数。
- 按北京/新加坡和模型分别汇总。
- 人民币估算费用。

翻译区域显示：

- 请求数。
- 输入 Token、缓存命中/未命中 Token、输出 Token 和总 Token。
- 美元估算费用。

本轮使用简单汇总行和明细表，不增加图表、预算告警、导出或云端账单同步。

### 7.4 费用显示

费用显示可行，但只能标为“估算费用”：

- 阿里云按模型、地域和音频秒数计算。初始价格快照以 2026-10-05 官方页面为准：北京 `0.00033 CNY/秒`，新加坡 `0.00066 CNY/秒`。
- DeepSeek 按响应返回的缓存命中、缓存未命中和输出 Token 分别计算，并以请求完成时间的 UTC 峰谷区间选择单价。`deepseek-v4-flash` 初始价格快照如下：

| 计费项（每 1M Token） | 非高峰 | 高峰 |
|---|---:|---:|
| 缓存命中输入 | `0.003 USD` | `0.006 USD` |
| 缓存未命中输入 | `0.15 USD` | `0.30 USD` |
| 输出 | `0.60 USD` | `1.20 USD` |

2026-10-05 官方快照：旧名称 `deepseek-v4-flash` 仍被接受，实际按 DeepSeek-V4.1-Flash 价格计费。高峰仅为周一至周五的 `01:00–04:00 UTC` 和 `06:00–10:00 UTC`，排除中国节假日；周末全部非高峰。节假日按中国日期判断，内置 [国务院公布的 2026 年放假日期](https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202511/t20251104_4258838.html)。日历未覆盖年份或未知模型记录用量但标示费用无法估算，不猜测单价。

- 价格表必须带模型、币种、生效日期和来源链接；每条历史记录保留当时使用的价格版本，后续更新价格不得改写旧估算。
- 人民币与美元分别显示，不进行汇率换算，也不合并成一个总额。
- 免费额度、优惠、税费、供应商舍入、失败请求是否计费和控制台事后调整不纳入估算。界面明确提示最终费用以供应商账单为准。

非目标：不调用阿里云或 DeepSeek 的账单 API，不存储账户余额，不自动充值，不设置消费上限，不上传统计数据。

验收：

- ASR 的预滚、自动待机恢复和多 Provider task 均只按实际成功发送的音频累计一次。
- DeepSeek 每个成功请求的用量与响应 fixture 一致；翻译失败、无 `usage` 的错误响应和取消请求不会伪造 Token。
- 四个时间范围边界正确，语音与翻译分区汇总不会互相混算。
- 北京/新加坡 ASR 费用、DeepSeek 峰谷与缓存价格公式正确，币种和“估算”标识清晰。
- 用量记录写入失败只提示统计错误，不影响原文、译文或课堂记录；API Key 和字幕内容不进入用量文件。

自动化测试重点：PCM 字节到秒数、task 快照去重、DeepSeek `usage` 解码、时间筛选、时区边界、价格版本、峰谷价格、缓存价格、原子持久化和无效文件报错。

主代理手动测试使用本地 fixture 和模拟 Provider，不主动调用可能计费的真实 API。真实阿里云/DeepSeek 对账列入用户必测，执行前明确提示会产生供应商用量。

用户必测重点：一次真实短会话后对比应用与供应商控制台的音频秒数、Token 和费用数量级；分别验证北京/新加坡配置及跨日期筛选。

预计：2～3 个开发日。

## 11. 测试与发布门禁

每个 feature 至少执行：

```bash
git diff --check
swift test
xcodebuild -project LectureCaption.xcodeproj \
  -scheme LectureCaption \
  -configuration Debug \
  -sdk macosx \
  -arch arm64 \
  -derivedDataPath .build/xcode-debug \
  build
```

并完成：

- 独立子代理代码审查，修复所有阻断主要功能的问题。
- 主代理实际启动 Debug App，完成可操作的滚动、按钮、配置和模拟用量测试。
- 在 `docs/MANUAL_TEST_CHECKLIST.md` 中为当前 feature 增加前置条件、步骤、输入、预期输出和结果字段。
- 用户确认当前 feature 的全部必测项后，PR 才能 Ready / Squash Merge，并发布对应补丁版本。
- 不运行或等待任何 GitHub Actions、远端 CI 或付费托管测试。

## 12. 总工期与后续版本

预计总工期：8～12 个开发日，不含用户手工测试、真实 API 对账和外部服务故障时间。

完成 `1.1.8` 后，按照 [LectureCaption 1.2.0 开发计划](DEVELOPMENT_PLAN_1.2.md) 开发低延迟实时翻译。`1.2.0` 的所有 partial 翻译请求也必须接入 `1.1.8` 的用量记录合同，但不得反向改变原文链路。

MiMo ASR、系统音频采集和自动暂停算法修复继续作为独立后续工作，不得混入上述八个 feature。
