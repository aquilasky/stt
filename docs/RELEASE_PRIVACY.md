# Release 隐私检查（1.1.3）

本 feature 只改变构建与发布验证，不改变识别、翻译、课堂记录合同或 Debug/Release 隔离。历史标签与已发布资产保持不变。

## 构建合同

- 项目与 App target 的 Release 显式关闭 `ENABLE_CODE_COVERAGE`、`CLANG_ENABLE_CODE_COVERAGE`、`CLANG_COVERAGE_MAPPING`、`GCC_GENERATE_TEST_COVERAGE_FILES`、`GCC_INSTRUMENT_PROGRAM_FLOW_ARCS`；打包命令再次指定这些值。当前 Xcode 的 Swift specification 通过前者及 coverage mapping 生成 `-profile-generate` 参数，不添加不存在的 Swift 开关。
- Release 的 `-file-prefix-map`、`-debug-prefix-map` 将仓库根映射为 `.`，Debug 诊断路径不变。
- DerivedData 位于每次 `mktemp` 创建的 staging 中，退出时仅清理本次临时目录，不读取旧 `.build/release-package`。
- 保留原有签名方式和验证；打包不会调用云端、CI、notarization 或修改旧 Release。

## 本地检查

```bash
bash Scripts/test-release-privacy.sh
bash Scripts/check-release-privacy.sh .build/release-privacy-validation/LectureCaption.app
bash Scripts/check-release-privacy.sh .build/release-privacy-validation/LectureCaption.zip
bash Scripts/check-release-privacy.sh .build/release-privacy-validation/LectureCaption.dmg
```

检查器要求标准 App 可执行文件名称和 arm64 架构，拒绝 `__llvm_profile` / `__llvm_prf`、任何 `.profraw`、`/Users/`、当前仓库绝对路径及绝对 `Sources/LectureCaption` 路径。按原始字节检查，不打印匹配的二进制内容。ZIP 解到独立临时目录，DMG 只读挂载并检查 Applications 安装快捷方式；检查成功或失败均卸载并清理本次临时目录。卸载失败会报错并保留目录供处理，不伪装成功。

退出码：0 表示通过；1 表示资产合同或隐私检查失败；64 表示参数错误。外部工具的其他非零退出码直接传播，缺少工具或损坏资产不能视为通过。检查是发布隐私检查，不是恶意压缩包安全沙箱，只用于本地生成的发布资产。

打包先检查未签名 App，生成资产后分别复检；只有全部成功才打印 `Packaged`。检查失败的输出不得发布，错误证据保留在构建日志中；原有用户 Release 文件不应在测试时覆盖，使用独立 `RELEASE_OUTPUT_DIRECTORY`。

## 发布说明须包含

修复 Release 意外携带覆盖率插桩和开发机源码路径的问题。记录三种资产检查、签名验证、本地密钥扫描与手工测试结果。历史 v1.0.x/1.1.0 产物可能含上述标记和路径；本次不移动旧标签或替换旧资产，也不声称历史产物已修复。
