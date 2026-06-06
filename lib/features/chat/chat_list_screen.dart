import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import 'chat_screen.dart';
import 'widgets/conversation_tile.dart';
import '../skills/my_skills_screen.dart';
import '../skills/skill_market_screen.dart';
import '../skills/providers/install_provider.dart';
import '../settings/settings_screen.dart';

final conversationsProvider =
    FutureProvider<List<Conversation>>((ref) async {
  final repo = ConversationRepository(ref.watch(dbProvider));
  return repo.getConversations();
});

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  bool _showSearch = false;
  String _query = '';
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() {
      _showSearch = true;
      _query = '';
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    setState(() {
      _showSearch = false;
      _query = '';
      _searchCtrl.clear();
    });
  }

  List<Conversation> _filter(List<Conversation> list) {
    if (_query.isEmpty) return list;
    final q = _query.toLowerCase();
    return list.where((c) {
      return (c.title?.toLowerCase().contains(q) ?? false) ||
          (c.skillName?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final conversationsAsync = ref.watch(conversationsProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('退出叩问'),
            content: const Text('正在进行的 AI 回复将在后台继续'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => SystemNavigator.pop(),
                child: const Text('退出'),
              ),
            ],
          ),
        );
      },
      child: Scaffold(
        appBar: AppBar(
        title: _showSearch
            ? AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    autofocus: false,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: '搜索对话...',
                      border: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 16),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              )
            : const Text('叩问'),
        actions: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: _showSearch
                ? IconButton(
                    key: const ValueKey('close'),
                    icon: const Icon(Icons.close),
                    onPressed: _closeSearch,
                  )
                : IconButton(
                    key: const ValueKey('search'),
                    icon: const Icon(Icons.search),
                    onPressed: _openSearch,
                  ),
          ),
        ],
      ),
      body: conversationsAsync.when(
        data: (conversations) {
          final filtered = _filter(conversations);
          if (conversations.isEmpty) {
            return _EmptyState(onStart: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const MySkillsScreen()),
              ).then((_) => ref.invalidate(conversationsProvider));
            });
          }
          if (filtered.isEmpty && _query.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off,
                      size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('未找到 "$_query"',
                      style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(conversationsProvider),
            child: ListView.builder(
                padding:
                    const EdgeInsets.only(top: 8, bottom: 80),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final conv = filtered[i];
                  return _AnimatedTile(
                    index: i,
                    child: ConversationTile(
                      conversation: conv,
                      onTap: () {
                        Navigator.of(context).push(
                          _pageRoute(
                            ChatScreen(
                                conversationId: conv.id),
                          ),
                        ).then((_) => ref.invalidate(conversationsProvider));
                      },
                      onDelete: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('删除对话'),
                            content: Text(
                                '确定删除「${conv.title ?? "新对话"}」？\n所有消息将被永久删除。'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  final repo = ConversationRepository(
                                      ref.read(dbProvider));
                                  await repo.deleteConversation(
                                      conv.id);
                                  ref.invalidate(
                                      conversationsProvider);
                                },
                                child: const Text('删除',
                                    style: TextStyle(
                                        color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            );
        },
        loading: () =>
            const Center(child: _LoadingSkeleton()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: _FABAnimation(
        child: FloatingActionButton.extended(
          onPressed: () {
            Navigator.of(context).push(
              _pageRoute(const ChatScreen()),
            ).then((_) => ref.invalidate(conversationsProvider));
          },
          icon: const Icon(Icons.add_comment),
          label: const Text('新对话'),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (index) {
          switch (index) {
            case 0:
              break;
            case 1:
              Navigator.of(context).push(
                _pageRoute(const SkillMarketScreen()),
              ).then((_) => ref.invalidate(conversationsProvider));
              break;
            case 2:
              Navigator.of(context).push(
                _pageRoute(const MySkillsScreen()),
              ).then((_) => ref.invalidate(conversationsProvider));
              break;
            case 3:
              Navigator.of(context).push(
                _pageRoute(const SettingsScreen()),
              ).then((_) => ref.invalidate(conversationsProvider));
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              label: '对话'),
          BottomNavigationBarItem(
              icon: Icon(Icons.store_outlined), label: '市场'),
          BottomNavigationBarItem(
              icon: _InstallBadge(), label: '技能'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              label: '设置'),
        ],
      ),
      ),
    );
  }

  Route _pageRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}

/// Animated list tile entrance
class _AnimatedTile extends StatefulWidget {
  final int index;
  final Widget child;
  const _AnimatedTile({required this.index, required this.child});

  @override
  State<_AnimatedTile> createState() => _AnimatedTileState();
}

class _AnimatedTileState extends State<_AnimatedTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// FAB entrance animation
class _FABAnimation extends StatefulWidget {
  final Widget child;
  const _FABAnimation({required this.child});

  @override
  State<_FABAnimation> createState() => _FABAnimationState();
}

class _FABAnimationState extends State<_FABAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scale = CurvedAnimation(
        parent: _ctrl, curve: Curves.elasticOut);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

/// Loading skeleton
class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onStart;
  const _EmptyState({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(
                  scale: v, child: child),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.auto_awesome,
                    size: 36, color: Color(0xFF4F46E5)),
              ),
            ),
            const SizedBox(height: 24),
            const Text('欢迎使用叩问',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              '选择一个技能，叩启你的专业 AI 对话',
              style: TextStyle(
                  fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.rocket_launch),
              label: const Text('开启叩问'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Badge icon for the "技能" tab — shows a dot when installing in background.
class _InstallBadge extends ConsumerWidget {
  const _InstallBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installState = ref.watch(installerProvider);
    return Badge(
      isLabelVisible: installState.isInstalling,
      child: const Icon(Icons.grid_view_outlined),
    );
  }
}
