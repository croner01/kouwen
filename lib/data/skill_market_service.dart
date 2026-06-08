import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'repositories.dart';
import 'database.dart';
import '../services/skill_api_service.dart';
import '../services/github_skill_loader.dart';

/// A skill entry in the market catalog
class MarketSkill {
  final String name;
  final String displayName;
  final String version;
  final String author;
  final String description;
  final String icon;
  final String category;
  final List<String> tags;
  final String file;
  final String? sourceUrl;
  final String? sourceRepo;
  final int downloads;
  final double rating;
  bool isInstalled;
  final bool isCollection;
  final int? childCount;
  String? id; // Backend skill ID, for uninstall
  List<String> pythonDeps; // pip dependency list from backend
  String? yamlContent; // SKILL.md content from backend, for local cache

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
    this.yamlContent,
  });

  factory MarketSkill.fromJson(Map<String, dynamic> json) {
    return MarketSkill(
      name: json['name'] as String,
      displayName: (json['display_name'] as String?) ?? json['name'] as String,
      version: json['version'] as String,
      author: json['author'] as String,
      description: json['description'] as String,
      icon: json['icon'] as String,
      category: json['category'] as String,
      tags: List<String>.from(json['tags'] as List),
      file: json['file'] as String,
      sourceUrl: json['source_url'] as String?,
      sourceRepo: json['source_repo'] as String?,
      downloads: json['downloads'] as int,
      rating: (json['rating'] as num).toDouble(),
      isCollection: json['is_collection'] as bool? ?? false,
      childCount: json['child_count'] as int?,
      yamlContent: json['yaml_content'] as String?,
    );
  }

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
      yamlContent: backend.yamlContent.isNotEmpty ? backend.yamlContent : null,
    );
  }

  static String _iconForCategory(String cat) {
    switch (cat) {
      case '科技':
        return '\u{1F4BB}';
      case '设计':
        return '\u{1F3A8}';
      case '文档':
        return '\u{1F4C4}';
      case '财经':
        return '\u{1F4C8}';
      case '法律':
        return '\u{2696}';
      case '医疗':
        return '\u{1F3E5}';
      case '教育':
        return '\u{1F393}';
      default:
        return '\u{1F916}';
    }
  }
}

class SkillMarketService {
  static List<MarketSkill>? _cached;

  /// Clear the cached catalog (call after skill install/uninstall).
  static void clearCache() => _cached = null;

  /// Load the catalog from assets and mark which are installed.
  /// Pass [forceRefresh] to bypass the cache and re-read from assets.
  static Future<List<MarketSkill>> loadCatalog({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null) return _cached!;

    final jsonStr = await rootBundle.loadString('assets/skills/catalog.json');
    final list = jsonDecode(jsonStr) as List;
    final skills = list.map((e) => MarketSkill.fromJson(e as Map<String, dynamic>)).toList();

    // Mark installed skills
    final repo = SkillRepository(AppDatabase.instance);
    final installed = await repo.getInstalledSkills();
    final installedNames = installed.map((s) => s.name).toSet();

    for (final skill in skills) {
      skill.isInstalled = installedNames.contains(skill.name);
    }

    _cached = skills;
    return skills;
  }

  /// Install a skill via backend API. Backend handles full directory download,
  /// PVC storage, and pip dependency installation.
  /// Requires [apiService] for the backend call and optionally saves a local
  /// cache record for yamlContent access.
  static Future<InstallResult> installSkill(
    MarketSkill skill, {
    required SkillApiService apiService,
    String? giteeToken,
  }) async {
    if (skill.sourceRepo == null) {
      throw Exception('该技能没有来源仓库');
    }
    // Backend handles everything: scan, download, PVC, pip, PostgreSQL
    final result = await apiService.installSkill(skill.sourceRepo!, giteeToken: giteeToken);
    skill.isInstalled = true;

    // Set backend ID so user can immediately uninstall without re-fetching list
    if (result.skills.isNotEmpty) {
      skill.id = result.skills.first.id;
    }

    // Also save to local SQLite as cache (for yamlContent access in chat/detail)
    if (result.skills.isNotEmpty) {
      try {
        // Try to download SKILL.md content for local cache using GitHubSkillLoader
        // which has Gitee branch fallback and auth support.
        String? yamlContent;
        if (skill.sourceUrl != null) {
          try {
            final loader = GitHubSkillLoader(giteeToken: giteeToken);
            yamlContent = await loader.downloadSkillContent(skill.sourceUrl!);
          } catch (e) {
            // ignore: avoid_print
            print('SkillMarketService: SKILL.md download failed ($e)');
          }
        }

        final repo = SkillRepository(AppDatabase.instance);

        // If the market skill is a collection, create a parent entry so
        // children are grouped under an expandable collection tile.
        String? collectionParentId;
        if (skill.isCollection && skill.sourceRepo != null) {
          final allInstalled = await repo.getInstalledSkills();
          final existing = allInstalled.where(
                (s) => s.name == skill.sourceRepo && s.isCollection,
              ).firstOrNull;
          if (existing != null) {
            collectionParentId = existing.id;
          } else {
            final parent = await repo.installSkill(
              name: skill.sourceRepo!,
              version: '1.0.0',
              author: skill.author,
              category: skill.category,
              yamlContent: '',
              isCollection: true,
              description: skill.displayName,
            );
            collectionParentId = parent.id;
          }
        }

        for (final s in result.skills) {
          try {
            final exists = await repo.skillExists(s.name,
                parentId: collectionParentId);
            if (exists) continue;
            await repo.installSkill(
              name: s.name,
              version: '1.0.0',
              author: skill.author,
              category: skill.category,
              yamlContent: yamlContent ?? '',
              parentId: collectionParentId,
              description: '通过后端安装 · ${s.files} 个文件',
            );
          } catch (e) {
            // ignore: avoid_print
            print('SkillMarketService: local cache write failed for ${s.name} ($e)');
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('SkillMarketService: local cache sync failed ($e)');
      }
    }

    clearCache();
    return result;
  }

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

  /// Search skills by name, description, or tags
  static List<MarketSkill> search(List<MarketSkill> skills, String query) {
    final q = query.toLowerCase();
    return skills.where((s) {
      return s.name.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q) ||
          s.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }

  /// Get unique categories from the catalog
  static List<String> getCategories(List<MarketSkill> skills) {
    return skills.map((s) => s.category).toSet().toList()..sort();
  }
}
