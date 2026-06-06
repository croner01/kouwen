import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers.dart';
import '../../../data/repositories.dart';
import '../../../services/github_skill_loader.dart';
import 'skill_provider.dart';
import '../skill_market_screen.dart' show marketSkillsProvider;
import '../../../engine/skill_parser.dart';

/// Global scaffold messenger key for showing SnackBars from anywhere.
final GlobalKey<ScaffoldMessengerState> installScaffoldKey =
    GlobalKey<ScaffoldMessengerState>();

// ── Install State ──

enum InstallStatus { idle, installing, completed, failed }

class InstallState {
  final InstallStatus status;
  final int total;
  final int current;
  final int successCount;
  final int failCount;
  final String? currentSkillName;
  final List<String> failedNames;
  final List<GitHubSkillResult> failedSkills;
  final String? resultMessage;
  final String? collectionParentId; // ID of collection parent for nested skills

  const InstallState({
    this.status = InstallStatus.idle,
    this.total = 0,
    this.current = 0,
    this.successCount = 0,
    this.failCount = 0,
    this.currentSkillName,
    this.failedNames = const [],
    this.failedSkills = const [],
    this.resultMessage,
    this.collectionParentId,
  });

  static const idle = InstallState();

  bool get isInstalling => status == InstallStatus.installing;
  bool get hasFailed => failedSkills.isNotEmpty;

  InstallState copyWith({
    InstallStatus? status,
    int? total,
    int? current,
    int? successCount,
    int? failCount,
    String? currentSkillName,
    List<String>? failedNames,
    List<GitHubSkillResult>? failedSkills,
    String? resultMessage,
    Object? collectionParentId = _sentinel,
  }) {
    return InstallState(
      status: status ?? this.status,
      total: total ?? this.total,
      current: current ?? this.current,
      successCount: successCount ?? this.successCount,
      failCount: failCount ?? this.failCount,
      currentSkillName: currentSkillName ?? this.currentSkillName,
      failedNames: failedNames ?? this.failedNames,
      failedSkills: failedSkills ?? this.failedSkills,
      resultMessage: resultMessage ?? this.resultMessage,
      collectionParentId: collectionParentId == _sentinel
          ? this.collectionParentId
          : collectionParentId as String?,
    );
  }
  static const _sentinel = Object();
}

// ── Installer Notifier ──

class InstallerNotifier extends StateNotifier<InstallState> {
  final Ref _ref;
  bool _cancelled = false;

  InstallerNotifier(this._ref) : super(InstallState.idle);

  SkillRepository get _repo => SkillRepository(_ref.read(dbProvider));

  /// Cancel a running installation. Already-installed skills are kept.
  /// Note: does NOT reset state to idle — the running loop terminates
  /// naturally via _cancelled flag on its next iteration check.
  void cancel() {
    _cancelled = true;
  }

  /// Reset state to idle (dismiss completion message).
  void reset() {
    state = InstallState.idle;
  }

  /// Install all skills from a scan result in the background.
  /// Returns immediately; progress is tracked via state.
  Future<void> installAll(
    GitHubScanResult result, {
    String? gitHubToken,
    String? giteeToken,
  }) async {
    if (state.isInstalling) return;

    _cancelled = false;
    final loader = GitHubSkillLoader(
      token: gitHubToken,
      giteeToken: giteeToken,
    );

    final skills = result.skills.where((s) => s.isValid).toList();
    final total = skills.length;
    if (total == 0) {
      state = InstallState(
        status: InstallStatus.completed,
        total: 0,
        resultMessage: '没有可安装的技能',
      );
      _showResult();
      return;
    }

    state = InstallState(
      status: InstallStatus.installing,
      total: total,
    );

    // If this is a collection, install the collection parent first and
    // track its ID so child skills are nested under it.
    String? collectionId;
    if (result.isCollection && result.collection != null) {
      final c = result.collection!;
      final exists = await _repo.skillExists(c.name);
      if (exists) {
        // Collection already installed — find its ID
        final all = await _repo.getInstalledSkills();
        final match = all.where((s) => s.name == c.name && s.isCollection).firstOrNull;
        collectionId = match?.id;
      }
      if (collectionId == null) {
        final collection = await _repo.installSkill(
          name: c.name,
          version: '1.0.0',
          author: result.repoName,
          category: c.category,
          yamlContent: 'name: ${c.name}\ndescription: ${c.description}',
          isCollection: true,
          description: c.description,
        );
        collectionId = collection.id;
      }
    }

    int success = 0;
    int failed = 0;
    int skipped = 0;
    final failedNames = <String>[];
    final failedSkills = <GitHubSkillResult>[];

    for (int i = 0; i < skills.length; i++) {
      if (_cancelled) return;

      final skill = skills[i];
      state = state.copyWith(
        current: i + 1,
        currentSkillName: skill.name,
      );

      try {
        final yaml = await loader.downloadSkillContent(skill.url);
        if (yaml == null) {
          failed++;
          failedNames.add(skill.name);
          failedSkills.add(skill);
          continue;
        }

        // Parse YAML to validate and get real skill name.
        // If parsing fails, the file is not a valid skill → skip silently.
        ParsedSkill parsed;
        try {
          parsed = SkillParser.parse(yaml);
        } catch (_) {
          skipped++;
          continue;
        }

        // Dedup — skip if a skill with the same name already exists
        // For collection children, check within the same parent scope.
        if (await _repo.skillExists(parsed.name, parentId: collectionId)) {
          skipped++;
          continue;
        }

        await _repo.installSkill(
          name: parsed.name,
          version: parsed.version,
          author: skill.author ?? result.repoName,
          category: parsed.category,
          yamlContent: yaml,
          parentId: collectionId,
        );
        success++;
      } catch (_) {
        failed++;
        failedNames.add(skill.name);
        failedSkills.add(skill);
      }
    }

    if (_cancelled) return;

    // Invalidate providers so UI refreshes
    _ref.invalidate(installedSkillsProvider);
    _ref.invalidate(topLevelSkillsProvider);
    _ref.invalidate(marketSkillsProvider);

    final parts = <String>[];
    if (success > 0) parts.add('$success 成功');
    if (skipped > 0) parts.add('$skipped 跳过(非技能/重复)');
    if (failed > 0) parts.add('$failed 失败');
    final msg = parts.isNotEmpty
        ? parts.join('，')
        : '没有可安装的技能';

    state = InstallState(
      status: InstallStatus.completed,
      total: total,
      current: total,
      successCount: success,
      failCount: failed + skipped,
      failedNames: failedNames,
      failedSkills: failedSkills,
      resultMessage: msg,
      collectionParentId: collectionId,
    );

    _showResult();

    // Keep state visible for user to retry failed skills
    if (failedSkills.isEmpty) {
      Future.delayed(const Duration(seconds: 4), () {
        if (state.status == InstallStatus.completed) {
          state = InstallState.idle;
        }
      });
    }
  }

