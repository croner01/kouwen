import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers.dart';
import '../../../data/models.dart';
import '../../../data/repositories.dart';
import '../../../engine/skill_router.dart';
import '../skill_market_screen.dart' show marketSkillsProvider;

final installedSkillsProvider = FutureProvider<List<Skill>>((ref) async {
  final repo = SkillRepository(ref.watch(dbProvider));
  return repo.getInstalledSkills();
});

/// Only top-level skills (collections + standalone, no children)
final topLevelSkillsProvider = FutureProvider<List<Skill>>((ref) async {
  final repo = SkillRepository(ref.watch(dbProvider));
  return repo.getTopLevelSkills();
});

class SkillInstallNotifier extends StateNotifier<AsyncValue<void>> {
  final SkillRepository _repo;
  final Ref _ref;

  SkillInstallNotifier(this._ref)
      : _repo = _ref.read(skillRepoProvider),
        super(const AsyncValue.data(null));

  Future<void> uninstallSkill(String skillId) async {
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
