import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers.dart';
import '../../../data/repositories.dart';
import '../../../services/github_skill_loader.dart';
import 'skill_provider.dart';
import '../skill_market_screen.dart' show marketSkillsProvider;

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
  final String? lastGiteeToken; // Saved for retry

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
    this.lastGiteeToken,
  });

  static const idle = InstallState();

  bool get isInstalling => status == InstallStatus.installing;
  bool get hasFailed => failedSkills.isNotEmpty || failedNames.isNotEmpty;

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
    Object? lastGiteeToken = _sentinel,
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
      lastGiteeToken: lastGiteeToken == _sentinel
          ? this.lastGiteeToken
          : lastGiteeToken as String?,
    );
  }
  static const _sentinel = Object();
}

// ── Installer Notifier ──

class InstallerNotifier extends StateNotifier<InstallState> {
  final Ref _ref;

  InstallerNotifier(this._ref) : super(InstallState.idle);

  /// Cancel a running installation.
  void cancel() {
    state = InstallState.idle;
  }

  /// Reset state to idle (dismiss completion message).
  void reset() {
    state = InstallState.idle;
  }

  /// Install all skills from a scan result via backend API.
  /// The backend handles directory download, PVC storage, and pip deps.
  Future<void> installAll(
    GitHubScanResult result, {
    String? gitHubToken,
    String? giteeToken,
  }) async {
    if (state.isInstalling) return;

    final repoName = result.repoName;

    state = InstallState(
      status: InstallStatus.installing,
      total: 1,
      current: 0,
      currentSkillName: repoName,
    );

    try {
      final api = _ref.read(skillApiServiceProvider);
      final installResult = await api.installSkill(repoName, giteeToken: giteeToken);

      // Cache in local SQLite for yamlContent access.
      // Try to download SKILL.md from Gitee for each installed skill.
      final repo = SkillRepository(_ref.read(dbProvider));

      // If the repo is a collection, create a parent entry so children
      // are grouped under an expandable tile with proper parentId.
      String? collectionParentId;
      if (result.isCollection && result.collection != null) {
        final allInstalled = await repo.getInstalledSkills();
        final existing = allInstalled.where(
              (s) => s.name == repoName && s.isCollection,
            ).firstOrNull;
        if (existing != null) {
          collectionParentId = existing.id;
        } else {
          final parent = await repo.installSkill(
            name: repoName,
            version: '1.0.0',
            author: repoName,
            category: result.collection!.category.isNotEmpty
                ? result.collection!.category
                : '通用',
            yamlContent: '',
            isCollection: true,
            description: result.collection!.description.isNotEmpty
                ? result.collection!.description
                : '${result.collection!.name} 集合',
          );
          collectionParentId = parent.id;
        }
      }

      for (final s in installResult.skills) {
        try {
          final exists = await repo.skillExists(s.name, parentId: collectionParentId);
          if (exists) continue;

          // Look up the GitHubSkillResult to get the raw URL for SKILL.md
          String? yamlContent;
          final match = result.skills
              .where((r) => r.isValid &&
                  (r.name == s.name ||
                   r.path.contains(s.name)))
              .firstOrNull;
          if (match != null) {
            final loader = GitHubSkillLoader(
              token: gitHubToken,
              giteeToken: giteeToken,
            );
            yamlContent = await loader.downloadSkillContent(match.url);
          }

          await repo.installSkill(
            name: s.name,
            version: '1.0.0',
            author: repoName,
            category: '通用',
            yamlContent: yamlContent ?? '',
            parentId: collectionParentId,
            description: '后端安装 · ${s.files} 个文件',
          );
        } catch (e) {
          // ignore: avoid_print
          print('install_provider: local cache write failed for ${s.name}: $e');
        }
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
        failedNames: [repoName],
        lastGiteeToken: giteeToken,
        resultMessage:
            '安装失败: ${e.toString().replaceAll("Exception: ", "")}',
      );
    }

    _showResult();

    Future.delayed(const Duration(seconds: 4), () {
      if (state.status == InstallStatus.completed) {
        state = InstallState.idle;
      }
    });
  }

  /// Retry all previously failed skills by re-triggering backend install.
  Future<void> retryFailed() async {
    if (state.failedNames.isEmpty || state.isInstalling) return;
    final repoName = state.failedNames.first;
    state = InstallState(
      status: InstallStatus.installing,
      total: 1,
      current: 0,
      currentSkillName: repoName,
    );
    try {
      final api = _ref.read(skillApiServiceProvider);
      final installResult = await api.installSkill(repoName, giteeToken: state.lastGiteeToken);

      // Sync yamlContent from backend into local cache (retry may have
      // succeeded but original install had empty yamlContent due to download failure).
      try {
        final repo = SkillRepository(_ref.read(dbProvider));
        final backendSkills = await api.listSkills();
        for (final bs in backendSkills) {
          if (bs.yamlContent.isEmpty) continue;
          final installed = await repo.getInstalledSkills();
          final existing = installed.where((s) => s.name == bs.name).firstOrNull;
          if (existing != null && existing.yamlContent.isEmpty) {
            await repo.updateSkillYamlContent(existing.id, bs.yamlContent);
          }
        }
      } catch (_) {
        // Non-fatal — yamlContent will be fetched on next market screen open
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
        resultMessage: '重试成功: $names',
      );
    } catch (e) {
      state = InstallState(
        status: InstallStatus.completed,
        total: 1,
        current: 0,
        successCount: 0,
        failCount: 1,
        failedNames: [repoName],
        resultMessage:
            '重试失败: ${e.toString().replaceAll("Exception: ", "")}',
      );
    }
    _showResult();
    Future.delayed(const Duration(seconds: 4), () {
      if (state.status == InstallStatus.completed) {
        state = InstallState.idle;
      }
    });
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
