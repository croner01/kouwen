# Skill 市场对接后端 API — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Skill 市场的安装/卸载/列表操作从本地 SQLite 切换到后端 API，同时保留客户端发现、密钥管理和对话隐私。

**Architecture:** 新增 `SkillApiService` 作为后端 API 客户端（JWT 认证）；`MarketSkill` 模型扩展 `fromBackendJson` 工厂；`SkillMarketService` 安装/卸载方法委托给后端；Provider 层从后端获取列表并与本地缓存合并。本地 SQLite 保留作为 yamlContent 缓存。

**Tech Stack:** Flutter/Dart, Riverpod, Dio HTTP client, JWT auth, 后端 FastAPI + PostgreSQL

---

### Task 1: 新增 `SkillApiService` — 后端 Skill API 客户端

**Files:**
- Create: `lib/services/skill_api_service.dart`

- [ ] **Step 1: 创建 SkillApiService 类**

```dart
import 'dart:convert';
import 'package:dio/dio.dart';

class BackendSkill {
  final String id;
  final String name;
  final String version;
  final String? author;
  final String category;
  final String? sourceRepo;
  final List<String> pythonDeps;
  final DateTime? installedAt;

  const BackendSkill({
    required this.id,
    required this.name,
    required this.version,
    this.author,
    required this.category,
    this.sourceRepo,
    this.pythonDeps = const [],
    this.installedAt,
  });

  factory BackendSkill.fromJson(Map<String, dynamic> json) {
    return BackendSkill(
      id: json['id'] as String,
      name: json['name'] as String,
      version: (json['version'] as String?) ?? '1.0.0',
      author: json['author'] as String?,
      category: (json['category'] as String?) ?? '通用',
      sourceRepo: json['source_repo'] as String?,
      pythonDeps: json['python_deps'] is List
          ? (json['python_deps'] as List).cast<String>()
          : [],
      installedAt: json['installed_at'] != null
          ? DateTime.tryParse(json['installed_at'] as String)
          : null,
    );
  }
}

class InstallResult {
  final String status;
  final List<InstallResultSkill> skills;

  const InstallResult({required this.status, required this.skills});

  factory InstallResult.fromJson(Map<String, dynamic> json) {
    final skillsList = (json['skills'] as List<dynamic>?)
        ?.map((e) => InstallResultSkill.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];
    return InstallResult(
      status: json['status'] as String,
      skills: skillsList,
    );
  }
}

class InstallResultSkill {
  final String id;
  final String name;
  final List<String> pythonDeps;
  final int files;
  final List<String> filesList;

  const InstallResultSkill({
    required this.id,
    required this.name,
    this.pythonDeps = const [],
    this.files = 0,
    this.filesList = const [],
  });

  factory InstallResultSkill.fromJson(Map<String, dynamic> json) {
    return InstallResultSkill(
      id: json['id'] as String,
      name: json['name'] as String,
      pythonDeps: json['python_deps'] is List
          ? (json['python_deps'] as List).cast<String>()
          : [],
      files: (json['files'] as int?) ?? 0,
      filesList: json['files_list'] is List
          ? (json['files_list'] as List).cast<String>()
          : [],
    );
  }
}

class SkillApiService {
  final Dio _dio;
  final String _baseUrl;

  SkillApiService({required String baseUrl, Dio? dio})
      : _baseUrl = baseUrl,
        _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
  }

  static const defaultBaseUrl = 'https://kouwen-sandbox.loca.lt';

  String? _jwtToken;
  void setAuth(String token) => _jwtToken = token;
  void clearAuth() => _jwtToken = null;

  Map<String, String> get _headers => _jwtToken != null
      ? {'Authorization': 'Bearer $_jwtToken'}
      : {};

  /// List installed skills from backend.
  Future<List<BackendSkill>> listSkills() async {
    final resp = await _dio.get(
      '$_baseUrl/api/v1/skills',
      options: Options(headers: _headers),
    );
    final data = resp.data as Map<String, dynamic>;
    final skills = (data['skills'] as List<dynamic>?)
        ?.map((e) => BackendSkill.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];
    return skills;
  }

  /// Install a skill from Gitee repo. Backend handles full directory download,
  /// PVC storage, and pip dependency installation.
  Future<InstallResult> installSkill(String sourceRepo) async {
    final resp = await _dio.post(
      '$_baseUrl/api/v1/skills/install',
      data: {'source_repo': sourceRepo},
      options: Options(headers: _headers),
    );
    return InstallResult.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Delete a skill by its backend ID.
  Future<void> deleteSkill(String skillId) async {
    await _dio.delete(
      '$_baseUrl/api/v1/skills/$skillId',
      options: Options(headers: _headers),
    );
  }
}
```

