# 叩问 (KouWen)

AI Skills Platform for Mobile — 基于 Flutter 的 AI 对话应用，通过加载"技能"（SKILL.md 文件）来定制 AI 对话的专业领域。

## 功能

- **技能系统**：从内置资产、GitHub/Gitee 仓库、技能市场安装技能
- **流式对话**：支持任何 OpenAI 兼容 API 的流式响应
- **技能自动匹配**：根据用户输入自动推荐/加载相关技能
- **联网搜索**：自动检测时间敏感问题，支持 Jina Reader 及模型原生搜索
- **文件附件**：支持拍照、文件上传（文本提取 + 上下文注入）

## 技术栈

- Flutter + Dart
- Riverpod (状态管理)
- sqflite (本地 SQLite 存储)
- Dio (HTTP 客户端)
- flutter_markdown (Markdown 渲染)

## 构建

```bash
flutter build apk --debug   # Debug 构建
flutter build apk --release # Release 构建（已签名）
flutter test                # 运行测试
flutter analyze             # 静态分析
```
