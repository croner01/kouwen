import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers.dart';

final githubStatusProvider = FutureProvider<GitHubStatus?>((ref) async {
  final service = ref.watch(githubServiceProvider);
  final connected = await service.isConnected();
  if (!connected) return null;
  final username = await service.getUsername() ?? '已连接';
  return GitHubStatus(connected: true, username: username);
});

class GitHubStatus {
  final bool connected;
  final String? username;
  const GitHubStatus({required this.connected, this.username});
}

class GitHubConnectScreen extends ConsumerStatefulWidget {
  const GitHubConnectScreen({super.key});

  @override
  ConsumerState<GitHubConnectScreen> createState() =>
      _GitHubConnectScreenState();
}

class _GitHubConnectScreenState extends ConsumerState<GitHubConnectScreen>
    with SingleTickerProviderStateMixin {
  final _githubTokenCtrl = TextEditingController();
  final _giteeTokenCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _githubTokenCtrl.dispose();
    _giteeTokenCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _connectGitHub() async {
    final token = _githubTokenCtrl.text.trim();
    if (token.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final service = ref.read(githubServiceProvider);
      // Validate first, then save — avoids persisting invalid tokens
      final dio = Dio(BaseOptions(headers: {'Authorization': 'Bearer $token'}));
      final resp = await dio.get('https://api.github.com/user');
      final username = resp.data['login'] as String?;
      if (username == null) throw Exception('Token 无效');
      await service.saveToken(token);
      if (mounted) {
        ref.invalidate(githubStatusProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('已连接 GitHub: $username'),
              backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('连接失败: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _connectGitee() async {
    final token = _giteeTokenCtrl.text.trim();
    if (token.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      // Save first so getGiteeToken() can read it during validation
      final storage = ref.read(secureStorageProvider);
      await storage.write(key: 'gitee_token', value: token);

      // Validate the token via a direct Gitee API call
      // (not getUsername which would return GitHub username if both are connected)
      final service = ref.read(githubServiceProvider);
      final username = await service.validateGiteeToken(token);
      if (username == null) throw Exception('Token 无效，请检查私人令牌是否正确');

      if (mounted) {
        ref.invalidate(githubStatusProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('已连接 Gitee: $username'),
              backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      // Remove invalid token
      await ref.read(secureStorageProvider).delete('gitee_token');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('连接失败: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接 Git 服务'),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: const Color(0xFF4F46E5),
          tabs: const [
            Tab(text: 'Gitee'),
            Tab(text: 'GitHub'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // ---- Gitee Tab ----
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Icon(Icons.cloud, size: 56, color: Color(0xFFC71D23)),
                const SizedBox(height: 12),
                const Text(
                  '连接 Gitee 账户',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Gitee 是国内代码托管平台，无需 Token 即可浏览公开仓库。\nToken 用于访问私有仓库和提高 API 频率限制。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _giteeTokenCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Gitee 私人令牌',
                    hintText: '在 Gitee 设置 → 私人令牌 中生成',
                    helperText: '公开仓库无需填写此项',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _connectGitee,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: const Text('保存 Gitee Token'),
                ),
              ],
            ),
          ),
          // ---- GitHub Tab ----
          Form(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Icon(Icons.code, size: 56, color: Color(0xFF4F46E5)),
                const SizedBox(height: 12),
                const Text(
                  '连接 GitHub 账户',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  '连接后可浏览私有仓库、审查 PR、分析 Issue',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _githubTokenCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Personal Access Token',
                    hintText: 'ghp_xxxxxxxxxxxxxxxxxxxx',
                    helperText: '在 GitHub Settings → Developer settings 创建',
                  ),
                  obscureText: true,
                  validator: (v) {
                    if (v != null && v.trim().isNotEmpty) {
                      if (!v.trim().startsWith('ghp_') &&
                          !v.trim().startsWith('github_pat_')) {
                        return 'Token 格式应为 ghp_ 或 github_pat_ 开头';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '需要权限: repo (私有仓库访问)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _connectGitHub,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: const Text('连接 GitHub'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
