import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/skill_provider.dart';
import 'providers/install_provider.dart';
import 'widgets/skill_card.dart';
import '../../data/repositories.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import 'skill_detail_screen.dart';
import 'skill_market_screen.dart';
import 'github_skill_screen.dart';

class MySkillsScreen extends ConsumerWidget {
  const MySkillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skillsAsync = ref.watch(topLevelSkillsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的技能'),
      ),
      body: Column(
        children: [
          // Install progress / completion banner
          Consumer(builder: (context, ref, _) {
            final installState = ref.watch(installerProvider);
            if (installState.status == InstallStatus.idle) return const SizedBox.shrink();
            if (installState.isInstalling) {
              final pct = installState.total > 0
                  ? (installState.current / installState.total * 100).toInt()
                  : 0;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.indigo.shade50,
                child: Row(
                  children: [
                    const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('正在后台安装技能... $pct%',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          Text(installState.currentSkillName ?? '',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Text('${installState.current}/${installState.total}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              );
            }
            // Completed with failures — show retry option
            if (installState.status == InstallStatus.completed && installState.hasFailed) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.orange.shade50,
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        installState.resultMessage ?? '部分技能安装失败',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => ref.read(installerProvider.notifier).retryFailed(),
                      icon: const Icon(Icons.refresh, size: 14),
                      label: Text('重试 ${installState.failedNames.length} 个',
                          style: const TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(foregroundColor: Colors.orange.shade800),
                    ),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          }),
          // Skills list
          Expanded(
            child: skillsAsync.when(
        data: (skills) {
          if (skills.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.extension_outlined,
                        size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      '还没有安装任何技能',
                      style: TextStyle(
                          fontSize: 16, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '去市场浏览和安装技能',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  const SkillMarketScreen()),
                        );
                      },
                      icon: const Icon(Icons.store),
                      label: const Text('前往技能市场'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (ctx) =>
                                  const GitHubSkillScreen()),
                        );
                      },
                      icon: const Icon(
                          Icons.cloud_download_outlined),
                      label: const Text('从 Gitee/GitHub 加载'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            itemCount: skills.length,
            itemBuilder: (_, i) {
              final skill = skills[i];
              if (skill.isCollection) {
                return _CollectionTile(
                  skill: skill,
                  onDelete: () {
                    ref
                        .read(skillInstallProvider.notifier)
                        .uninstallSkill(skill.id);
                  },
                );
              }
              return SkillCard(
                skill: skill,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SkillDetailScreen(
                          skillId: skill.id),
                    ),
                  );
                },
                onDelete: () {
                  ref
                      .read(skillInstallProvider.notifier)
                      .uninstallSkill(skill.id);
                },
              );
            },
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    ));
  }
}

/// Expandable tile for skill collections
class _CollectionTile extends StatefulWidget {
  final Skill skill;
  final VoidCallback onDelete;

  const _CollectionTile({required this.skill, required this.onDelete});

  @override
  State<_CollectionTile> createState() => _CollectionTileState();
}

class _CollectionTileState extends State<_CollectionTile> {
  bool _expanded = false;
  List<Skill>? _children;
  bool _loadingChildren = false;

  Future<void> _toggle() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }
    setState(() {
      _expanded = true;
      _loadingChildren = true;
    });
    try {
      final repo = SkillRepository(AppDatabase.instance);
      final children = await repo.getChildSkills(widget.skill.id);
      if (mounted) {
        setState(() {
          _children = children;
          _loadingChildren = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _children = [];
          _loadingChildren = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(Icons.folder_special,
                          color: Color(0xFF4F46E5), size: 22),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.skill.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        if (widget.skill.description != null &&
                            widget.skill.description!.isNotEmpty)
                          Text(
                            widget.skill.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                height: 1.3),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('集合',
                            style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF4F46E5))),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            size: 18, color: Colors.grey.shade400),
                        onPressed: widget.onDelete,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),
                      Icon(
                        _expanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: Colors.grey.shade500,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Expanded children
          if (_expanded) ...[
            const Divider(height: 1),
            if (_loadingChildren)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (_children != null && _children!.isNotEmpty)
              ...(_children!.map((child) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.article_outlined,
                        size: 16, color: Colors.grey),
                    title: Text(child.name.split('/').last,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: child.category.isNotEmpty
                        ? Text(child.category,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500))
                        : null,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              SkillDetailScreen(skillId: child.id),
                        ),
                      );
                      // Refresh children after returning (edit may have changed data)
                      if (mounted) {
                        final repo = SkillRepository(AppDatabase.instance);
                        final updated = await repo.getChildSkills(widget.skill.id);
                        setState(() => _children = updated);
                      }
                    },
                  )))
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('没有子技能',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade500)),
              ),
          ],
        ],
      ),
    );
  }
}
