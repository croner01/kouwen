import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers.dart';
import '../../services/github_service.dart';

/// Result returned when user selects content for analysis
class GitHubSelection {
  final String title;
  final String content;
  final String source; // e.g. "repo/file.dart" or "PR #42"

  const GitHubSelection({
    required this.title,
    required this.content,
    required this.source,
  });
}

/// Provider for GitHub connection status
final githubConnectedProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(githubServiceProvider);
  return service.isConnected();
});

/// Provider for repo list (Gitee-aware)
final reposProvider = FutureProvider.autoDispose
    .family<List<GitHubRepo>, bool>((ref, isGitee) async {
  final service = ref.watch(githubServiceProvider);
  return service.listRepos(isGitee: isGitee);
});

/// Provider for file list in a specific repo path (Gitee-aware)
final repoFilesProvider = FutureProvider.autoDispose
    .family<List<GitHubFile>, ({String repoPath, bool isGitee})>(
        (ref, params) async {
  final service = ref.watch(githubServiceProvider);
  final parts = params.repoPath.split('/');
  if (parts.length < 2) return [];
  final owner = parts[0];
  final repo = parts[1];
  final path = parts.length > 2 ? parts.sublist(2).join('/') : '';
  return service.listFiles(owner, repo,
      path: path, isGitee: params.isGitee);
});

/// Provider for file content (Gitee-aware)
final fileContentProvider = FutureProvider.autoDispose
    .family<String, ({String key, bool isGitee})>((ref, params) async {
  final service = ref.watch(githubServiceProvider);
  final parts = params.key.split('/');
  if (parts.length < 3) return '';
  final owner = parts[0];
  final repo = parts[1];
  final path = parts.sublist(2).join('/');
  return service.readFile(owner, repo, path, isGitee: params.isGitee);
});

/// Provider for PR list (GitHub only for now)
final prsProvider = FutureProvider.family
    .autoDispose<List<GitHubPr>, String>((ref, repoFull) async {
  final service = ref.watch(githubServiceProvider);
  final parts = repoFull.split('/');
  if (parts.length < 2) return [];
  return service.listPRs(parts[0], parts[1]);
});

class GitHubBrowserScreen extends ConsumerStatefulWidget {
  const GitHubBrowserScreen({super.key});

  @override
  ConsumerState<GitHubBrowserScreen> createState() =>
      _GitHubBrowserScreenState();
}

class _GitHubBrowserScreenState
    extends ConsumerState<GitHubBrowserScreen> {
  String? _selectedRepo; // "owner/repo"
  String? _currentPath; // "owner/repo/path"
  String? _selectedFile; // "owner/repo/path/file.dart"
  int _tabIndex = 0; // 0=Files, 1=PRs
  bool _isGitee = true; // Default to Gitee for Chinese users

  @override
  Widget build(BuildContext context) {
    // Check if connected; Gitee public repos don't need auth
    final connectedAsync = ref.watch(githubConnectedProvider);
    return connectedAsync.when(
      data: (connected) {
        if (!connected && !_isGitee) {
          return Scaffold(
            appBar: AppBar(title: const Text('浏览代码')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.link_off,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('未连接 Git 服务'),
                  const SizedBox(height: 8),
                  Text(
                    '请先在设置中连接，或切换到 Gitee 浏览公开仓库',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          );
        }
        return _buildBrowser();
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('浏览代码')),
        body:
            const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: const Text('浏览代码')),
        body: const Center(child: Text('连接检查失败')),
      ),
    );
  }

  Widget _buildBrowser() {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedRepo ?? (_isGitee ? 'Gitee 仓库' : 'GitHub 仓库')),
        leading: _selectedRepo != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (_selectedFile != null) {
                    setState(() => _selectedFile = null);
                  } else if (_currentPath != null &&
                      _currentPath != _selectedRepo) {
                    final parts = _currentPath!.split('/');
                    parts.removeLast();
                    setState(() => _currentPath = parts.join('/'));
                  } else {
                    setState(() {
                      _selectedRepo = null;
                      _currentPath = null;
                    });
                  }
                },
              )
            : null,
        actions: [
          // Gitee / GitHub toggle
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Gitee', style: TextStyle(fontSize: 12))),
              ButtonSegment(value: false, label: Text('GitHub', style: TextStyle(fontSize: 12))),
            ],
            selected: {_isGitee},
            onSelectionChanged: (v) {
              setState(() {
                _isGitee = v.first;
                _selectedRepo = null;
                _currentPath = null;
                _selectedFile = null;
              });
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _selectedFile != null
          ? _FileContentView(
              fileKey: _selectedFile!,
              isGitee: _isGitee,
              onSend: (title, content) {
                Navigator.of(context).pop(GitHubSelection(
                  title: title,
                  content: content,
                  source: _selectedFile!,
                ));
              },
            )
          : _selectedRepo != null
              ? Column(
                  children: [
                    // Tab bar: Files | PRs (PRs GitHub only)
                    Row(
                      children: [
                        _buildTab('文件', 0),
                        if (!_isGitee) _buildTab('PR', 1),
                      ],
                    ),
                    Expanded(
                      child: _tabIndex == 0
                          ? _FileList(
                              repoPath:
                                  _currentPath ?? _selectedRepo!,
                              isGitee: _isGitee,
                              onTap: (file) {
                                if (file.type == 'dir') {
                                  setState(() => _currentPath =
                                      file.path);
                                } else {
                                  setState(() => _selectedFile =
                                      '${_selectedRepo!}/${file.path}');
                                }
                              },
                            )
                          : _PRList(
                              repoFull: _selectedRepo!,
                              onTapPR: (pr) async {
                                final service = ref.read(
                                    githubServiceProvider);
                                final parts = _selectedRepo!
                                    .split('/');
                                final diff =
                                    await service.getPRDiff(
                                        parts[0], parts[1], pr.number);
                                if (mounted) {
                                  Navigator.of(context).pop(
                                    GitHubSelection(
                                      title:
                                          'PR #${pr.number}: ${pr.title}',
                                      content: diff,
                                      source:
                                          '$_selectedRepo#${pr.number}',
                                    ),
                                  );
                                }
                              },
                            ),
                    ),
                  ],
                )
              : _RepoList(
                  isGitee: _isGitee,
                  onTapRepo: (repo) {
                    setState(() {
                      _selectedRepo = repo.fullName;
                      _currentPath = repo.fullName;
                    });
                  },
                ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _tabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected
                    ? const Color(0xFF4F46E5)
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? const Color(0xFF4F46E5)
                  : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}

class _RepoList extends ConsumerWidget {
  final Function(GitHubRepo) onTapRepo;
  final bool isGitee;

  const _RepoList({required this.onTapRepo, required this.isGitee});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reposAsync = ref.watch(reposProvider(isGitee));
    return reposAsync.when(
      data: (repos) => ListView.builder(
        itemCount: repos.length,
        itemBuilder: (_, i) {
          final repo = repos[i];
          return ListTile(
            leading: Icon(
              repo.isPrivate ? Icons.lock : Icons.code,
              color: const Color(0xFF4F46E5),
            ),
            title: Text(repo.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              repo.description.isNotEmpty
                  ? repo.description
                  : repo.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade600),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (repo.language.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(repo.language,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700)),
                  ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right,
                    color: Colors.grey.shade400),
              ],
            ),
            onTap: () => onTapRepo(repo),
          );
        },
      ),
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text('加载失败: $e')),
    );
  }
}

