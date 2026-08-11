# Contributing

LectureCaption 使用短生命周期 feature 分支和 Pull Request 开发。开始工作前请阅读：

- [版本控制与 Pull Request 规范](docs/VERSION_CONTROL.md)
- [MVP 开发文档](docs/MVP_DEVELOPMENT.md)

基本流程：

```bash
git switch main
git pull --ff-only origin main
git switch -c feature/<issue>-<slug>

# 开发并验证
git push -u origin feature/<issue>-<slug>
gh pr create --fill --base main
```

禁止直接向 `main` 推送业务变更。API Key、Workspace 私密配置、原始课堂音频和签名材料不得进入版本库。
