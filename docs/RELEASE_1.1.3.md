# LectureCaption 1.1.3

本次汇总 1.1.0 之后已验收的兼容性修复，未包含 1.1.4 后续追踪和 1.2 实时翻译功能。

- 校验阿里云 Workspace ID 与实际网络端点，阻止凭据和音频发往非预期主机。
- 加入本地敏感文件忽略与 Gitleaks 扫描。
- 清除 Release coverage/profile 插桩和开发机源码路径；打包强制检查 APP、ZIP、DMG。
- 修复 macOS 27 悬浮字幕文字/空白拖动，扩大四边与四角缩放区域。
- 统一浮窗生命周期，修复重复和无法关闭的浮窗。
- 新增默认关闭的本地识别延迟诊断，详见 `RECOGNITION_DIAGNOSTICS.md`。
- 仓库公开，恢复仅限标准免费 runner 的 CI；无自动部署或发布。

## 安装与限制

下载 `LectureCaption.dmg` 拖入 Applications，或解压 `LectureCaption.zip` 得到 `LectureCaption.app`。GitHub Release 不能上传 macOS App 目录本身，因此 App 包含在 ZIP 和 DMG 中；本地保留 APP、ZIP、DMG 三种产物，固定文件名不带版本号。

采用 ad-hoc 签名，未进行 Apple notarization。macOS 可能提示无法验证开发者。API Key 与课堂记录沿用 Release 本地目录，不包含在发布资产中；Debug 数据目录独立。

历史 v1.0.x/1.1.0 资产可能包含 profile 标记或开发机源码路径，本次不移动旧标签、不替换旧资产。自动待机误判（Issue #53）仍未修复；识别高延迟的根因尚待真实运行日志定位。诊断只能区分客户端阶段，不等同于精确测量服务端计算时间。
