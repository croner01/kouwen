import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers.dart';
import '../../data/models.dart';
import '../../data/skill_market_service.dart';
import '../../data/repositories.dart';
import '../../services/github_skill_source.dart';
import '../../data/skill_source_store.dart';
import 'skill_detail_screen.dart';
import 'github_skill_screen.dart';

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

final skillSourcesProvider =
    FutureProvider<List<SkillSource>>((ref) async {
  final sources = <SkillSource>[
    GitHubSkillSource.official,
    GitHubSkillSource.tradingAgentsPlugin,
  ];
  // Load user-added custom sources
  try {
    final store = SkillSourceStore(ref.read(secureStorageProvider));
    final custom = await store.loadCustom();
    sources.addAll(custom);
  } catch (_) {}
  return sources;
});

class SkillMarketScreen extends ConsumerStatefulWidget {
  const SkillMarketScreen({super.key});

  @override
  ConsumerState<SkillMarketScreen> createState() => _SkillMarketScreenState();
}

class _SkillMarketScreenState extends ConsumerState<SkillMarketScreen> {
  String? _selectedCategory;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skillsAsync = ref.watch(marketSkillsProvider);

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: "搜索技能...",
                    border: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 16),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              )
            : const Text('技能市场'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () =>
                ref.invalidate(marketSkillsProvider),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined),
            tooltip: '从 GitHub 加载',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const GitHubSkillScreen()),
              ).then((_) => ref.invalidate(marketSkillsProvider));
            },
          ),
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
          ),
        ],
      ),
      body: skillsAsync.when(
        data: (allSkills) {
          final categories = SkillMarketService.getCategories(allSkills);
          var displaySkills = allSkills;

          // Filter by category
          if (_selectedCategory != null) {
            displaySkills = displaySkills
                .where((s) => s.category == _selectedCategory)
                .toList();
          }

          // Filter by search
          if (_searchQuery.isNotEmpty) {
            displaySkills =
                SkillMarketService.search(displaySkills, _searchQuery);
          }

          return Column(
            children: [
              // Category chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _buildChip('全部', null),
                    ...categories.map((c) => _buildChip(c, c)),
                  ],
                ),
              ),
              // Results count
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '${displaySkills.length} 个技能',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600),
                    ),
                    if (_searchQuery.isNotEmpty) ...[
                      const Spacer(),
                      Text(
                        '搜索: "$_searchQuery"',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade500),
                      ),
                    ],
                  ],
                ),
              ),
              // Skill list
              Expanded(
                child: displaySkills.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off,
                                size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 8),
                            Text('未找到匹配的技能',
                                style: TextStyle(
                                    color: Colors.grey.shade600)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding:
                            const EdgeInsets.only(top: 4, bottom: 80),
                        itemCount: displaySkills.length,
                        itemBuilder: (_, i) {
                          final ms = displaySkills[i];
                          final api = ref.read(skillApiServiceProvider);
                          return _MarketSkillTile(
                            skill: ms,
                            onInstall: () async {
                              final giteeToken = await ref.read(secureStorageProvider).read(key: 'gitee_token');
                              await SkillMarketService.installSkill(
                                ms,
                                apiService: api,
                                giteeToken: giteeToken,
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
                              // Find local skill ID and open detail
                              _openDetail(ms);
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在从 GitHub 加载技能...',
                    style: TextStyle(
                        fontSize: 14, color: Colors.grey.shade600)),
              ],
            ),
          ),
        error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off,
                      size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('加载失败',
                      style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  Text('$e'.replaceAll('Exception: ', ''),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () =>
                        ref.invalidate(marketSkillsProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
      ),
    );
  }

  Widget _buildChip(String label, String? category) {
    final isSelected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedCategory = category),
        selectedColor: const Color(0xFF4F46E5).withValues(alpha: 0.1),
        labelStyle: TextStyle(
          color: isSelected
              ? const Color(0xFF4F46E5)
              : Colors.grey.shade700,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  Future<void> _openDetail(MarketSkill ms) async {
    final db = ref.read(dbProvider);
    final repo = SkillRepository(db);
    final installed = await repo.getInstalledSkills();
    Skill? match;
    try {
      match = installed.firstWhere((s) => s.name == ms.name);
    } catch (_) {
      match = null;
    }

    // No local cache — try to create placeholder from backend data
    if (match == null) {
      if (ms.id != null) {
        try {
          // Guard against duplicate insertion
          if (!await repo.skillExists(ms.name)) {
            match = await repo.installSkill(
              name: ms.name,
              version: ms.version,
              author: ms.author,
              category: ms.category,
              yamlContent: '',
              description: '通过后端安装',
            );
          } else {
            // Already exists (race condition with parallel calls) — re-query
            final all = await repo.getInstalledSkills();
            match = all.where((s) => s.name == ms.name).firstOrNull;
          }
        } catch (_) {
          match = null;
        }
      }
    }

    if (match == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('技能未找到，请刷新后重试')),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SkillDetailScreen(skillId: match!.id),
      ),
    );
  }
}

class _MarketSkillTile extends StatelessWidget {
  final MarketSkill skill;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;
  final VoidCallback onOpen;

  const _MarketSkillTile({
    required this.skill,
    required this.onInstall,
    required this.onUninstall,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: skill.isInstalled ? onOpen : onInstall,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: skill.isCollection
                      ? Colors.indigo.shade50
                      : const Color(0xFF4F46E5).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: skill.isCollection
                      ? const Icon(Icons.folder_special,
                          color: Color(0xFF4F46E5), size: 24)
                      : Text(skill.icon,
                          style: const TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                skill.displayName,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              ),
                              if (skill.sourceRepo != null)
                                Text(
                                  'github.com/${skill.sourceRepo}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade400,
                                      fontFamily: 'monospace'),
                                ),
                            ],
                          ),
                        ),
                        if (skill.isInstalled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius:
                                  BorderRadius.circular(10),
                            ),
                            child: Text('已安装',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.green.shade700)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    if (skill.isCollection && skill.childCount != null)
                      Row(
                        children: [
                          Icon(Icons.article_outlined, size: 12,
                              color: Colors.indigo.shade400),
                          const SizedBox(width: 3),
                          Text('${skill.childCount} 个子技能',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.indigo.shade400)),
                        ],
                      )
                    else
                      Text(
                        skill.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _meta(Icons.person_outline, skill.author),
                        const SizedBox(width: 12),
                        _meta(Icons.download_outlined,
                            '${_fmtNum(skill.downloads)}'),
                        const SizedBox(width: 12),
                        _meta(Icons.star,
                            skill.rating.toString(),
                            color: Colors.amber),
                      ],
                    ),
                  ],
                ),
              ),
              // Action button
              if (!skill.isInstalled)
                FilledButton(
                  onPressed: onInstall,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  child:
                      const Text('安装', style: TextStyle(fontSize: 13)),
                )
              else
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.grey.shade400,
                  onPressed: onUninstall,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color ?? Colors.grey.shade500),
        const SizedBox(width: 3),
        Text(text,
            style: TextStyle(
                fontSize: 12,
                color: color ?? Colors.grey.shade500)),
      ],
    );
  }

  String _fmtNum(int n) {
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(1)}k';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }
}