  /// Retry all previously failed skills.
  Future<void> retryFailed() async {
    if (state.failedSkills.isEmpty) return;

    _cancelled = false;
    final loader = GitHubSkillLoader(
      token: await _ref.read(secureStorageProvider).getGitHubToken(),
      giteeToken: await _ref.read(secureStorageProvider).read(key: 'gitee_token'),
    );

    final skills = state.failedSkills.where((s) => s.isValid).toList();
    final total = skills.length;

    state = InstallState(
      status: InstallStatus.installing,
      total: total,
    );

    // Resolve the collection parent for nested skills.
    // Use the ID saved from the original installAll(), or try to find one
    // by author if the state was reset between sessions.
    String? collectionId = state.collectionParentId;
    if (collectionId == null && skills.isNotEmpty) {
      final author = skills.first.author;
      if (author != null) {
        final all = await _repo.getInstalledSkills();
        final match = all.where((s) => s.author == author && s.isCollection).firstOrNull;
        collectionId = match?.id;
      }
    }

    int success = 0;
    int failed = 0;
    final failedNames = <String>[];
    final failedSkills = <GitHubSkillResult>[];

    for (int i = 0; i < skills.length; i++) {
      if (_cancelled) return;

      final skill = skills[i];
      state = state.copyWith(
        current: i + 1,
        currentSkillName: skill.name,
      );

      try {
        final yaml = await loader.downloadSkillContent(skill.url);
        if (yaml == null) {
          failed++;
          failedNames.add(skill.name);
          failedSkills.add(skill);
          continue;
        }

        ParsedSkill parsed;
        try {
          parsed = SkillParser.parse(yaml);
        } catch (_) {
          // Still invalid — count as failed this time
          failed++;
          failedNames.add(skill.name);
          failedSkills.add(skill);
          continue;
        }

        // Dedup within the same scope as the original install
        if (await _repo.skillExists(parsed.name, parentId: collectionId)) {
          continue;
        }

        await _repo.installSkill(
          name: parsed.name,
          version: parsed.version,
          author: skill.author,
          category: parsed.category,
          yamlContent: yaml,
          parentId: collectionId,
        );
        success++;
      } catch (_) {
        failed++;
        failedNames.add(skill.name);
        failedSkills.add(skill);
      }
    }

    if (_cancelled) return;

    _ref.invalidate(installedSkillsProvider);
    _ref.invalidate(topLevelSkillsProvider);
    _ref.invalidate(marketSkillsProvider);

    final parts = <String>[];
    if (success > 0) parts.add('$success 成功');
    if (failed > 0) parts.add('$failed 仍失败');
    final msg = parts.isNotEmpty ? parts.join('，') : '没有可重试的技能';

    state = InstallState(
      status: InstallStatus.completed,
      total: total,
      current: total,
      successCount: success,
      failCount: failed,
      failedNames: failedNames,
      failedSkills: failedSkills,
      resultMessage: msg,
      collectionParentId: collectionId,
    );

    _showResult();

    if (failedSkills.isEmpty) {
      Future.delayed(const Duration(seconds: 4), () {
        if (state.status == InstallStatus.completed) {
          state = InstallState.idle;
        }
      });
    }
  }

  void _showResult() {
    final msg = state.resultMessage;
    if (msg == null || msg.isEmpty) return;
    installScaffoldKey.currentState?.showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: state.failCount > 0 ? Colors.orange : Colors.green,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
  }
}

final installerProvider =
    StateNotifierProvider<InstallerNotifier, InstallState>((ref) {
  return InstallerNotifier(ref);
});
