import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers.dart';
import '../../../data/models.dart';
import '../../../data/repositories.dart';
import '../../../engine/skill_router.dart';
import '../skill_market_screen.dart' show marketSkillsProvider;

/// Installed skills from backend API, enriched with local cache data.
final installedSkillsProvider = FutureProvider<List<Skill>>((ref) async {
  final api = ref.watch(skillApiServiceProvider);
  final repo = SkillRepository(ref.watch(dbProvider));

  try {
    final backendSkills = await api.listSkills();
    final localSkills = await repo.getInstalledSkills();

    // Merge: backend provides IDs, metadata, and yamlContent;
    // local cache fills in collection/description when available.
    final result = <Skill>[];
    for (final bs in backendSkills) {
      final local =
          localSkills.where((s) => s.name == bs.name).firstOrNull;
      // Prefer local yamlContent if non-empty, otherwise use backend's
      final yaml = (local != null && local.yamlContent.isNotEmpty)
          ? local.yamlContent
          : bs.yamlContent;
      result.add(Skill(
        id: local?.id ?? bs.id,
        name: bs.name,
        version: bs.version,
        author: bs.author,
        category: bs.category,
        yamlContent: yaml,
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
