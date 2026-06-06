import 'dart:convert';
import '../services/secure_storage_service.dart';
import '../services/github_skill_source.dart';

/// Manages user-added custom skill sources stored in SecureStorage.
class SkillSourceStore {
  final SecureStorageService _storage;
  static const _key = 'custom_skill_sources';

  SkillSourceStore(this._storage);

  /// Load custom sources from storage
  Future<List<SkillSource>> loadCustom() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return SkillSource(
          name: m['name'] as String,
          owner: m['owner'] as String,
          repo: m['repo'] as String,
          branch: (m['branch'] as String?) ?? 'main',
          isGitee: (m['isGitee'] as bool?) ?? true,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Save a new custom source (appends to existing)
  Future<void> addCustom(SkillSource source) async {
    final existing = await loadCustom();
    // Dedup by owner/repo/branch to allow same repo with different branches
    if (existing.any((s) =>
        s.owner == source.owner &&
        s.repo == source.repo &&
        s.branch == source.branch)) {
      return;
    }
    existing.add(source);
    await _saveAll(existing);
  }

  /// Remove a custom source
  Future<void> removeCustom(String owner, String repo) async {
    final existing = await loadCustom();
    existing.removeWhere((s) => s.owner == owner && s.repo == repo);
    await _saveAll(existing);
  }

  Future<void> _saveAll(List<SkillSource> sources) async {
    final list = sources
        .map((s) => {
              'name': s.name,
              'owner': s.owner,
              'repo': s.repo,
              'branch': s.branch,
              'isGitee': s.isGitee,
            })
        .toList();
    await _storage.write(key: _key, value: jsonEncode(list));
  }
}