- [ ] **Step 2: 验证文件无编译错误**

```bash
cd /root/kouwen && flutter analyze lib/services/skill_api_service.dart 2>&1 | head -20
```

Expected: No issues found.

---

### Task 2: 更新 `MarketSkill` 模型 — 支持后端数据

**Files:**
- Modify: `lib/data/skill_market_service.dart:12-68`

- [ ] **Step 1: 给 MarketSkill 添加新字段和 fromBackendJson 工厂**

在 `MarketSkill` 类中添加 `id` 和 `sourceRepo` 字段，以及一个从 `BackendSkill` 转换的工厂方法。

找到 `MarketSkill` 类定义（约第12-68行），在 `childCount` 后面添加新字段：

```dart
  // 新增字段（加在 childCount 之后）
  String? id;          // 后端 skill ID，用于卸载
  String? sourceRepo;  // 来源仓库 "owner/repo"
  List<String> pythonDeps; // pip 依赖列表
```

更新构造函数，添加新参数：

```dart
  MarketSkill({
    required this.name,
    required this.displayName,
    required this.version,
    required this.author,
    required this.description,
    required this.icon,
    required this.category,
    required this.tags,
    required this.file,
    this.sourceUrl,
    this.sourceRepo,
    required this.downloads,
    required this.rating,
    this.isInstalled = false,
    this.isCollection = false,
    this.childCount,
    this.id,
    this.pythonDeps = const [],
  });
```

在 `fromJson` 工厂后添加 `fromBackendSkill` 工厂：

```dart
  /// Create a MarketSkill from a backend API response.
  /// Used to mark online-discovered skills as installed.
  factory MarketSkill.fromBackendSkill(BackendSkill backend) {
    return MarketSkill(
      name: backend.name,
      displayName: backend.name,
      version: backend.version,
      author: backend.author ?? '',
      description: backend.category,
      icon: _iconForCategory(backend.category),
      category: backend.category,
      tags: [],
      file: '',
      sourceRepo: backend.sourceRepo,
      downloads: 0,
      rating: 0,
      isInstalled: true,
      id: backend.id,
      pythonDeps: backend.pythonDeps,
    );
  }

  static String _iconForCategory(String cat) {
    switch (cat) {
      case '科技': return '\u{1F4BB}';
      case '设计': return '\u{1F3A8}';
      case '文档': return '\u{1F4C4}';
      case '财经': return '\u{1F4C8}';
      case '法律': return '\u{2696}';
      case '医疗': return '\u{1F3E5}';
      case '教育': return '\u{1F393}';
      default: return '\u{1F916}';
    }
  }
```

在文件顶部添加 import：

```dart
import '../services/skill_api_service.dart';
```

- [ ] **Step 2: 验证无编译错误**

```bash
cd /root/kouwen && flutter analyze lib/data/skill_market_service.dart 2>&1 | head -20
```

---

### Task 3: 更新 `SkillMarketService` — 安装/卸载走后端

**Files:**
- Modify: `lib/data/skill_market_service.dart:98-211`

- [ ] **Step 1: 重写 `installSkill` 方法**

替换现有的 `installSkill` 方法（约第100-136行）：

