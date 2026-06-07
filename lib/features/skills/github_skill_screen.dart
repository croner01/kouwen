import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/github_skill_loader.dart';
import 'providers/skill_provider.dart';
import 'skill_market_screen.dart' show marketSkillsProvider;
import '../../../providers.dart';
import 'providers/install_provider.dart';

class GitHubSkillScreen extends ConsumerStatefulWidget {
  const GitHubSkillScreen({super.key});

  @override
  ConsumerState<GitHubSkillScreen> createState() =>
      _GitHubSkillScreenState();
}

class _GitHubSkillScreenState
    extends ConsumerState<GitHubSkillScreen> {
  final _urlCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _resultKey = GlobalKey();
  GitHubScanResult? _result;
  bool _isLoading = false;
  String? _error;

  /// Extract "owner/repo" from a URL like https://gitee.com/ren02/skills
  static String _extractRepoPath(String url) {
    final trimmed = url.trim();
    // If it's already in owner/repo format, return as-is
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://') &&
        trimmed.contains('/') && !trimmed.contains(' ')) {
      return trimmed.split('/').take(2).join('/');
    }
    // Parse full URL
    try {
      final uri = Uri.parse(trimmed);
      return uri.pathSegments.where((s) => s.isNotEmpty).take(2).join('/');
    } catch (_) {
      return trimmed;
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final input = _urlCtrl.text.trim();
    if (input.isEmpty) return;

    // Debug: show exactly what's being scanned (visible in UI)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('扫描: "$input"'),
        duration: const Duration(seconds: 2),
      ));
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final token = await ref.read(secureStorageProvider).getGitHubToken();
      final giteeToken = await ref.read(secureStorageProvider).read(key: 'gitee_token');
      final loader = GitHubSkillLoader(token: token, giteeToken: giteeToken);
      final result = await loader.scanRepo(input);
      setState(() {
        _result = result;
        _error = result.error;
        _isLoading = false;
      });
      // Auto-scroll to results
      if (result.skills.isNotEmpty && mounted) {
        Future.delayed(const Duration(milliseconds: 100), () {
          _scrollToResults();
        });
      }
    } catch (e) {
      setState(() {
        _error = '扫描失败: $e';
        _isLoading = false;
      });
    }
  }

  String _skillDisplayName(String path) {
    final parts = path.split('/');
    if (parts.length >= 2) {
      return parts[parts.length - 2].replaceAll('-', ' ').replaceAll('_', ' ');
    }
    return parts.last.replaceAll('.md', '').replaceAll('.yaml', '').replaceAll('.yml', '');
  }

  Future<void> _installAll() async {
    if (_result == null || _result!.skills.isEmpty) return;
    final installState = ref.read(installerProvider);
    if (installState.isInstalling) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在后台安装中，请稍候'), duration: Duration(seconds: 1)),
      );
      return;
    }

    final token = await ref.read(secureStorageProvider).getGitHubToken();
    final giteeToken = await ref.read(secureStorageProvider).read(key: 'gitee_token');
    ref.read(installerProvider.notifier).installAll(
      _result!,
      gitHubToken: token,
      giteeToken: giteeToken,
    );
  }

  void _scrollToResults() {
    final context = _resultKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(context,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut);
    }
  }

  Future<void> _install(GitHubSkillResult skill) async {
    if (_isLoading) return;
    // If the repo is a collection, install the whole thing
    if (_result?.isCollection == true) {
      await _installAll();
      return;
    }

    final repoUrl = _extractRepoPath(_urlCtrl.text.trim());
    if (repoUrl.isEmpty) return;

    try {
      setState(() => _isLoading = true);
      final api = ref.read(skillApiServiceProvider);
      await api.installSkill(repoUrl);

      ref.invalidate(installedSkillsProvider);
      ref.invalidate(topLevelSkillsProvider);
      ref.invalidate(marketSkillsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${skill.name} 安装成功'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '安装失败: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('从 Gitee/GitHub 加载技能')),
      body: ListView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(16),
        children: [
          // Input area
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '💡 直接输入 "用户名/仓库名" 默认走 Gitee（无需 Token）\n'
              '输入完整 GitHub URL 才需要先在设置中连接 GitHub Token',
              style: TextStyle(fontSize: 13, color: Colors.blueGrey, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlCtrl,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.text,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(
                        RegExp(r'[\s  -‏ - ]')),
                  ],
                  decoration: InputDecoration(
                    hintText: '输入仓库地址: ren02/skills',
                    hintStyle: TextStyle(
                        color: Colors.grey.shade400, fontSize: 14),
                  ),
                  onSubmitted: (_) => _scan(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _isLoading ? null : _scan,
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('扫描'),
              ),
            ],
          ),
          // Scan status
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Text('正在扫描仓库...', style: TextStyle(fontSize: 14)),
                ],
              ),
            ),

          // Scan result banner
          if (!_isLoading && _result != null) ...[
            const SizedBox(height: 12),
            if (_result!.isCollection && _result!.collection != null) ...[
              // Collection banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.folder_special, size: 22, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '技能集合 · ${_result!.collection!.name}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF4F46E5)),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_result!.skills.length} 子技能',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF4F46E5)),
                          ),
                        ),
                      ],
                    ),
                    if (_result!.collection!.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _result!.collection!.description,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
            ] else ...[
              // Flat skills banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _error != null
                      ? Colors.orange.shade50
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _error != null ? Icons.error_outline : Icons.check_circle,
                      size: 20,
                      color: _error != null
                          ? Colors.orange.shade700
                          : Colors.green.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error ?? '${_result!.repoName} — ${_result!.skills.length} 个技能，点击安装',
                        style: TextStyle(
                          fontSize: 13,
                          color: _error != null
                              ? Colors.orange.shade900
                              : Colors.green.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],

          // ── Background install progress ──
          Consumer(builder: (context, ref, _) {
            final installState = ref.watch(installerProvider);
            if (installState.status == InstallStatus.idle) {
              return const SizedBox.shrink();
            }
            if (installState.status == InstallStatus.completed) {
              // Completion state with retry option
              final msg = installState.resultMessage ?? '安装完成';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Card(
                  color: installState.hasFailed ? Colors.orange.shade50 : Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(
                            installState.hasFailed ? Icons.warning_amber_rounded : Icons.check_circle,
                            size: 20,
                            color: installState.hasFailed ? Colors.orange.shade700 : Colors.green.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(msg, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                        ]),
                        if (installState.hasFailed) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => ref.read(installerProvider.notifier).retryFailed(),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: Text('重试 ${installState.failedSkills.length} 个失败'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange.shade800,
                                side: BorderSide(color: Colors.orange.shade300),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Card(
                color: Colors.indigo.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(
                          '正在安装: ${installState.currentSkillName ?? "..."}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        )),
                      ]),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: installState.total > 0
                            ? installState.current / installState.total
                            : null,
                        backgroundColor: Colors.indigo.shade100,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${installState.current}/${installState.total} · '
                        '${installState.successCount}成功 ${installState.failCount}失败',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 12),

          // Recommended sources
          Text(
            '推荐来源（点击自动扫描）',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          _SectionLabel('🩺 家庭医生'),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _SourceCard(label: '医疗AI工具集', repo: 'ren02/awesome-medical-ai-skills-cn', desc: '家庭医生Skill·中文', onTap: () { _urlCtrl.text = 'https://gitee.com/ren02/awesome-medical-ai-skills-cn'; _scan(); }),
          ]),
          const SizedBox(height: 12),
          _SectionLabel('⚖️ 律师'),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _SourceCard(label: '合同审查', repo: 'ren02/claude-legal-skill', desc: 'CUAD风险检测·红线批注', onTap: () { _urlCtrl.text = 'https://gitee.com/ren02/claude-legal-skill'; _scan(); }),
            _SourceCard(label: 'AI法律助手', repo: 'ren02/ai-legal-claude', desc: '14个Skill·并行Agent', onTap: () { _urlCtrl.text = 'https://gitee.com/ren02/ai-legal-claude'; _scan(); }),
            _SourceCard(label: '法律套件', repo: 'ren02/claude-for-legal', desc: '12个实践领域·70+Agent', onTap: () { _urlCtrl.text = 'https://gitee.com/ren02/claude-for-legal'; _scan(); }),
          ]),
          const SizedBox(height: 12),
          _SectionLabel('📚 中小学老师'),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _SourceCard(label: '教育技能库', repo: 'ren02/education-agent-skills', desc: '152个教学法Skill', onTap: () { _urlCtrl.text = 'https://gitee.com/ren02/education-agent-skills'; _scan(); }),
          ]),
          const SizedBox(height: 12),
          _SectionLabel('🖥️ 运维工程师'),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _SourceCard(label: 'DevOps工具箱', repo: 'ren02/claude-skills', desc: '32个Skill·DevOps·SecOps', onTap: () { _urlCtrl.text = 'https://gitee.com/ren02/claude-skills'; _scan(); }),
          ]),
          const SizedBox(height: 12),
          _SectionLabel('🌐 通用'),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _SourceCard(label: 'Anthropic 官方', repo: 'ren02/skills', desc: '17个官方Skill', onTap: () { _urlCtrl.text = 'https://gitee.com/ren02/skills'; _scan(); }),
            _SourceCard(label: 'AI SkillStore', repo: 'ren02/marketplace', desc: '安全审计·一键安装', onTap: () { _urlCtrl.text = 'https://gitee.com/ren02/marketplace'; _scan(); }),
            _SourceCard(label: '交易策略库', repo: 'ren02/claude-trading-skills', desc: '50+量化交易Skill', onTap: () { _urlCtrl.text = 'https://gitee.com/ren02/claude-trading-skills'; _scan(); }),
          ]),

          const SizedBox(height: 24),

          // Results list
          if (_result != null && _result!.skills.isNotEmpty) ...[
            Container(key: _resultKey),
            const SizedBox(height: 12),
            // Install button
            Consumer(builder: (context, ref, _) {
              final installState = ref.watch(installerProvider);
              final isInstalling = installState.isInstalling;
              if (_result!.isCollection) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FilledButton.icon(
                    onPressed: (isInstalling || _isLoading) ? null : () => _installAll(),
                    icon: Icon(isInstalling ? Icons.hourglass_top : Icons.download, size: 18),
                    label: Text(isInstalling
                        ? '安装中 (${installState.current}/${installState.total})'
                        : '安装全部 (${_result!.skills.length} 个子技能)'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                );
              }
              return Card(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.05),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.folder, color: Color(0xFF4F46E5)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_result!.repoName,
                                style: const TextStyle(fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                            Text('${_result!.skills.length} 个技能',
                                style: TextStyle(fontSize: 13,
                                    color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: (isInstalling || _isLoading) ? null : () => _installAll(),
                        icon: Icon(isInstalling ? Icons.hourglass_top : Icons.download, size: 18),
                        label: Text(isInstalling
                            ? '${installState.current}/${installState.total}'
                            : '安装全部'),
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8)),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 6),
            // Skill list — always show for flat; for collections show collapsed preview
            if (!_result!.isCollection)
              ...(_result!.skills.map((skill) {
                final name = _skillDisplayName(skill.path);
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.article, size: 18,
                      color: Color(0xFF4F46E5)),
                  title: Text(name, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(skill.path,
                      style: TextStyle(fontSize: 11,
                          color: Colors.grey.shade400,
                          fontFamily: 'monospace')),
                  trailing: TextButton(
                    onPressed: () => _install(skill),
                    child: const Text('安装', style: TextStyle(fontSize: 13)),
                  ),
                );
              }))
            else
              // Collection: show expandable child preview
              _ChildSkillPreview(
                skills: _result!.skills,
                displayName: _skillDisplayName,
              ),
          ],

          // Explanation
          if (_result == null && _error == null) ...[
            const SizedBox(height: 32),
            ExpansionTile(
              title: const Text('什么样的仓库可以加载？',
                  style: TextStyle(fontSize: 14)),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bullet('仓库包含 .yaml /.yml 文件'),
                      _bullet('每个 YAML 需包含 name、system_prompt 等字段'),
                      _bullet('支持任何公开仓库'),
                      _bullet('自动过滤 pubspec.yaml 等配置文件'),
                      const SizedBox(height: 8),
                      Text(
                        '这与 Claude Code Skills 的格式兼容，社区 Skill 可以直接安装使用。',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Color(0xFF4F46E5))),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13, height: 1.5))),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text(label,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600)),
    );
  }
}

