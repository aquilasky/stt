# LectureCaption 版本控制与 Pull Request 规范

> 适用范围：LectureCaption macOS MVP 及后续版本
> 工作模式：短生命周期 feature 分支 + Pull Request
> 默认分支：`main`

## 1. 基本原则

- `main` 始终保持可构建、可测试和可回退。
- 所有功能和修复都从最新 `main` 创建短生命周期分支。
- 禁止直接向 `main` 推送业务代码，所有变更通过 Pull Request 合并。
- 一个 PR 只解决一个明确问题，避免混入无关重构和格式化。
- 分支存活时间建议不超过 3 个工作日；大功能拆成可独立合并的小步。
- 密钥、音频样本、个人配置、DerivedData 和签名材料不得提交。
- MVP 阶段采用 Squash Merge，使 `main` 上每个 PR 对应一个可读提交。
- 不使用 GitHub Actions、GitHub-hosted runner、Codespaces、付费 Marketplace App 或其他可能计费的托管构建、测试、部署、监控和分析服务。质量门禁只在本机执行并记录结果；计费状态不明确的能力必须先获得用户当次明确授权。

## 2. 分支模型

项目使用简化 GitHub Flow，不维护长期 `develop` 分支。

| 类型 | 分支格式 | 用途 | 示例 |
|---|---|---|---|
| 功能 | `feature/<issue>-<slug>` | 新增用户能力 | `feature/12-microphone-capture` |
| 修复 | `fix/<issue>-<slug>` | 修复非紧急缺陷 | `fix/31-duplicate-final` |
| 紧急修复 | `hotfix/<issue>-<slug>` | 修复已发布版本的阻断问题 | `hotfix/48-keychain-crash` |
| 重构 | `refactor/<issue>-<slug>` | 不改变外部行为 | `refactor/22-audio-buffer` |
| 文档 | `docs/<issue>-<slug>` | 只修改文档 | `docs/7-api-contract` |
| 工程 | `chore/<issue>-<slug>` | 构建、依赖和工具配置 | `chore/9-ci-workflow` |

`<slug>` 使用小写英文和连字符。已有 GitHub Issue 时必须带 Issue 编号；没有 Issue 的微小维护可省略编号，例如 `docs/update-readme`。

## 3. Feature 开发流程

### 3.1 创建分支

```bash
git switch main
git pull --ff-only origin main
git switch -c feature/12-microphone-capture
```

编码前先明确该 feature 的验收条件、非目标和测试方式。预计超过 400 行有效改动或跨越多个独立模块时，优先拆分为多个可依次合并的 PR。

### 3.2 开发与同步

提交应小而完整，保证每个提交可以解释且不会包含密钥：

```bash
git status
git diff --check
git add <明确的文件路径>
git commit -m "feat(audio): capture microphone PCM buffers"
```

分支落后时使用 rebase 保持线性历史：

```bash
git fetch origin
git rebase origin/main
```

仅允许对个人 feature 分支使用 `git push --force-with-lease` 更新已发布的 rebase 历史，禁止使用普通 `--force`，禁止改写 `main`。

### 3.3 推送并创建 PR

```bash
git push -u origin feature/12-microphone-capture
gh pr create --fill --base main
```

首次推送后尽早创建 Draft PR，以便持续检查变更范围；达到本地验收条件后再标记 Ready for review。不得触发、重跑或等待远端 CI。

### 3.4 Feature 完成质量门禁

一个 feature 只有在以下门禁全部通过后，才能标记为完成、合并 PR 或开始下一个 feature。未通过任何一项时，应继续在当前分支修复并重复完整验证；不得以口头判断、部分通过或已创建 PR 代替验收。

1. **子代理代码审查**：功能实现完成后，由独立子代理进行代码审查。审查以缺陷、回归风险、并发与资源生命周期、隐私与密钥泄露、错误处理及测试缺口为重点。所有阻断问题必须修复；非阻断建议应在 PR 中明确采纳或说明不采纳的理由。
2. **自动化测试**：运行与变更范围匹配的单元测试、集成测试、构建检查和静态检查。至少执行 `git diff --check`、`swift test` 和 arm64 macOS Debug 构建；涉及网络、持久化、导出或 UI 时，增加相应测试。测试结果必须记录在 PR 描述中。
3. **主代理手动测试**：由负责开发的主代理依据该 feature 的验收标准，在实际应用中完成手动验证并记录场景和结果。涉及权限、麦克风、悬浮窗、网络恢复或长时间运行的功能，不能仅以单元测试替代真实运行验证。

