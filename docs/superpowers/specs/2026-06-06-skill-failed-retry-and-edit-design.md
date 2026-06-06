# Skill 失败重试 + 编辑功能设计

## 需求概述

1. **失败技能重试**：批量安装中失败的技能可单独或批量重新安装
2. **技能编辑**：安装后可查看/编辑技能内容，支持表单编辑和原始 YAML 编辑双模式

---

## 1. 失败技能重试

### 现状

- `InstallState` 只存 `failedNames: List<String>` — 无法重试
- 安装完成后失败信息随 state auto-reset 丢失
- 想重试只能重新扫描整个仓库

### 改动

**`install_provider.dart` — InstallState 新增字段：**

```dart
class InstallState {
  final List<GitHubSkillResult> failedSkills;  // ← 新增
  final List<String> failedNames;              // ← 已有
}
```

**`install_provider.dart` — InstallerNotifier：**

```dart
// installAll 执行中，下载/解析/安装失败时保存完整 skill 对象：
if (yaml == null || parse failed || install failed) {
  failedSkills.add(skill);  // ← 保存 GitHubSkillResult（含 url）
  ...
}

// 新增方法：重试全部失败技能
Future<void> retryFailed() async {
  if (failedSkills.isEmpty) return;
  // 复用 installAll 内部逻辑，但只处理 failedSkills
  // 清空 failedSkills，重新尝试
  // 成功后 same progress 通知
}
```

**`github_skill_screen.dart`：**

安装完成结果区下方增加"重试失败"按钮（`failedSkills.isNotEmpty` 时显示）

**`my_skills_screen.dart`：**

进度 banner 完成后增加"重试 N 个失败"按钮

---

## 2. 技能编辑 (A+B)

### 现状

- `skill_detail_screen.dart` 只读展示
- `SkillRepository.updateSkill()` 只更新 `yaml_content` + `version`
- 用户无法修改已安装技能

### 改动清单

| 文件 | 改动 |
|------|------|
| **NEW** `skill_edit_screen.dart` | 新页面，双模式编辑 |
| `skill_detail_screen.dart` | 右上角加"编辑"按钮 |
| `repositories.dart` | `updateSkill()` 扩展为全字段更新 |
| `install_provider.dart` | 同需求 1 |

### SkillEditScreen 设计

#### 页面结构

```
AppBar: "编辑技能" + SegmentedButton [表单 | 原始YAML]

─── 表单模式 ───
┌────────────────────────────────┐
│ 技能名称  [__________________] │
│ 版本      [1.0.0           ]   │
│ 图标      [🤖               ]  │
│ 分类      [通用 ▾           ]  │
│ 描述      [__________________]  │
│ 欢迎语    [__________________]  │
│ 系统提示       (多行文本框)     │
│ ┌────────────────────────────┐ │
│ │ You are an expert...      │ │
│ │                           │ │
│ └────────────────────────────┘ │
│ 示例问题:                      │
│ [+ 添加]                       │
│ [× 问题1]  [× 问题2]           │
└────────────────────────────────┘
[  保存  ]

─── 原始YAML模式 ───
┌────────────────────────────────┐
│ ┌────────────────────────────┐ │
│ │ name: My Skill            │ │
│ │ version: 1.0.0            │ │
│ │ system_prompt: |          │ │
│ │   You are an expert...    │ │
│ └────────────────────────────┘ │
└────────────────────────────────┘
[ 验证并保存 ]
```

#### 数据流

```
表单模式:
  加载 → parse YAML → 填充表单字段
  编辑 → 本地状态变更 → 无实时 YAML 生成
  保存 → 从表单重建 YAML → parse 验证 → DB 更新

原始YAML模式:
  加载 → 显示原始 YAML 文本
  编辑 → 直接修改文本
  保存 → parse 验证 → 提取 name → DB 更新

切换模式:
  表单→YAML: 从表单数据重建 YAML（提交到文本框）
  YAML→表单: parse YAML → 重新填充表单
```

#### YAML 重建函数

为表单→YAML 方向实现 `_buildYamlFromForm()`：
- 使用 StringBuffer 逐行构建标准 YAML
- 处理多行 system_prompt（`|` 块标量）
- 保留所有字段（缺失字段用空值）

#### 验证规则

- YAML parse 必须成功（`SkillParser.parse()`）
- `name:` 必须非空
- 如果 `name:` 变了 → 检查 `skillExists()` → 冲突则警告但不阻止
- `category:` 必须非空

#### DB 更新

扩展 `SkillRepository.updateSkill()`：

```dart
Future<void> updateSkill(
  String id, {
  required String name,
  required String version,
  String? author,
  String? description,
  required String category,
  required String yamlContent,
}) async {
  final db = await _db.database;
  await db.update('installed_skills', {
    'name': name,
    'version': version,
    'author': author,
    'category': category,
    'description': description,
    'yaml_content': yamlContent,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  }, where: 'id = ?', whereArgs: [id]);
}
```

---

## 3. 复用逻辑

两个需求共享的数据流修改：

```
installAll()
  ├→ 下载内容 → parse YAML → 获取真实 name
  ├→ skillExists() 去重
  ├→ 成功 → 记录 success
  ├→ 失败 → 记录 failedSkills (含 url) ← 新
  └→ 完成 → 返回 InstallState.failedSkills ← 新

retryFailed()
  └→ 遍历 failedSkills → 重新下载/parse/安装
      └→ 清空 failedSkills，新失败重新记录
```

---

## 文件变更汇总

| 文件 | 状态 | 变更 |
|------|------|------|
| `lib/features/skills/skill_edit_screen.dart` | **NEW** | 双模式编辑页 |
| `lib/features/skills/skill_detail_screen.dart` | 修改 | 加"编辑"按钮 → 跳转编辑页 |
| `lib/features/skills/skill_market_screen.dart` | 修改 | 可能不需要 |
| `lib/features/skills/providers/install_provider.dart` | 修改 | 加 `failedSkills` 字段 + `retryFailed()` |
| `lib/data/repositories.dart` | 修改 | `updateSkill()` 扩展为全字段 |
| `lib/features/skills/github_skill_screen.dart` | 修改 | 完成区加"重试失败"按钮 |
| `lib/features/skills/my_skills_screen.dart` | 修改 | 进度 banner 加"重试"按钮 |
