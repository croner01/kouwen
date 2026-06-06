import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers.dart';
import '../../services/github_skill_source.dart';
import '../../services/github_skill_loader.dart';
import '../../data/skill_source_store.dart';
import '../skills/skill_market_screen.dart' show marketSkillsProvider, skillSourcesProvider;

class SkillSourcesScreen extends ConsumerStatefulWidget {
  const SkillSourcesScreen({super.key});

  @override
  ConsumerState<SkillSourcesScreen> createState() =>
      _SkillSourcesScreenState();
}

class _SkillSourcesScreenState
    extends ConsumerState<SkillSourcesScreen> {
  final _ownerCtrl = TextEditingController();
  final _repoCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isValidating = false;

  @override
  void dispose() {
    _ownerCtrl.dispose();
    _repoCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(skillSourcesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('技能来源')),
      body: ListView(
        children: [
          _SectionHeader(title: '已添加的来源'),
          sourcesAsync.when(
            data: (sources) {
              if (sources.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.cloud_off,
                          size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('暂无外部来源',
                          style: TextStyle(
                              color: Colors.grey.shade600)),
                      const SizedBox(height: 4),
                      Text('添加 GitHub 仓库作为技能来源',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500)),
                    ],
                  ),
                );
              }
              return Column(
                children: sources
                    .map((s) {
                      final isOfficial = s == GitHubSkillSource.official;
                      final host = s.isGitee ? 'gitee.com' : 'github.com';
                      return ListTile(
                        leading: Icon(
                          s.isGitee ? Icons.cloud : Icons.code,
                          color: const Color(0xFF4F46E5),
                        ),
                        title: Text(s.name),
                        subtitle: Text('$host/${s.owner}/${s.repo}'),
                        trailing: isOfficial
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: Colors.grey),
                                onPressed: () async {
                                  final store = SkillSourceStore(
                                      ref.read(secureStorageProvider));
                                  await store.removeCustom(s.owner, s.repo);
                                  ref.invalidate(skillSourcesProvider);
                                },
                              ),
                      );
                    })
                    .toList(),
              );
            },
            loading: () => const Center(
                child: CircularProgressIndicator()),
            error: (_, __) => const ListTile(
              leading: Icon(Icons.error),
              title: Text('加载失败'),
            ),
          ),
          const Divider(height: 32),
          _SectionHeader(title: '添加 Gitee/GitHub 仓库'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '💡 在 Gitee 上找到想添加的技能仓库，复制地址栏中的 "用户名/仓库名" 两部分即可。\n'
                    '例如 gitee.com/ren02/skills → 用户名填 ren02，仓库名填 skills',
                    style: TextStyle(fontSize: 13, color: Colors.blueGrey, height: 1.5),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '来源名称',
                    hintText: '如：官方技能集 / 我的工具库',
                    helperText: '给这个来源起一个易记的名字',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ownerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Gitee 用户名/组织',
                    hintText: '如：ren02',
                    helperText: '仓库地址 gitee.com/【这部分】/仓库名',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _repoCtrl,
                  decoration: const InputDecoration(
                    labelText: '仓库名',
                    hintText: '如：skills',
                    helperText: '仓库地址 gitee.com/用户名/【这部分】',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _isValidating
                      ? null
                      : () async {
                          final owner = _ownerCtrl.text.trim();
                          final repo = _repoCtrl.text.trim();
                          final name = _nameCtrl.text.trim();
                          if (owner.isEmpty ||
                              repo.isEmpty ||
                              name.isEmpty) return;

                          setState(() => _isValidating = true);

                          // Validate by scanning the repo first
                          try {
                            final giteeToken = await ref.read(secureStorageProvider).read(key: 'gitee_token');
                            final loader = GitHubSkillLoader(giteeToken: giteeToken);
                            final result = await loader.scanRepo(
                                'https://gitee.com/$owner/$repo');
                            if (result.error != null) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('验证失败: ${result.error}'),
                                    backgroundColor: Colors.red,
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                                setState(() => _isValidating = false);
                              }
                              return;
                            }
                            final skillCount = result.skills.length;
                            if (skillCount == 0) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('该仓库未找到技能文件（SKILL.md 或 .yaml），请检查仓库结构'),
                                    backgroundColor: Colors.orange,
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                                setState(() => _isValidating = false);
                              }
                              return;
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('网络错误: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              setState(() => _isValidating = false);
                            }
                            return;
                          }

                          // Repo is valid — save the source
                          final source = SkillSource(
                            name: name,
                            owner: owner,
                            repo: repo,
                            isGitee: true,
                          );
                          final store = SkillSourceStore(
                              ref.read(secureStorageProvider));
                          await store.addCustom(source);
                          ref.invalidate(skillSourcesProvider);
                          ref.invalidate(marketSkillsProvider);

                          if (mounted) {
                            setState(() => _isValidating = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('已添加来源: $name\n'
                                    'gitee.com/$owner/$repo\n'
                                    '检测到技能文件，请到市场刷新查看'),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                            _ownerCtrl.clear();
                            _repoCtrl.clear();
                            _nameCtrl.clear();
                          }
                        },
                  icon: _isValidating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.add),
                  label: Text(_isValidating ? '正在验证仓库...' : '添加来源'),
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          _SectionHeader(title: '仓库结构要求'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '你的 GitHub 仓库需要包含:',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 8),
                _CodeBlock('''
my-skills/
├── catalog.json    # 技能索引
├── legal.yaml      # 技能定义
├── medical.yaml
└── finance.yaml'''),
                SizedBox(height: 12),
                Text(
                  'catalog.json 格式:',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 8),
                _CodeBlock('''[
  {
    "name": "技能名称",
    "version": "1.0.0",
    "author": "作者",
    "description": "描述",
    "icon": "🎯",
    "category": "分类",
    "tags": ["标签1", "标签2"],
    "file": "legal.yaml",
    "downloads": 0,
    "rating": 0.0
  }
]'''),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF4F46E5),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String code;
  const _CodeBlock(this.code);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        code,
        style: const TextStyle(
          color: Color(0xFFC3E88D),
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }
}