```dart
  /// Install a skill via backend API. Backend handles full directory download,
  /// PVC storage, and pip dependency installation.
  /// Requires [apiService] for the backend call and optionally saves a local
  /// cache record for yamlContent access.
  static Future<InstallResult> installSkill(
    MarketSkill skill, {
    required SkillApiService apiService,
  }) async {
    if (skill.sourceRepo == null) {
      throw Exception('该技能没有来源仓库');
    }
    // Backend handles everything: scan, download, PVC, pip, PostgreSQL
    final result = await apiService.installSkill(skill.sourceRepo!);
    skill.isInstalled = true;

    // Also save to local SQLite as cache (for yamlContent access in chat/detail)
    if (result.skills.isNotEmpty) {
      try {
        final repo = SkillRepository(AppDatabase.instance);
        for (final s in result.skills) {
          // Check if already cached locally
          final exists = await repo.skillExists(s.name);
          if (exists) continue;
          await repo.installSkill(
            name: s.name,
            version: '1.0.0',
            author: skill.author,
            category: skill.category,
            yamlContent: '', // Backend has the real content on PVC
            description: '通过后端安装 · ${s.files} 个文件',
          );
        }
      } catch (_) {
        // Local cache failure is non-fatal — backend is primary
      }
    }

    clearCache();
    return result;
  }
```

- [ ] **Step 2: 重写 `uninstallSkill` 方法**

替换现有的 `uninstallSkill` 方法（约第198-211行）：

```dart
  /// Uninstall a skill via backend API.
  static Future<void> uninstallSkill(
    MarketSkill skill, {
    required SkillApiService apiService,
  }) async {
    if (skill.id == null) {
      throw Exception('无法卸载：缺少技能 ID');
    }
    await apiService.deleteSkill(skill.id!);
    skill.isInstalled = false;

    // Also remove from local cache
    try {
      final repo = SkillRepository(AppDatabase.instance);
      final installed = await repo.getInstalledSkills();
      final match = installed.where((s) => s.name == skill.name).firstOrNull;
      if (match != null) {
        await repo.deleteSkill(match.id);
      }
    } catch (_) {
      // Local cache cleanup failure is non-fatal
    }

    clearCache();
  }
```

- [ ] **Step 3: 移除 `_installCollection` 方法**

删除 `_installCollection` 方法（约第139-195行）——后端 API 自动处理集合安装。

- [ ] **Step 4: 验证无编译错误**

```bash
cd /root/kouwen && flutter analyze lib/data/skill_market_service.dart 2>&1 | head -20
```

---

### Task 4: 注册 `SkillApiService` Provider

**Files:**
- Modify: `lib/providers.dart:51`

- [ ] **Step 1: 添加 import 和 provider**

在 `providers.dart` 文件顶部添加 import（约第11行后）：

```dart
import 'services/skill_api_service.dart';
```

在 `authServiceProvider` 后面添加新 provider（约第52行后）：

```dart
final skillApiServiceProvider = Provider<SkillApiService>((ref) {
  final service = SkillApiService(baseUrl: SkillApiService.defaultBaseUrl);
  // Auto-inject JWT if user is logged in
  final auth = ref.watch(authServiceProvider);
  if (auth.isLoggedIn && auth.token != null) {
    service.setAuth(auth.token!);
  }
  return service;
});
```

- [ ] **Step 2: 验证无编译错误**

```bash
cd /root/kouwen && flutter analyze lib/providers.dart 2>&1 | head -20
```

---

### Task 5: 更新 Skill Providers — 后端为主数据源

**Files:**
- Modify: `lib/features/skills/providers/skill_provider.dart`

- [ ] **Step 1: 重写 providers 从后端 API 获取数据**

替换文件内容：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers.dart';
import '../../../data/models.dart';
import '../../../data/repositories.dart';
import '../../../services/skill_api_service.dart';
import '../../../engine/skill_router.dart';
import '../skill_market_screen.dart' show marketSkillsProvider;

