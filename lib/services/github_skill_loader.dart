import 'package:dio/dio.dart';
import '../engine/skill_parser.dart';

class GitHubSkillResult {
  final String name;
  final String path;
  final String url;
  final String? category;
  final String? author; // repo attribution (owner/repo)
  ParsedSkill? parsed;
  final String? error;

  GitHubSkillResult({
    required this.name,
    required this.path,
    required this.url,
    this.category,
    this.author,
    this.parsed,
    this.error,
  });

  bool get isValid => error == null;
}

/// Collection-level result for repos that contain subdirs of skills
class GitHubCollectionResult {
  final String name;
  final String repoName;
  final String description;
  final String category;
  final List<GitHubSkillResult> childSkills;

  const GitHubCollectionResult({
    required this.name,
    required this.repoName,
    required this.description,
    required this.category,
    required this.childSkills,
  });
}

class GitHubSkillLoader {
  final Dio _dio;
  final String? _token;
  final String? _giteeToken;

  GitHubSkillLoader({Dio? dio, String? token, String? giteeToken})
      : _dio = dio ?? Dio(),
        _token = token,
        _giteeToken = giteeToken {
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
  }

  Map<String, String> _getHeaders({bool isGitee = false}) {
    // Gitee uses ?access_token= query parameter, not Bearer header
    if (isGitee) return {};
    if (_token == null) return {};
    return {'Authorization': 'Bearer $_token'};
  }