执行顺序固定为：**实现完成 -> 子代理审查 -> 修复审查问题 -> 自动化测试 -> 主代理手动测试 -> 记录结果 -> 完成 feature**。自动化测试或手动测试发现问题后，回到实现阶段；修复影响核心逻辑时，必须再次进行子代理审查。

## 4. Commit 规范

采用 Conventional Commits：

```text
<type>(<scope>): <imperative summary>
```

允许的 `type`：

- `feat`：新增功能。
- `fix`：修复缺陷。
- `refactor`：重构且不改变行为。
- `test`：新增或调整测试。
- `docs`：只改文档。
- `chore`：工程与维护工作。
- `build`：构建系统或依赖。
- `ci`：持续集成配置。
- `perf`：性能改进。

建议 scope：`audio`、`stt`、`translation`、`caption`、`session`、`security`、`export`、`app`。

示例：

```text
feat(stt): implement Aliyun run-task handshake
fix(caption): ignore duplicate final sentence events
test(audio): cover stereo to mono conversion
docs(workflow): define pull request checks
```

主题行使用英文祈使句，不加句号，建议不超过 72 个字符。破坏性变更必须在正文中写 `BREAKING CHANGE:`；MVP 阶段原则上避免破坏性变更。

## 5. Pull Request 规范

PR 标题使用与提交相同的 Conventional Commit 格式。描述必须回答：

- 为什么需要这项变更。
- 实际做了什么。
- 明确没有做什么。
- 如何验证，包含具体命令或手工场景。
- 是否涉及权限、密钥、网络协议、数据迁移或性能风险。
- 关联 Issue，使用 `Closes #<issue>` 自动关闭。

### 5.1 PR 大小

| 规模 | 有效改动行数 | 要求 |
|---|---:|---|
| S | 0～200 | 正常评审 |
| M | 201～400 | 正常评审，说明主要设计决定 |
| L | 401～800 | 解释无法拆分的原因 |
| XL | 800+ | 默认拒绝，先拆分或先提交设计 PR |

生成文件、锁文件和测试夹具不计入有效改动，但必须在 PR 中说明。

### 5.2 合并门槛

PR 合并前必须满足：

- 分支基于最新 `main`，无冲突。
- Debug 构建成功。
- 相关单元测试和集成测试通过。
- `git diff --check` 无错误。
- 新行为有测试，或在 PR 中说明无法自动化的原因与手工验证结果。
- 不包含 API Key、Workspace 私密配置、签名文件或原始课堂音频。
- 用户可见行为、协议或架构变化已同步开发文档。
- PR 中的阻断评论已解决。
- 已完成第 3.4 节的子代理审查、自动化测试和主代理手动测试，并在 PR 中记录结论。

个人项目允许作者自审合并，但必须完整填写 PR 模板，并记录本地构建、测试和手工验证结果。邀请协作者后，将 `main` 保护规则升级为至少 1 个批准评审。

### 5.3 合并方式

- 默认使用 Squash Merge。
- Squash 提交标题使用 PR 标题。
- 合并后删除远程和本地 feature 分支。
- 禁止 Merge Commit，除非未来维护发布分支时另行修订规范。

```bash
gh pr merge --squash --delete-branch
git switch main
git pull --ff-only origin main
```

## 6. Issue 与 Feature 关系

超过约 2 小时的工作、用户可见功能、协议变更和缺陷修复，应先创建 GitHub Issue。Issue 至少包含目标、验收标准、非目标和风险。

一个 feature 分支通常对应一个 Issue 和一个 PR。需要多 PR 交付时，在 Issue 中维护拆分清单，每个 PR 都必须可独立构建，并通过 `Part of #<issue>` 关联，最后一个 PR 使用 `Closes #<issue>`。

## 7. 发布与版本号

采用语义化版本 `MAJOR.MINOR.PATCH`：