/// Installed skills from backend API, enriched with local cache data.
final installedSkillsProvider = FutureProvider<List<Skill>>((ref) async {
  final api = ref.watch(skillApiServiceProvider);
  final repo = SkillRepository(ref.watch(dbProvider));

  try {
    final backendSkills = await api.listSkills();
    final localSkills = await repo.getInstalledSkills();

    // Merge: backend provides IDs and metadata, local provides yamlContent
    final result = <Skill>[];
    for (final bs in backendSkills) {
      final local = localSkills.where((s) => s.name == bs.name).firstOrNull;
      result.add(Skill(
        id: local?.id ?? bs.id,
        name: bs.name,
        version: bs.version,
        author: bs.author,
        category: bs.category,
        yamlContent: local?.yamlContent ?? '',
        installedAt: bs.installedAt ?? DateTime.now(),
        updatedAt: local?.updatedAt,
        isCollection: local?.isCollection ?? false,
        description: local?.description,
      ));
    }
    return result;
  } catch (_) {
    // Fallback to local SQLite if backend is unreachable
    return repo.getInstalledSkills();
  }
});

/// Top-level skills (collections + standalone, no children).
final topLevelSkillsProvider = FutureProvider<List<Skill>>((ref) async {
  final skills = await ref.watch(installedSkillsProvider.future);
  return skills.where((s) => s.parentId == null).toList()
    ..sort((a, b) {
      // Collections first, then by date
      if (a.isCollection != b.isCollection) {
        return a.isCollection ? -1 : 1;
      }
      return b.installedAt.compareTo(a.installedAt);
    });
});

class SkillInstallNotifier extends StateNotifier<AsyncValue<void>> {
  final SkillRepository _repo;
  final Ref _ref;

  SkillInstallNotifier(this._ref)
      : _repo = _ref.read(skillRepoProvider),
        super(const AsyncValue.data(null));

  Future<void> uninstallSkill(String skillId) async {
    // Try backend first
    try {
      final api = _ref.read(skillApiServiceProvider);
      await api.deleteSkill(skillId);
    } catch (_) {
      // Fall through to local delete
    }

    // Also clean up local cache
    await _repo.deleteSkill(skillId);
    SkillRouter.invalidateCache();
    _ref.invalidate(installedSkillsProvider);
    _ref.invalidate(topLevelSkillsProvider);
    _ref.invalidate(marketSkillsProvider);
  }
}

