# 本地敏感文件检查

固定使用开源 Gitleaks **8.24.2**，不使用 Actions、托管扫描或网络账单接口。下载官方 [v8.24.2 Release](https://github.com/gitleaks/gitleaks/releases/tag/v8.24.2) 的 `darwin_arm64.tar.gz` 和 checksums 文件，核对 SHA-256 后解压到本机目录。脚本不会自动安装工具或修改 Git hooks。

例如将已验证的二进制放到 `.build/security-tools/gitleaks` 后：

```bash
export GITLEAKS_BIN="$PWD/.build/security-tools/gitleaks"
bash Scripts/check-secrets.sh staged
bash Scripts/check-secrets.sh worktree
bash Scripts/check-secrets.sh history
```

- `staged`：提交前检查暂存 diff 的新增内容。
- `worktree`：检查全部已跟踪现存文件，以及没有被 Git 忽略的未跟踪文件。已跟踪文件即使后来被忽略仍会扫描；未跟踪的个人凭据、音频和 Release 目录不属于待提交源码，不会复制到扫描目录。
- `history`：检查本机所有 refs 可达的完整提交历史，包含后来删除的内容。浅克隆会明确失败；本机未获取的远端 refs 不在覆盖范围。

安全相关 PR 和每次发布必须记录三种模式、工具版本、提交 ID 和退出结果。`staged` 为空不代表工作区或历史安全。忽略规则不影响已经跟踪的文件，也不能阻止 `git add -f`，必须配合扫描使用。

退出码：0 通过，1 发现疑似密钥（或扫描器失败，应结合输出判断），64 参数错误，65 不支持的扫描范围，69 缺少工具或版本不符。任何非零结果都不能视为通过。扫描输出凭据脱敏，保留文件、规则、行号和历史提交信息；不要将含真实凭据的原始文件或未脱敏报告贴到 PR。

没有配置项目级 allowlist，也不接受行内 `gitleaks:allow` 或 `.gitleaksignore` 来隐藏结果。如将来确有合成 fixture 误报，只允许同时限制确切路径和合成内容的例外。发现真实凭据时保留文件与历史，停止提交/发布并报告；凭据轮换和历史清理需单独处理。

自动化验证：`bash Scripts/test-secret-checks.sh`。测试只在临时仓库创建合成密钥，不接触真实配置或修改当前 Git index。