class _ChildSkillPreview extends StatefulWidget {
  final List<GitHubSkillResult> skills;
  final String Function(String path) displayName;

  const _ChildSkillPreview({
    required this.skills,
    required this.displayName,
  });

  @override
  State<_ChildSkillPreview> createState() => _ChildSkillPreviewState();
}

class _ChildSkillPreviewState extends State<_ChildSkillPreview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final preview = _expanded
        ? widget.skills
        : widget.skills.take(5).toList();
    final hidden = widget.skills.length - preview.length;

    return Column(
      children: [
        ...preview.map((skill) => ListTile(
              dense: true,
              leading: const Icon(Icons.article_outlined, size: 16,
                  color: Colors.grey),
              title: Text(
                widget.displayName(skill.path),
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(skill.path,
                  style: TextStyle(fontSize: 10,
                      color: Colors.grey.shade400,
                      fontFamily: 'monospace')),
            )),
        if (hidden > 0)
          TextButton(
            onPressed: () => setState(() => _expanded = true),
            child: Text('展开全部 $hidden 个...',
                style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  final String label;
  final String repo;
  final String desc;
  final VoidCallback onTap;

  const _SourceCard({
    required this.label,
    required this.repo,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: (MediaQuery.of(context).size.width - 48) / 2 - 4,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF4F46E5).withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(repo,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontFamily: 'monospace')),
            const SizedBox(height: 2),
            Text(desc,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }
}