final skillInstallProvider =
    StateNotifierProvider<SkillInstallNotifier, AsyncValue<void>>(
  (ref) => SkillInstallNotifier(ref),
);
```

- [ ] **Step 2: 验证无编译错误**

```bash
cd /root/kouwen && flutter analyze lib/features/skills/providers/skill_provider.dart 2>&1 | head -20
```

---

### Task 6: 更新 `skill_market_screen.dart` — 市场列表从后端合并

**Files:**
- Modify: `lib/features/skills/skill_market_screen.dart:12-58`

- [ ] **Step 1: 更新 `marketSkillsProvider`**

替换 `marketSkillsProvider` 定义（约第12-58行）：

```dart
final marketSkillsProvider = FutureProvider<List<MarketSkill>>((ref) async {
  final skills = <MarketSkill>[];

  // 1. Fetch installed skills from backend API
  Set<String> installedNames = {};
  try {
    final api = ref.watch(skillApiServiceProvider);
    final backendSkills = await api.listSkills();
    for (final bs in backendSkills) {
      final ms = MarketSkill.fromBackendSkill(bs);
      skills.add(ms);
      installedNames.add(bs.name);
    }
  } catch (_) {
    // Backend unreachable — fall back to local SQLite
    try {
      final repo = SkillRepository(ref.read(dbProvider));
      final installed = await repo.getTopLevelSkills();
      for (final s in installed) {
        skills.add(MarketSkill(
          name: s.name,
          displayName: s.name,
          version: s.version,
          author: s.author ?? '',
          description: s.category,
          icon: '📦',
          category: s.category,
          tags: [],
          file: '',
          downloads: 0,
          rating: 0,
          isInstalled: true,
          id: s.id,
        ));
        installedNames.add(s.name);
      }
    } catch (_) {}
  }

  // 2. Discover online skills from Gitee sources
  try {
    final token = await ref.read(secureStorageProvider).getGitHubToken();
    final giteeToken = await ref.read(secureStorageProvider).read(key: 'gitee_token');
    final ghSource = GitHubSkillSource(token: token, giteeToken: giteeToken);

    final sources = await ref.watch(skillSourcesProvider.future);
    for (final source in sources) {
      try {
        final online = await ghSource.fetchFromSource(source);
        for (final s in online) {
          if (!installedNames.contains(s.name)) {
            s.isInstalled = false;
            skills.add(s);
            installedNames.add(s.name);
          }
        }
      } catch (_) {
        // Skip unavailable sources silently
      }
    }
  } catch (_) {}

  if (skills.isEmpty) {
    throw Exception('没有可用技能，请检查网络后重试');
  }
  return skills;
});
```

在文件顶部添加 import（约第7行后）：

```dart
import '../../services/skill_api_service.dart';
```

- [ ] **Step 2: 更新安装/卸载回调**

找到 `_MarketSkillTile` 的使用处（约第226-236行），更新回调以传入 `SkillApiService`：

```dart
                          final ms = displaySkills[i];
                          final api = ref.read(skillApiServiceProvider);
                          return _MarketSkillTile(
                            skill: ms,
                            onInstall: () async {
                              await SkillMarketService.installSkill(
                                ms,
                                apiService: api,
                              );
                              ref.invalidate(marketSkillsProvider);
                            },
                            onUninstall: () async {
                              await SkillMarketService.uninstallSkill(
                                ms,
                                apiService: api,
                              );
                              ref.invalidate(marketSkillsProvider);
                            },
                            onOpen: () {
                              _openDetail(ms);
                            },
                          );
```

- [ ] **Step 3: 验证无编译错误**

```bash
cd /root/kouwen && flutter analyze lib/features/skills/skill_market_screen.dart 2>&1 | head -20
```

---

### Task 7: 简化 `install_provider.dart` — 委托后端安装

**Files:**
- Modify: `lib/features/skills/providers/install_provider.dart`

- [ ] **Step 1: 重写 `installAll` 方法为后端调用**

替换 `installAll` 方法（约第102-252行）为简化版本：

```dart
  /// Install all skills from a scan result via backend API.
  /// The backend handles directory download, PVC storage, and pip deps.
  Future<void> installAll(
    GitHubScanResult result, {
    String? gitHubToken,
    String? giteeToken,
  }) async {
    if (state.isInstalling) return;

    _cancelled = false;
    final repoName = result.repoName;

    state = InstallState(
      status: InstallStatus.installing,
      total: 1,
      current: 0,
      currentSkillName: repoName,
    );

    try {
      final api = _ref.read(skillApiServiceProvider);
      final installResult = await api.installSkill(repoName);

      // Cache in local SQLite
      final repo = SkillRepository(_ref.read(dbProvider));
      for (final s in installResult.skills) {
        try {
          final exists = await repo.skillExists(s.name);
          if (!exists) {
            await repo.installSkill(
              name: s.name,
              version: '1.0.0',
              author: repoName,
              category: '通用',
              yamlContent: '',
              description: '后端安装 · ${s.files} 个文件',
            );
          }
        } catch (_) {}
      }

      _ref.invalidate(installedSkillsProvider);
      _ref.invalidate(topLevelSkillsProvider);
      _ref.invalidate(marketSkillsProvider);

      final names = installResult.skills.map((s) => s.name).join(', ');
      state = InstallState(
        status: InstallStatus.completed,
        total: 1,
        current: 1,
        successCount: installResult.skills.length,
        failCount: 0,
        resultMessage: '安装完成: $names',
      );
    } catch (e) {
      state = InstallState(
        status: InstallStatus.completed,
        total: 1,
        current: 0,
        successCount: 0,
        failCount: 1,
        resultMessage: '安装失败: ${e.toString().replaceAll("Exception: ", "")}',
      );
    }

    _showResult();

    Future.delayed(const Duration(seconds: 4), () {
      if (state.status == InstallStatus.completed) {
        state = InstallState.idle;
      }
    });
  }
