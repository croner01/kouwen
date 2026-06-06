import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme_provider.dart';
import '../../../providers.dart';
import 'providers/model_config_provider.dart';
import 'model_config_edit_screen.dart';
import 'github_connect_screen.dart';
import 'skill_sources_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configsAsync = ref.watch(modelConfigsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _SectionHeader(title: '模型配置'),
          configsAsync.when(
            data: (configs) {
              if (configs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.api,
                          size: 48,
                          color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Text(
                        '还没有配置模型',
                        style: TextStyle(
                            color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '添加 DeepSeek、通义千问等模型的 API Key',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children: configs
                    .map((config) => ListTile(
                          leading: IconButton(
                            icon: Icon(
                              config.isDefault
                                  ? Icons.star
                                  : Icons.star_border,
                              color: config.isDefault
                                  ? Colors.amber
                                  : Colors.grey,
                            ),
                            tooltip: config.isDefault
                                ? '当前默认'
                                : '设为默认',
                            onPressed: config.isDefault
                                ? null
                                : () async {
                                    await ref
                                        .read(modelManagerProvider)
                                        .setDefault(config.id);
                                    ref.invalidate(
                                        modelConfigsProvider);
                                  },
                          ),
                          title: Text(config.alias),
                          subtitle: Text(
                              '${config.modelName}\n${config.apiUrl}'),
                          isThreeLine: true,
                          onTap: () async {
                            // Navigate to edit screen
                            final apiKey = await ref
                                .read(modelManagerProvider)
                                .getApiKey(config.id);
                            if (!context.mounted) return;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ModelConfigEditScreen(
                                  config: config,
                                  existingApiKey: apiKey,
                                ),
                              ),
                            ).then((_) =>
                                ref.invalidate(
                                    modelConfigsProvider));
                          },
                          onLongPress: () {
                            showDialog(
                              context: context,
                              builder: (_) =>
                                  AlertDialog(
                                title:
                                    Text(config.alias),
                                content: const Text(
                                    '删除此模型配置？'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(
                                            context),
                                    child: const Text(
                                        '取消'),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      await ref
                                          .read(modelConfigFormProvider
                                              .notifier)
                                          .deleteConfig(config.id);
                                      ref.invalidate(modelConfigsProvider);
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    },
                                    child: const Text(
                                        '删除',
                                        style: TextStyle(
                                            color:
                                                Colors.red)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ))
                    .toList(),
              );
            },
            loading: () => const Center(
                child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) =>
                          const ModelConfigEditScreen()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('添加模型'),
            ),
          ),
          const Divider(height: 32),
          _SectionHeader(title: '技能市场'),
          ListTile(
            leading:
                const Icon(Icons.source, color: Color(0xFF4F46E5)),
            title: const Text('技能来源'),
            subtitle: const Text('管理 Gitee/GitHub 技能仓库'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) =>
                        const SkillSourcesScreen()),
              );
            },
          ),
          const Divider(height: 32),
          _SectionHeader(title: '联网搜索'),
          _WebSearchInfoTile(),
          const Divider(height: 32),
          const Divider(height: 32),
          _SectionHeader(title: 'Git 服务'),
          Consumer(
            builder: (context, ref, _) {
              final statusAsync = ref.watch(githubStatusProvider);
              return statusAsync.when(
                data: (status) {
                  final connected =
                      status != null && status.connected;
                  return ListTile(
                    leading: Icon(
                      connected
                          ? Icons.check_circle
                          : Icons.link_off,
                      color: connected ? Colors.green : Colors.grey,
                    ),
                    title: Text(connected
                        ? '已连接: ${status.username}'
                        : '未连接'),
                    subtitle: const Text('浏览 Gitee/GitHub 仓库、审查 PR'),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const GitHubConnectScreen()),
                      );
                    },
                  );
                },
                loading: () => const ListTile(
                  leading: CircularProgressIndicator(),
                  title: Text('加载中...'),
                ),
                error: (_, __) => ListTile(
                  leading: const Icon(Icons.link_off),
                  title: const Text('未连接'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) =>
                              const GitHubConnectScreen()),
                    );
                  },
                ),
              );
            },
          ),
          const Divider(height: 32),
          _SectionHeader(title: '外观'),
          Consumer(
            builder: (context, ref, _) {
              final themeMode = ref.watch(themeModeProvider);
              final isDark = themeMode == ThemeMode.dark;
              return SwitchListTile(
                title: const Text('深色模式'),
                subtitle: Text(isDark ? '已开启深色主题' : '已关闭深色主题'),
                value: isDark,
                onChanged: (_) {
                  ref.read(themeModeProvider.notifier).toggle();
                },
                secondary: Icon(
                  isDark ? Icons.dark_mode : Icons.light_mode,
                  color: isDark ? Colors.amber : Colors.grey,
                ),
              );
            },
          ),
          const Divider(height: 32),
          _SectionHeader(title: '关于'),
          const ListTile(
            title: Text('叩问'),
            subtitle: Text('版本 0.1.0'),
            leading: Icon(Icons.info_outline),
          ),
          const ListTile(
            title: Text('开源协议'),
            subtitle: Text('MIT License'),
            leading: Icon(Icons.gavel_outlined),
          ),
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

class _WebSearchInfoTile extends StatelessWidget {
  const _WebSearchInfoTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.language, color: Color(0xFF4F46E5)),
      title: const Text('联网搜索'),
      subtitle: const Text('模型原生搜索 / Jina Reader 兜底，无需额外配置'),
      onTap: () => _showSearchInfo(context),
    );
  }
}

void _showSearchInfo(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('联网搜索'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('1. 模型原生搜索（推荐）'),
          SizedBox(height: 4),
          Text(
            'DeepSeek、通义千问、Kimi 等模型自带联网搜索能力。'
            '在对话中开启搜索开关即可，无需额外配置。',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          SizedBox(height: 16),
          Text('2. 客户端搜索（兜底）'),
          SizedBox(height: 4),
          Text(
            '对于不支持原生搜索的模型，叩问使用 Jina Reader '
            '搜索网页并抓取全文，注入对话供模型参考。'
            '无需任何 API Key，开箱即用。',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          SizedBox(height: 16),
          Text('3. 智能触发'),
          SizedBox(height: 4),
          Text(
            '包含"最新""今天""新闻""价格""股票""年份"等'
            '关键词时自动开启搜索，也可手动切换 🌐 按钮。',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}
