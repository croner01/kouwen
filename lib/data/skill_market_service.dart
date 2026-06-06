import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'models.dart';
import 'repositories.dart';
import 'database.dart';
import '../services/github_skill_loader.dart';
import '../services/secure_storage_service.dart';
import '../engine/skill_parser.dart';

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
    );
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

  /// Install a skill from the market — downloads real content from GitHub/Gitee.
  /// For collections, scans the repo and installs all child skills under a parent.
  static Future<void> installSkill(MarketSkill skill) async {
    final repo = SkillRepository(AppDatabase.instance);

    // Guard against duplicate installs
    final installed = await repo.getInstalledSkills();
    if (installed.any((s) => s.name == skill.name)) {
      throw Exception('${skill.displayName} 已安装');
    }

    if (skill.isCollection && skill.sourceRepo != null) {
      // Install entire collection
      await _installCollection(skill, repo);
      skill.isInstalled = true;
      return;
    }

    if (skill.sourceUrl == null) {
      throw Exception('该技能没有来源');
    }

    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 10);
    dio.options.receiveTimeout = const Duration(seconds: 30);
    final resp = await dio.get(skill.sourceUrl!);
    if (resp.statusCode != 200 || resp.data == null) {
      throw Exception('下载失败 (${resp.statusCode})');
    }

    await repo.installSkill(
      name: skill.name,
      version: skill.version,
      author: skill.author,
      category: skill.category,
      yamlContent: resp.data.toString(),
    );
    skill.isInstalled = true;
  }

  /// Install a collection: scan repo, create parent, install all children
  static Future<void> _installCollection(
      MarketSkill skill, SkillRepository repo) async {
    final parts = skill.sourceRepo!.split('/');
    if (parts.length < 2) throw Exception('仓库地址格式错误');

    final storage = SecureStorageService();
    final giteeToken = await storage.read(key: 'gitee_token');
    final loader = GitHubSkillLoader(giteeToken: giteeToken);
    final result = await loader.scanRepo(skill.sourceRepo!);
    if (result.error != null) throw Exception(result.error);
    if (!result.isCollection || result.collection == null) {
      throw Exception('该仓库不是技能集合');
    }

    final coll = result.collection!;

    // Create parent collection
    final parent = await repo.installSkill(
      name: coll.name,
      version: '1.0.0',
      author: coll.repoName,
      category: coll.category,
      yamlContent: '',
      isCollection: true,
      description: coll.description,
    );

    // Install each child
    for (final child in coll.childSkills) {
      final yaml = await loader.downloadSkillContent(child.url);
      if (yaml == null) continue;

      final childName = child.path
          .split('/')
          .reversed
          .skip(1)
          .firstOrNull
          ?.replaceAll('-', ' ')
          .replaceAll('_', ' ') ?? child.name;
      final childKey = '${coll.name}/$childName';

      String cat = child.category ?? coll.category;
      try {
        final parsed = SkillParser.parse(yaml);
        cat = parsed.category;
      } catch (_) {}

      await repo.installSkill(
        name: childKey,
        version: '1.0.0',
        author: coll.repoName,
        category: cat,
        yamlContent: yaml,
        parentId: parent.id,
      );
    }
  }

  /// Uninstall a skill. Silently succeeds if already uninstalled.
  static Future<void> uninstallSkill(MarketSkill skill) async {
    final repo = SkillRepository(AppDatabase.instance);
    final installed = await repo.getInstalledSkills();
    Skill? match;
    try {
      match = installed.firstWhere((s) => s.name == skill.name);
    } catch (_) {
      // Already uninstalled — nothing to do
      skill.isInstalled = false;
      return;
    }
    await repo.deleteSkill(match.id);
    skill.isInstalled = false;
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