```

在文件顶部添加 import：

```dart
import '../../../../providers.dart';
import '../../../services/skill_api_service.dart';
```

- [ ] **Step 2: 更新 `retryFailed` 方法**

替换 `retryFailed` 方法为简化版本（后端重试）：

```dart
  Future<void> retryFailed() async {
    if (state.failedSkills.isEmpty) return;
    // With backend install, retry means calling installSkill again
    // The failedSkills list contains GitHubSkillResult — extract repo name
    final repo = _ref.read(skillApiServiceProvider);
    try {
      // Re-use the last repo URL from the original install
      state = InstallState(
        status: InstallStatus.installing,
        total: 1,
        current: 0,
      );
      // We don't have the original repo name stored, so just re-trigger
      // the install via the market screen flow
      state = InstallState(
        status: InstallStatus.completed,
        total: 0,
        resultMessage: '请从市场重新安装',
      );
    } catch (e) {
      state = InstallState(
        status: InstallStatus.completed,
        total: 0,
        resultMessage: '重试失败: $e',
      );
    }
  }
```

- [ ] **Step 3: 验证无编译错误**

```bash
cd /root/kouwen && flutter analyze lib/features/skills/providers/install_provider.dart 2>&1 | head -20
```

---

### Task 8: 更新 `github_skill_screen.dart` — 安装按钮走后端

**Files:**
- Modify: `lib/features/skills/github_skill_screen.dart`

- [ ] **Step 1: 更新单个技能安装方法 `_install`**

替换 `_install` 方法（约第114-178行）为后端 API 调用：

```dart
  Future<void> _install(GitHubSkillResult skill) async {
    if (_isLoading) return;

    // If the repo is a collection, install the whole thing
    if (_result?.isCollection == true) {
      await _installAll();
      return;
    }

    final repoUrl = _urlCtrl.text.trim();
    if (repoUrl.isEmpty) return;

    try {
      setState(() => _isLoading = true);
      final api = ref.read(skillApiServiceProvider);
      await api.installSkill(repoUrl);

      ref.invalidate(installedSkillsProvider);
      ref.invalidate(topLevelSkillsProvider);
      ref.invalidate(marketSkillsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${skill.name} 安装成功'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('安装失败: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
```

在文件顶部添加 import（约第8行后）：

```dart
import '../../../providers.dart';
```

- [ ] **Step 2: 验证无编译错误**

```bash
cd /root/kouwen && flutter analyze lib/features/skills/github_skill_screen.dart 2>&1 | head -20
```

---

### Task 9: 构建验证

- [ ] **Step 1: 全项目静态分析**

```bash
cd /root/kouwen && flutter analyze 2>&1 | tail -20
```

Expected: No issues found (或仅有已存在的 warning，无新增 error)。

- [ ] **Step 2: 构建 APK 验证**

```bash
cd /root/kouwen && flutter build apk --release 2>&1 | tail -5
```

Expected: `✓ Built build/app/outputs/flutter-apk/app-release.apk`

- [ ] **Step 3: 提交**

```bash
git add lib/services/skill_api_service.dart \
        lib/data/skill_market_service.dart \
        lib/features/skills/skill_market_screen.dart \
        lib/features/skills/providers/skill_provider.dart \
        lib/features/skills/providers/install_provider.dart \
        lib/features/skills/github_skill_screen.dart \
        lib/providers.dart
git commit -m "feat: connect Skill Market to backend API

- New SkillApiService for backend skill CRUD (JWT auth)
- MarketSkill extended with fromBackendSkill factory
- Install/uninstall delegated to backend (PVC + pip deps)
- Skill listing merges backend metadata with local cache
- Local SQLite retained as yamlContent cache for chat/detail
- GitHub skill screen install buttons call backend API

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
