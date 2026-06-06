# 联网搜索重构方案

## 问题

当前联网搜索依赖 Brave Search API，需要用户自行注册并配置 API Key，门槛高、体验差。

## 目标

零配置、开箱即用的联网搜索，无论用户使用哪个模型。

## 架构

```
用户消息
  │
  ├─ webSearchEnabled=false → 普通对话，无搜索
  │
  └─ webSearchEnabled=true
       │
       ├─ 模型支持原生搜索?
       │   ├─ 是 → 向 API 请求体追加搜索参数
       │   │        模型自己搜索、阅读、整合回答
       │   │        零额外 token 消耗
       │   │
       │   └─ 否 → 客户端搜索兜底 (Jina Reader)
       │             s.jina.ai/{query} → 搜索结果 (URL+标题+摘要)
       │             r.jina.ai/{url}   → 页面全文→Markdown
       │             注入对话 → 模型回答
       │
       └─ 结果返回给用户
```

## 组件

### 1. 模型原生搜索 (主力)

**原理**：叩问对接的 DeepSeek、通义千问、Kimi 均支持在 chat/completions 请求体中追加搜索参数。模型端自动完成搜索→阅读→回答全流程。

**检测规则**（根据 `modelName` 自动判断）：

| 模型名称包含 | 搜索参数 |
|-------------|---------|
| `deepseek`  | `enable_search: true` |
| `qwen` 或 `tongyi` | `enable_search: true` |
| `kimi` 或 `moonshot` | `use_search: true` |
| 其他 | 不追加搜索参数（走 Jina 兜底） |

**改动点**：
- `api_service.dart`: `_chatStreamOnce()` 接收 `enableSearch` 参数，追加搜索字段

### 2. Jina Reader 客户端搜索 (兜底)

当模型不支持原生搜索时，用 Jina Reader 的免费 API 完成搜索+抓取：

| 能力 | URL | 返回 |
|------|-----|------|
| 搜索 | `GET https://s.jina.ai/{query}` | 搜索结果列表（标题、URL、摘要），无需 API Key |
| 抓取 | `GET https://r.jina.ai/{url}` | 页面完整内容转 Markdown，无需 API Key |

**改动点**：
- **NEW** `lib/services/web_search_service.dart` — 封装 Jina Reader 搜索 + 抓取
- `chat_provider.dart` — 添加 Jina 兜底分支

### 3. 智能触发（保留手动开关）

保留现有的 🌐 手动开关，但增加自动检测：

```
用户输入包含以下关键词 → 自动开启搜索
  "最新", "今天", "最近", "新闻", "行情"
  "价格", "天气", "股票", "比分"
  "2025年", "2026年", "今年"
  完整 URL (http:// 或 https://)
```

**改动点**：
- `chat_provider.dart` — `sendMessage()` 增加关键词检测

## 删除

- `lib/services/brave_search_service.dart` — 可删除，不再依赖 Brave
- `secure_storage_service.dart` 中的 `_braveSearchKey` — 可删除

## 数据流

```
用户输入 → sendMessage()
  │
  ├─ webSearchEnabled=true OR 关键词触发自动搜索
  │    │
  │    ├─ auto_detect_model(modelName) 检测原生搜索支持
  │    │   ├─ 支持 → api_service 追加 enable_search/use_search
  │    │   └─ 不支持 → Jina Reader 搜索+抓取 → 注入上下文
  │    │
  │    └─ stream 请求 → 模型回答
  │
  └─ webSearchEnabled=false AND 无关键词 → 普通对话
```

## 实施步骤

1. 创建 `WebSearchService`（Jina Reader 封装）
2. 修改 `api_service.dart` 支持原生搜索参数（模型自动检测）
3. 修改 `chat_provider.dart` 集成 Jina 兜底 + 关键词触发
4. 删除 Brave Search 相关代码
5. 更新 `ModelConfig` 表 (DB v5: 可选加 `provider` 字段)
6. 测试
