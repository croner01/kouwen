import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models.dart';
import '../../engine/skill_parser.dart';
import '../../engine/skill_intro.dart';
import '../../data/repositories.dart';
import '../../../providers.dart';
import '../skills/providers/skill_provider.dart';
import 'providers/chat_provider.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/chat_input_bar.dart';
import 'github_browser_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String? conversationId;
  final String? autoLoadSkillId;
  final String? initialMessage;

  const ChatScreen({super.key, this.conversationId, this.autoLoadSkillId, this.initialMessage});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  bool _initialized = false;
  final _chineseNameCache = <String, String>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        final notifier = ref.read(chatProvider.notifier);
        if (widget.conversationId != null) {
          await notifier.loadConversation(widget.conversationId!);
        } else {
          await notifier.createConversation();
          if (widget.autoLoadSkillId != null) {
            await notifier.loadSkill(widget.autoLoadSkillId!);
          }
        }
      } catch (e) {
        // Final safety net — should not reach here if loadConversation handles its own errors
        // ignore: avoid_print
        print('ChatScreen initState error: $e');
      }
      setState(() => _initialized = true);

      // Auto-send initial message if provided
      if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
        try {
          await ref.read(chatProvider.notifier).sendMessage(widget.initialMessage!);
        } catch (e) {
          // ignore: avoid_print
          print('ChatScreen auto-send error: $e');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    if (!_initialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('叩问')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.skill != null) ...[
              Text(state.skill!.icon,
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  // Cache the chinese name so SkillIntroBuilder.build isn't
                  // called on every frame — the result depends only on skill data
                  // which rarely changes mid-conversation.
                  _chineseNameCache.putIfAbsent(
                    state.skill!.name,
                    () => SkillIntroBuilder.build(
                      rawName: state.skill!.name,
                      parsed: state.skill,
                    ).chineseName,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else
              const Text('叩问'),
          ],
        ),
        actions: [
          // GitHub browser button
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: '浏览 Gitee/GitHub 仓库',
            onPressed: () async {
              final result = await Navigator.of(context).push<GitHubSelection>(
                MaterialPageRoute(
                    builder: (_) => const GitHubBrowserScreen()),
              );
              if (result != null) {
                ref.read(chatProvider.notifier).sendMessage(
                  '请分析以下来自 GitHub 的内容：\n\n来源: ${result.source}\n\n${result.content}',
                );
              }
            },
          ),
          // Skill picker
          _SkillPicker(
            currentSkill: state.skill,
            onSkillSelected: (skillId) async {
              final notifier = ref.read(chatProvider.notifier);
              final msgCount = state.messages.length;

              // Silent switch for short conversations
              if (msgCount <= 6) {
                notifier.loadSkill(skillId);
                return;
              }

              // Long conversation — confirm with user
              final keepHistory = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('切换技能'),
                  content: Text('当前对话有 $msgCount 条消息，选择如何处理对话历史？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('清空重新开始'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('保留对话继续'),
                    ),
                  ],
                ),
              );

              // null (dismiss) defaults to keep history
              if (keepHistory ?? true) {
                notifier.loadSkill(skillId);
              } else {
                await notifier.newConversation();
                notifier.loadSkill(skillId);
              }
            },
            onSkillUnloaded: () {
              ref.read(chatProvider.notifier).unloadSkill();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () {
              if (state.messages.isEmpty) {
                // Already empty — just start fresh
                ref.read(chatProvider.notifier).newConversation();
                return;
              }
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('开始新对话'),
                  content: const Text('当前对话将被保留在对话列表中，确定开始新对话？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        ref.read(chatProvider.notifier).newConversation();
                      },
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            },
            tooltip: '新对话',
          ),
        ],
      ),
      body: Column(
        children: [
          // Skill suggestion list — persistent, shows all matches
          if (state.suggestedSkills.isNotEmpty && state.skill == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              color:
                  const Color(0xFF4F46E5).withValues(alpha: 0.04),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 14,
                          color: Color(0xFF4F46E5)),
                      const SizedBox(width: 4),
                      Text(
                        '根据你的问题，推荐以下技能：',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => ref
                            .read(chatProvider.notifier)
                            .clearSuggestion(),
                        child: Icon(Icons.close, size: 16,
                            color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: state.suggestedSkills.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 6),
                      itemBuilder: (_, i) {
                        final m = state.suggestedSkills[i];
                        return ActionChip(
                          avatar: const Icon(Icons.bolt,
                              size: 14, color: Color(0xFF4F46E5)),
                          label: Text(
                            m.intro.chineseName,
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () async {
                            final notifier = ref.read(chatProvider.notifier);
                            await notifier.loadSkill(m.skill.id);
                          },
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          if (state.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              color: Colors.orange.shade50,
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.error!,
                      style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 13),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      ref
                          .read(chatProvider.notifier)
                          .clearError();
                    },
                    child: Icon(Icons.close,
                        size: 18,
                        color: Colors.orange.shade700),
                  ),
                ],
              ),
            ),
          Expanded(
            child: state.messages.isEmpty
                ? _WelcomeView(
                    skill: state.skill,
                    state: state,
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8),
                    itemCount: state.messages.length +
                        (state.isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index < state.messages.length) {
                        return ChatBubble(
                          message: state.messages[index],
                          skillIcon: state.skill?.icon,
                        );
                      }
                      if (state.streamingContent.isNotEmpty) {
                        return ChatBubble(
                          message: Message(
                            id: 'streaming',
                            conversationId: '',
                            role: MessageRole.assistant,
                            content: state.streamingContent,
                            createdAt: DateTime.now(),
                          ),
                          skillIcon: state.skill?.icon,
                        );
                      }
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                            child: CircularProgressIndicator()),
                      );
                    },
                  ),
          ),
          ChatInputBar(
            webSearchEnabled: state.webSearchEnabled,
            onToggleWebSearch: () {
              ref.read(chatProvider.notifier).toggleWebSearch();
            },
            onSend: (text, attachments) {
              ref.read(chatProvider.notifier).sendMessage(
                    text,
                    attachments: attachments,
                  );
            },
          ),
        ],
      ),
    );
  }
}