- MVP 开发期使用 `0.x.y`。
- `MINOR`：新增一组可用能力，例如 `0.2.0` 加入实时原文。
- `PATCH`：兼容性修复，例如 `0.2.1` 修复字幕重复。
- `1.0.0`：达到全部 MVP 验收标准并可稳定日常使用。

建议里程碑：

| 版本 | 内容 |
|---|---|
| `0.1.0` | 麦克风与本地自动待机原型 |
| `0.2.0` | 阿里云实时与字幕稳定器 |
| `0.3.0` | DeepSeek V4 Flash 翻译与术语上下文 |
| `0.4.0` | 主界面完善与本地课堂记录 |
| `0.5.0` | 悬浮字幕窗口 |
| `0.6.0` | Markdown / JSON 导出 |
| `1.0.0` | 2 小时稳定性与完整 MVP 验收通过 |
| `1.1.0` | 时间戳与 TXT/JSON 导出、全屏和防息屏 |
| `1.2.0` | 悬浮字幕最新原文下边界追踪与低延迟实时翻译 |

MiMo 分块 ASR 不属于当前 MVP；在 `1.0.0` 之后重新评估接口稳定性、成本和分块体验，并作为独立版本功能交付。

`1.1.0` 的 feature 拆分、顺序、验收条件和测试计划详见 [LectureCaption 1.1.0 开发计划](DEVELOPMENT_PLAN_1.1.md)。`1.2.0` 只能在 1.1.0 全部 feature 完成后开始，详见 [LectureCaption 1.2.0 开发计划](DEVELOPMENT_PLAN_1.2.md)。

> 发布例外：`1.0.0` 作为个人使用版本发布时，发布者接受 2 小时稳定性和睡眠/唤醒恢复尚未完成完整手工验收的风险。当前已完成 60 分钟连续运行测试。未完成项必须在发布说明中明确列为已知限制，并在后续补丁版本前补充验证或修复。

发布步骤：

1. 从 `main` 创建 `chore/<issue>-release-x.y.z`。
2. 更新版本号、开发文档和变更记录。
3. 通过 PR 合并到 `main`。
4. 在合并提交上创建带注释标签 `vX.Y.Z`。
5. 使用 GitHub Release 发布变更说明、已知问题和已验证的安装资产。
6. 使用 `Scripts/create-release.sh` 打包。最终用户资产固定命名为 `LectureCaption.app`、`LectureCaption.zip` 和 `LectureCaption.dmg`，不在文件名中附加版本号或架构；版本以应用内 `CFBundleShortVersionString` 和 GitHub Release 标签 `vX.Y.Z` 为准。ZIP 用于直接解压，DMG 必须包含应用及指向 `/Applications` 的快捷方式，供拖拽安装。发布说明应分别列出两种资产的 SHA-256 校验和。

禁止移动或覆盖已经推送的版本标签。

## 8. GitHub 仓库保护建议

远程仓库创建后，为 `main` 配置：

- Require a pull request before merging。
- Require conversation resolution before merging。
- Block force pushes。
- Block branch deletion。
- Automatically delete head branches。
- 个人阶段不强制审批人数；有协作者后要求至少 1 个 approval。

不得配置或要求远端 CI status check；当前仓库不使用 GitHub Actions 或其他托管 CI/CD。

## 9. 紧急修复

个人 MVP 仍应通过 PR 处理紧急问题：

```bash
git switch main
git pull --ff-only origin main
git switch -c hotfix/48-keychain-crash
```

只包含最小修复和回归测试，不夹带重构。PR 标记为高优先级，本地质量门禁通过后 Squash Merge；随后按 PATCH 版本发布。

## 10. 禁止事项

- 直接推送或强制推送 `main`。
- 提交 `.env`、API Key、个人 Workspace 配置或证书私钥。
- 使用笼统提交信息，例如 `update`、`fix bug`、`wip`。
- 一个 PR 同时包含功能、无关重构和全项目格式化。
- 为通过检查而删除或跳过有效测试。
- 未完成 `finish-task`/`task-finished` 协议测试就合并 STT 生命周期改动。
- 未验证数据迁移就合并 SwiftData 模型变更。
