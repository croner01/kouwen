# Skill 市场对接后端 API — 隐私优先架构

Date: 2026-06-07

## 核心原则

**API Key 绝不在服务端落地，对话内容不存服务端。** App 是决策和交互中心，后端是计算和文件存储的扩展。

## 职责划分

| 能力 | 位置 | 原因 |
|------|------|------|
| API Key 存储与管理 | 客户端 SecureStorage | 隐私核心——绝不出设备持久化 |
| 模型配置 | 客户端 SQLite | 用户偏好，不涉及服务端 |
| 对话历史 | 客户端 SQLite | 隐私——对话是用户最敏感数据 |
| Skill 市场发现 | 客户端直连 GitHub/Gitee | 灵活、无需服务端令牌 |
| Skill 自动匹配 | 客户端 SkillRouter | 本地决策，低延迟 |
| Markdown/LaTeX 渲染 | 客户端 | UI 能力 |
| 文件附件 | 客户端 | 本地文件访问 |
| Skill 文件存储 | 后端 PVC | 脚本+依赖需要持久文件系统 |
| pip venv 管理 | 后端 Sandbox | 需要 Python 运行时 |
| 脚本执行 | 后端 Sandbox | 隔离执行，防注入 |
| Agent 工具循环 | 后端 Agent | LLM tool-use 循环 |
| 用户认证 | 后端 PostgreSQL + JWT | 多租户隔离 |
| Skill 元数据 | 后端 PostgreSQL | 多设备同步（可选），主数据源 |

## API 设计

### Skill 相关端点（后端已有）

```
GET  /api/v1/skills              → 列出已安装技能 (JWT)
POST /api/v1/skills/install      → 安装技能 (JWT + source_repo)
DELETE /api/v1/skills/{id}       → 卸载技能 (JWT)
```

### 数据流

**市场浏览：**
- App → GitHubSkillSource.fetchFromSource() (客户端直连 Gitee API)
- App → SkillApiService.listSkills() (标记已安装状态)
- 合并显示：在线技能 + isInstalled 标记

**安装技能：**
- 用户点"安装" → SkillApiService.installSkill(sourceRepo)
- 后端：扫描 repo → 下载目录树 → PVC 存储 → pip install → PostgreSQL 记录
- 返回 {status, skills: [{id, name, python_deps, files}]}
- 客户端：更新本地缓存

**卸载技能：**
- 用户点"卸载" → SkillApiService.deleteSkill(skillId)
- 后端：DELETE FROM skills WHERE id=$1
- 客户端：刷新列表

## 新增文件

### `lib/services/skill_api_service.dart`
Skill 后端 API 客户端：
- 构造函数接收 `baseUrl` 和 `AuthService`（获取 JWT）
- `listSkills()` → GET /api/v1/skills
- `installSkill(sourceRepo)` → POST /api/v1/skills/install
- `deleteSkill(skillId)` → DELETE /api/v1/skills/{id}
- 返回类型使用扩展后的 MarketSkill / BackendSkill

## 修改文件

### `lib/data/skill_market_service.dart`
- `MarketSkill` 新增 `id` (后端 skill ID)、`sourceRepo`、`pythonDeps` 字段
- `MarketSkill.fromBackendJson()` 工厂方法
- `installSkill()` → 调用 SkillApiService.installSkill()
- `uninstallSkill()` → 调用 SkillApiService.deleteSkill()
- `loadCatalog()` → 废弃（不再读本地 assets catalog）
- 移除本地 SQLite 写入（SkillRepository.installSkill 调用）

### `lib/features/skills/skill_market_screen.dart`
- `marketSkillsProvider` → 
  1. 从后端 API 取已安装列表
  2. 从 Gitee 源扫描可用技能
  3. 合并时用后端数据标记 isInstalled
- 安装/卸载回调改为调用 SkillApiService

### `lib/features/skills/providers/skill_provider.dart`
- `installedSkillsProvider` → 从后端 API 获取
- `topLevelSkillsProvider` → 从后端 API 获取（暂用客户端过滤，后续后端加参数）
- `SkillInstallNotifier.uninstallSkill()` → 调用 SkillApiService

### `lib/features/skills/providers/install_provider.dart`
- `InstallerNotifier.installAll()` → 简化为调用 SkillApiService.installSkill()
- 不再逐文件下载和本地 SQLite 写入
- 保留进度展示（后端返回安装进度）

### `lib/features/skills/github_skill_screen.dart`
- 安装按钮 → 调用 SkillApiService.installSkill(repoUrl)
- 不再走本地 downloadSkillContent + SkillRepository.installSkill

### `lib/providers.dart`
- 新增 `skillApiServiceProvider`

### `lib/features/skills/skill_detail_screen.dart`
- 技能详情从后端 API 获取最新元数据

## 不变的部分

- `github_skill_loader.dart` — 市场浏览仍用它扫描 repo
- `github_skill_source.dart` — 内置源配置不变
- `skill_source_store.dart` — 自定义源不变
- `engine/skill_parser.dart` — 客户端解析不变
- 本地 SQLite `installed_skills` 表 — 保留作为缓存，但非主数据源

## API Key 安全

```
用户设置 API Key → FlutterSecureStorage (AES 加密)
Chat 时 → 从 SecureStorage 读取 → HTTPS 瞬时传递 → 后端 Agent 使用
           → 请求结束即丢弃，不落盘，不记录日志
           → 对话结果存客户端 SQLite
```

后端 Agent 代码中不持久化 api_key 参数，仅在请求生命周期内存存在变量中。