class _WelcomeView extends ConsumerWidget {
  final ParsedSkill? skill;
  final ChatState state;
  const _WelcomeView({required this.skill, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      children: [
        Center(
          child: Column(
            children: [
              if (skill == null)
                ClipOval(
                  child: Image.asset(
                    'assets/icon/chat_avatar.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Text(skill!.icon,
                    style: const TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text(
                skill?.name ?? '叩问',
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                skill?.welcomeMessage ??
                    '选择一个技能获取专业分析，或直接开始对话。\n'
                    '点击右上角 🧩 图标加载技能。',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        if (skill == null) ...[
          const SizedBox(height: 32),
          Text(
            '\u{1F4A1} 也可以直接开始',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Text(
            '不加载技能也可以自由对话，叩问是通用的 AI 助手',
            style: TextStyle(
                fontSize: 13, color: Colors.grey.shade500),
          ),
        ] else if (skill!.sampleQuestions.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text(
            '\u{1F4A1} 试试这些问题',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          ...skill!.sampleQuestions.map((q) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () {
                    ref
                        .read(chatProvider.notifier)
                        .sendMessage(q, attachments: []);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(q,
                              style: const TextStyle(
                                  fontSize: 14, height: 1.4)),
                        ),
                        Icon(Icons.arrow_forward_ios,
                            size: 14,
                            color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
              )),
        ],
      ],
    );
  }
}

/// Skill picker dropdown in the app bar
class _SkillPicker extends ConsumerWidget {
  final ParsedSkill? currentSkill;
  final Function(String) onSkillSelected;
  final VoidCallback onSkillUnloaded;

  const _SkillPicker({
    required this.currentSkill,
    required this.onSkillSelected,
    required this.onSkillUnloaded,
  });

  void _showPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SkillPickerSheet(
        currentSkill: currentSkill,
        onSkillSelected: onSkillSelected,
        onSkillUnloaded: onSkillUnloaded,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: Icon(
        Icons.extension,
        color: currentSkill != null
            ? const Color(0xFF4F46E5)
            : null,
      ),
      tooltip: '加载技能',
      onPressed: () => _showPicker(context, ref),
    );
  }
}

/// Bottom sheet with searchable hierarchical skill picker
class _SkillPickerSheet extends ConsumerStatefulWidget {
  final ParsedSkill? currentSkill;
  final Function(String) onSkillSelected;
  final VoidCallback onSkillUnloaded;

  const _SkillPickerSheet({
    required this.currentSkill,
    required this.onSkillSelected,
    required this.onSkillUnloaded,
  });

  @override
  ConsumerState<_SkillPickerSheet> createState() => _SkillPickerSheetState();
}

class _SkillPickerSheetState extends ConsumerState<_SkillPickerSheet> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topAsync = ref.watch(topLevelSkillsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) {
        return Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title + current skill
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const Text('选择技能',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (widget.currentSkill != null)
                    TextButton.icon(
                      onPressed: () {
                        widget.onSkillUnloaded();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.close, size: 16, color: Colors.red),
                      label: const Text('卸载', style: TextStyle(color: Colors.red, fontSize: 13)),
                    ),
                ],
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: '搜索技能...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            // List
            Expanded(
              child: topAsync.when(
                data: (topSkills) {
                  final filtered = _query.isEmpty
                      ? topSkills
                      : topSkills.where((s) {
                          final cn = SkillIntroBuilder.build(rawName: s.name).chineseName;
                          return s.name.toLowerCase().contains(_query.toLowerCase()) ||
                              cn.contains(_query) ||
                              (s.description?.contains(_query) ?? false);
                        }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 40, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text('未找到 "$_query"',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.only(bottom: 32),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _SkillPickerTile(
                      skill: filtered[i],
                      query: _query,
                      onSelected: (skillId) {
                        widget.onSkillSelected(skillId);
                        Navigator.pop(context);
                      },
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('加载失败: $e')),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A single tile in the skill picker — shows collection expandable or standalone
class _SkillPickerTile extends ConsumerStatefulWidget {
  final Skill skill;
  final String query;
  final Function(String) onSelected;

  const _SkillPickerTile({
    required this.skill,
    required this.query,
    required this.onSelected,
  });

  @override
  ConsumerState<_SkillPickerTile> createState() => _SkillPickerTileState();
}

class _SkillPickerTileState extends ConsumerState<_SkillPickerTile> {
  bool _expanded = false;
  List<Skill>? _children;

  Future<void> _toggle() async {
    if (_expanded) { setState(() => _expanded = false); return; }
    setState(() => _expanded = true);
    if (!context.mounted) return;
    final repo = SkillRepository(ref.read(dbProvider));
    final children = await repo.getChildSkills(widget.skill.id);
    if (mounted) setState(() => _children = children);
  }

  @override
  Widget build(BuildContext context) {
    final intro = SkillIntroBuilder.build(rawName: widget.skill.name);

    if (!widget.skill.isCollection) {
      return ListTile(
        leading: _skillIcon(intro.chineseName),
        title: Text(intro.chineseName, style: const TextStyle(fontSize: 14)),
        subtitle: widget.skill.name != intro.chineseName
            ? Text(widget.skill.name,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400))
            : null,
        onTap: () => widget.onSelected(widget.skill.id),
      );
    }

    // Collection — expandable
    final cn = intro.chineseName;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.folder_special, color: Color(0xFF4F46E5), size: 22),
          title: Text(cn, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: widget.skill.description != null && widget.skill.description!.isNotEmpty
              ? Text(widget.skill.description!, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500))
              : null,
          trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          onTap: _toggle,
        ),
        if (_expanded) ...[
          if (_children == null)
            const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
          else if (_children!.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 56, bottom: 8),
              child: Text('暂无子技能', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            )
          else
            ...(_children!.where((c) {
              if (widget.query.isEmpty) return true;
              final cIntro = SkillIntroBuilder.build(rawName: c.name);
              final short = c.name.split('/').last.toLowerCase();
              return short.contains(widget.query.toLowerCase()) ||
                  cIntro.chineseName.contains(widget.query);
            }).map((c) {
              final cIntro = SkillIntroBuilder.build(rawName: c.name);
              final short = c.name.split('/').last;
              return ListTile(
                leading: _skillIcon(cIntro.chineseName),
                title: Text(cIntro.chineseName, style: const TextStyle(fontSize: 13)),
                subtitle: Text(short,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontFamily: 'monospace')),
                contentPadding: const EdgeInsets.only(left: 56),
                dense: true,
                onTap: () => widget.onSelected(c.id),
              );
            })),
        ],
      ],
    );
  }

  Widget _skillIcon(String name) {
    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFF4F46E5).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(name.isNotEmpty ? name[0] : 'S',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF4F46E5))),
      ),
    );
  }
}