  /// Append Gitee access_token query param if a token is configured.
  String _giteeAuth(String url) {
    if (_giteeToken == null || _giteeToken.isEmpty) return url;
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}access_token=$_giteeToken';
  }

  /// Chinese descriptions for known skill collections
  static const _collectionDescriptions = {
    'ren02/skills': 'Anthropic 官方技能集 — 包含代码审查、MCP构建、设计系统等专业开发技能，覆盖全栈开发场景',
    'ren02/marketplace': 'AI SkillStore 市场 — 安全审计与一键安装工具集，社区精选技能合集',
    'ren02/claude-trading-skills': '量化交易策略库 — 50+交易技能，覆盖选股、回测、技术分析、策略优化全流程',
    'ren02/awesome-medical-ai-skills-c': '家庭医生·医疗AI工具集 — 中文医疗问诊、症状分析、健康管理一站式技能包',
    'ren02/claude-legal-skill': '合同审查助手 — CUAD风险检测、红线批注、合同条款智能分析',
    'ren02/ai-legal-claude': 'AI法律助手 — 14个法律专业Skill，并行Agent协作，覆盖多领域法律实务',
    'ren02/claude-for-legal': '法律实务套件 — 12个实践领域、70+法律Agent，企业法务全场景覆盖',
    'ren02/education-agent-skills': '教育技能库 — 152个教学法Skill，覆盖全学段全学科，智能教学设计',
    'ren02/claude-skills': 'DevOps工具箱 — 32个运维安全技能，覆盖CI/CD、监控、SecOps全链路',
  };

  /// Detect whether a repo is a collection (skills under subdirectories).
  /// Returns null if flat (skills at root), or a GitHubCollectionResult if nested.
  GitHubCollectionResult? detectCollection(
    String owner, String repo, String branch, List<GitHubSkillResult> skills) {
    // Group skills by their top-level directory
    final groups = <String, List<GitHubSkillResult>>{};
    final rootSkills = <GitHubSkillResult>[];

    for (final s in skills) {
      final parts = s.path.split('/');
      if (parts.length <= 1) {
        // Root-level file
        rootSkills.add(s);
      } else {
        final dir = parts[0];
        groups.putIfAbsent(dir, () => []).add(s);
      }
    }

    // If most files are in subdirectories, treat as a collection
    final totalInDirs = groups.values.fold<int>(0, (sum, l) => sum + l.length);
    if (totalInDirs > rootSkills.length && groups.isNotEmpty) {
      final repoName = '$owner/$repo';
      final desc = _collectionDescriptions[repoName] ??
          _collectionDescriptions.entries
              .firstWhere(
                (e) => e.key.contains(repo.toLowerCase()),
                orElse: () => const MapEntry('', ''),
              )
              .value;
      return GitHubCollectionResult(
        name: repo.replaceAll('-', ' ').replaceAll('_', ' '),
        repoName: repoName,
        description: desc.isNotEmpty ? desc : '$repo 技能集合',
        category: _guessCollectionCategory(repo, groups),
        childSkills: skills,
      );
    }
    return null;
  }

  String _guessCollectionCategory(
      String repo, Map<String, List<GitHubSkillResult>> groups) {
    final lower = repo.toLowerCase();
    if (lower.contains('legal') || lower.contains('law')) return '法律';
    if (lower.contains('medical') || lower.contains('health')) return '医疗';
    if (lower.contains('edu') || lower.contains('tutor')) return '教育';
    if (lower.contains('trade') || lower.contains('stock') || lower.contains('invest')) return '财经';
    if (lower.contains('devops') || lower.contains('skill')) return '科技';
    return '通用';
  }

  /// Fast scan: list SKILL.md files, no content download.
  /// Supports both Gitee and GitHub repos.
  Future<GitHubScanResult> scanRepo(String repoUrl) async {
    String owner = '';
    String repo = '';
    String branch = 'main';
    bool isGitee = false;

    final input = repoUrl.trim();

    // Use Uri.parse to avoid fragile hardcoded substring counts.
    // 'https://gitee.com/' is 18 chars but old code used substring(19) — off-by-1!
    if (input.startsWith('http://') || input.startsWith('https://')) {
      final uri = Uri.parse(input);
      final host = uri.host.toLowerCase();
      final path = uri.pathSegments.where((s) => s.isNotEmpty).toList();

      if (host.contains('gitee.com')) {
        isGitee = true;
      }

      if (path.length >= 2) {
        owner = path[0];
        repo = path[1];
        // Handle optional /tree/branch in GitHub-style URLs
        if (path.length >= 4 && path[2] == 'tree') {
          branch = path[3];
        } else if (path.length >= 3) {
          branch = path[2];
        }
      }
    } else {
      // No protocol — plain "owner/repo" or "owner/repo/branch"
      // Default to Gitee for bare paths (primary source for Chinese users)
      isGitee = true;
      final parts = input.split('/').where((s) => s.isNotEmpty).toList();
      if (parts.length >= 2) {
        owner = parts[0];
        repo = parts[1];
        if (parts.length >= 3) branch = parts[2];
      } else if (parts.length == 1) {
        owner = parts[0];
      }
    }

    if (owner.isEmpty || repo.isEmpty) {
      return GitHubScanResult(
        repoName: repoUrl,
        error: '格式错误，无法从 "$repoUrl" 中解析 owner/repo',
      );
    }

    print('[scanRepo] input="$repoUrl" → owner="$owner" repo="$repo" branch="$branch" isGitee=$isGitee');

    if (repo.length < 3) {
      return GitHubScanResult(
        repoName: '$owner/$repo',
        error: '仓库名 "$repo" 过短，请检查是否输入完整\n例如: ren02/skills',
      );
    }

    try {
      // Use Gitee or GitHub API based on URL
      var treeUrl = isGitee
          ? 'https://gitee.com/api/v5/repos/$owner/$repo/git/trees/$branch?recursive=1'
          : 'https://api.github.com/repos/$owner/$repo/git/trees/$branch?recursive=1';
      // Gitee private token uses ?access_token= query param, not Bearer header
      if (isGitee) treeUrl = _giteeAuth(treeUrl);
      final resp = await _dio.get(treeUrl, options: Options(headers: _getHeaders(isGitee: isGitee)));
      if (resp.statusCode != 200) {
        return GitHubScanResult(
          repoName: '$owner/$repo',
          error: '仓库不存在或无权限 (${resp.statusCode})',
        );
      }

      final tree = resp.data['tree'] as List<dynamic>?;
      if (tree == null) {
        return GitHubScanResult(
          repoName: '$owner/$repo',
          error: '仓库为空',
        );
      }

      // Detect whether this repo has a structured skills/ directory.
      // Match case-insensitively and also via startsWith in case the
      // directory entry is a subpath rather than a standalone tree entry.
      final hasSkillsDir = tree.any((e) {
        final p = (e as Map<String, dynamic>)['path'] as String? ?? '';
        final lower = p.toLowerCase();
        return lower == 'skills' || lower.startsWith('skills/');
      });

      // Only discover skill files — no content download.
      // For structured repos (has skills/ dir), only accept SKILL.md/claude.md
      // inside the skills/ directory. This excludes reference/docs files.
      // For flat repos, use the original broader filter.
      final found = <GitHubSkillResult>[];
      for (final e in tree) {
        final entry = e as Map<String, dynamic>;
        final path = entry['path'] as String? ?? '';
        final name = path.split('/').last.toLowerCase();

        if (hasSkillsDir) {
          // ── Structured repo ──
          // Only skill files under the skills/ directory
          if (!path.startsWith('skills/')) continue;

          // Only accept SKILL.md or claude.md (not reference docs)
          if (name != 'skill.md' && name != 'claude.md') continue;
        } else {
          // ── Flat repo (no skills/ dir) — original broad filter ──
          // Must be a skill file — accept .md (any name), .yaml, .yml
          final isSkillMd = name.endsWith('.md') &&
              name != 'readme.md' &&
              name != 'license.md' &&
              !name.startsWith('.');
          final isSkillYaml = name.endsWith('.yaml') || name.endsWith('.yml');
          if (!isSkillMd && !isSkillYaml) continue;

          // Skip hidden / config dirs
          if (path.startsWith('.') ||
              path.contains('/.github/') ||
              path.contains('/.claude/') ||
              path.contains('/examples/') ||
              path.contains('/docs/') ||
              path.contains('/scripts/')) {
            continue;
          }

          // Skip root-level CLAUDE.md (repo readme, not a skill)
          if (name == 'claude.md' && !path.contains('/')) continue;

          // Skip known config/index files
          if (name.endsWith('.yaml') || name.endsWith('.yml')) {
            final skipNames = [
              'pubspec.yaml', 'pubspec.yml', 'analysis_options.yaml',
              '.pre-commit-config.yaml', 'skills-index.yaml',
              '_config.yml', 'marketplace.json',
            ];
            if (skipNames.contains(name) || name.startsWith('.')) continue;
          }
        }

        final rawUrl = isGitee
            ? 'https://gitee.com/$owner/$repo/raw/$branch/$path'
            : 'https://raw.githubusercontent.com/$owner/$repo/$branch/$path';

        // Compute display name:
        //   Structured repo → parent directory name (e.g. "backtest-expert")
        //   Flat repo → filename (e.g. "code-review.md")
        final parts = path.split('/');
        final displayName = hasSkillsDir && parts.length >= 2
            ? parts[parts.length - 2]
            : parts.last;

        found.add(GitHubSkillResult(
          name: displayName,
          path: path,
          url: rawUrl,
          category: _guessCategory(path),
          author: '$owner/$repo',
        ));
      }

      final collection = detectCollection(owner, repo, branch, found);
      return GitHubScanResult(
        repoName: '$owner/$repo',
        skills: found,
        branch: branch,
        collection: collection,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      final reqUrl = e.requestOptions.uri.toString();
      if (code == 404) {
        return GitHubScanResult(
          repoName: '$owner/$repo',
          error: '仓库 $owner/$repo 不存在 (404)\n'
              '请检查仓库名是否正确，或该仓库为私有\n'
              '请求: $reqUrl',
        );
      }
      if (code == 403) {
        final hint = isGitee
            ? 'Gitee API 频率限制：未认证每小时仅 100 次请求，连续操作容易耗尽。\n'
              '解决方法：去 设置→Git 服务→Gitee 配置私人令牌，认证后每小时 5000 次。\n'
              '（在 gitee.com 设置→私人令牌 中生成，无需特殊权限）'
            : 'GitHub API 需要 Personal Access Token 才能访问（即便是公开仓库）。\n'
              '解决方法：\n'
              '1. 在设置→Git 服务→GitHub 中连接 Token\n'
              '2. 或者使用 Gitee 地址：直接输入 "用户名/仓库名"（不加协议）默认走 Gitee';
        return GitHubScanResult(
          repoName: '$owner/$repo',
          error: 'API 访问受限 (403)\n$hint',
        );
      }
      return GitHubScanResult(
        repoName: '$owner/$repo',
        error: '网络错误 ($code): ${e.message}\n请求: $reqUrl',
      );
    } catch (e) {
      return GitHubScanResult(
        repoName: '$owner/$repo',
        error: '扫描失败: $e',
      );
    }
  }

  /// Download and parse a single skill's content from GitHub/Gitee.
  /// For Gitee, tries the given branch first, then falls back to main/master
  /// if the first attempt 404s (same fix as _readGiteeFile in github_service.dart).
  Future<String?> downloadSkillContent(String url) async {
    final isGitee = url.contains('gitee.com');
    try {
      final resp = await _dio.get(url,
          options: Options(headers: _getHeaders(isGitee: isGitee)));
      if (resp.statusCode == 200) {
        return resp.data.toString();
      }
    } catch (_) {}

    // Gitee branch fallback: the raw URL may use the wrong branch name.
    // Try both main and master if the original attempt failed.
    if (isGitee) {
      for (final branch in ['main', 'master']) {
        try {
          final fallbackUrl =
              url.replaceAll(RegExp(r'/raw/[^/]+/'), '/raw/$branch/');
          if (fallbackUrl == url) continue; // already tried this branch
          final resp = await _dio.get(fallbackUrl,
              options: Options(headers: _getHeaders(isGitee: true)));
          if (resp.statusCode == 200) {
            return resp.data.toString();
          }
        } catch (_) {}
      }
    }

    return null;
  }

  String _guessCategory(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('code') || lower.contains('mcp') ||
        lower.contains('api') || lower.contains('web')) return '科技';
    if (lower.contains('design') || lower.contains('brand') ||
        lower.contains('theme') || lower.contains('art')) return '设计';
    if (lower.contains('doc') || lower.contains('xls') ||
        lower.contains('pdf') || lower.contains('pptx')) return '文档';
    if (lower.contains('trade') || lower.contains('stock') ||
        lower.contains('backtest') || lower.contains('investment')) return '财经';
    if (lower.contains('test')) return '科技';
    return '通用';
  }
}

class GitHubScanResult {
  final String repoName;
  final String? branch;
  final List<GitHubSkillResult> skills;
  final String? error;
  final GitHubCollectionResult? collection;

  const GitHubScanResult({
    required this.repoName,
    this.branch,
    this.skills = const [],
    this.error,
    this.collection,
  });

  int get validCount => skills.where((s) => s.isValid).length;
  bool get isCollection => collection != null;
}