class _FileList extends ConsumerWidget {
  final String repoPath;
  final Function(GitHubFile) onTap;
  final bool isGitee;

  const _FileList({required this.repoPath, required this.onTap, required this.isGitee});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(repoFilesProvider((repoPath: repoPath, isGitee: isGitee)));
    return filesAsync.when(
      data: (files) {
        // Separate dirs and files
        final dirs =
            files.where((f) => f.type == 'dir').toList();
        final regularFiles =
            files.where((f) => f.type == 'file').toList();

        return ListView(
          children: [
            // Breadcrumb
            if (repoPath.contains('/'))
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  repoPath,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontFamily: 'monospace'),
                ),
              ),
            ...dirs.map((d) => ListTile(
                  leading: const Icon(Icons.folder,
                      color: Colors.amber, size: 22),
                  title: Text(d.name,
                      style: const TextStyle(fontSize: 14)),
                  dense: true,
                  onTap: () => onTap(d),
                )),
            ...regularFiles.map((f) => ListTile(
                  leading: Icon(
                    _iconForFile(f.name),
                    size: 22,
                    color: Colors.grey.shade600,
                  ),
                  title: Text(f.name,
                      style: const TextStyle(fontSize: 14)),
                  dense: true,
                  onTap: () => onTap(f),
                )),
          ],
        );
      },
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text('加载失败: $e')),
    );
  }

  IconData _iconForFile(String name) {
    final ext = name.split('.').last;
    switch (ext) {
      case 'dart':
        return Icons.code;
      case 'yaml':
        return Icons.settings;
      case 'md':
        return Icons.article;
      case 'json':
        return Icons.data_object;
      default:
        return Icons.insert_drive_file;
    }
  }
}

class _FileContentView extends ConsumerWidget {
  final String fileKey;
  final bool isGitee;
  final Function(String title, String content) onSend;

  const _FileContentView(
      {required this.fileKey, required this.isGitee, required this.onSend});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentAsync = ref.watch(fileContentProvider((key: fileKey, isGitee: isGitee)));
    final fileName = fileKey.split('/').last;

    return contentAsync.when(
      data: (content) {
        final truncated = content.length > 15000
            ? '${content.substring(0, 15000)}\n\n... [内容已截断]'
            : content;

        return Column(
          children: [
            // File header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF1E293B),
              child: Row(
                children: [
                  const Icon(Icons.code,
                      color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(fileName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 14)),
                  ),
                  Text(
                    '${content.split('\n').length} 行',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            // Code content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Text(
                  truncated.substring(
                      0,
                      truncated.length > 5000
                          ? 5000
                          : truncated.length),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            // Send button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () =>
                      onSend(fileName, truncated),
                  icon: const Icon(Icons.send),
                  label: Text('发送「$fileName」分析'),
                  style: FilledButton.styleFrom(
                    minimumSize:
                        const Size(double.infinity, 48),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text('加载文件失败: $e')),
    );
  }
}

class _PRList extends ConsumerWidget {
  final String repoFull;
  final Function(GitHubPr) onTapPR;

  const _PRList({required this.repoFull, required this.onTapPR});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prsAsync = ref.watch(prsProvider(repoFull));
    return prsAsync.when(
      data: (prs) {
        if (prs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.merge_type,
                    size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text('没有打开的 PR',
                    style: TextStyle(
                        color: Colors.grey.shade600)),
              ],
            ),
          );
        }
        return ListView.builder(
          itemCount: prs.length,
          itemBuilder: (_, i) {
            final pr = prs[i];
            return ListTile(
              leading: Icon(
                pr.state == 'open'
                    ? Icons.call_merge
                    : Icons.merge_type,
                color: pr.state == 'open'
                    ? Colors.green
                    : Colors.purple,
              ),
              title: Text('#${pr.number} ${pr.title}',
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text('by ${pr.author}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600)),
              onTap: () => onTapPR(pr),
            );
          },
        );
      },
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text('加载 PR 失败: $e')),
    );
  }
}
