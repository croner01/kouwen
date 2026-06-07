import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaml/yaml.dart';
import '../engine/skill_parser.dart';
import '../data/database.dart';
import '../data/repositories.dart';
import '../providers.dart';
import 'auth/login_screen.dart';
import 'chat/chat_list_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scaleIn;
  bool _initDone = false;
  bool _minTimeElapsed = false;
  bool _authChecked = false;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeIn = CurvedAnimation(
        parent: _ctrl, curve: Curves.easeOutCubic);
    _scaleIn = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _ctrl.forward();

    // Min display time for splash visibility
    Future.delayed(const Duration(seconds: 2), () {
      _minTimeElapsed = true;
      _tryNavigate();
    });

    // Initialize skills
    _initSkills().then((_) {
      _initDone = true;
      _tryNavigate();
    });

    // Check auth state
    _checkAuth().then((_) {
      _authChecked = true;
      _tryNavigate();
    });
  }

  Future<void> _checkAuth() async {
    try {
      final auth = ref.read(authServiceProvider);
      await auth.restoreSession();
    } catch (_) {}
  }

  Future<void> _initSkills() async {
    try {
      final db = AppDatabase.instance;
      final repo = SkillRepository(db);
      final installed = await repo.getInstalledSkills();
      if (installed.isNotEmpty) return;

      // Create a parent collection for all built-in skills
      final parent = await repo.installSkill(
        name: 'Superpowers',
        version: '1.0.0',
        author: 'Anthropic',
        category: '科技',
        yamlContent: '',
        isCollection: true,
        description: 'Anthropic 官方 Superpowers 工具集 — 包含代码审查、调试、设计、文档等专业开发技能',
      );

      // Load individual skills as children of the collection
      List<String> paths;
      try {
        final manifestStr = await rootBundle.loadString('AssetManifest.json');
        final manifest = loadYaml(manifestStr) as Map;
        paths = manifest.keys
            .where((k) => k is String && k.startsWith('assets/builtin/'))
            .cast<String>()
            .toList();
      } catch (_) {
        // AssetManifest may not be available on all platforms/versions
        paths = [];
      }

      for (final path in paths) {
        final content = await rootBundle.loadString(path);
        try {
          final parsed = SkillParser.parse(content);
          await repo.installSkill(
            name: 'Superpowers/${parsed.name}',
            version: parsed.version,
            author: 'Anthropic',
            category: parsed.category,
            yamlContent: content,
            parentId: parent.id,
          );
        } catch (_) {
          // Skip unparseable files
        }
      }
    } catch (_) {
      // Graceful fallback
    }
  }

  void _tryNavigate() {
    if (_initDone && _authChecked && _minTimeElapsed && mounted) {
      final auth = ref.read(authServiceProvider);
      final destination = auth.isLoggedIn
          ? const ChatListScreen()
          : const LoginScreen();
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => destination,
          transitionsBuilder: (_, anim, __, child) {
            return FadeTransition(opacity: anim, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF4F46E5), // Indigo
              Color(0xFF7C3AED), // Violet
              Color(0xFF3B2660), // Deep purple
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeIn,
            child: ScaleTransition(
              scale: _scaleIn,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),
                  // Icon
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Center(
                      child: Text(
                        '叩',
                        style: TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.w300,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // App name
                  const Text(
                    '叩问',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                      letterSpacing: 12,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Poem
                  const Text(
                    '一叩即问',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '技达天下',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                      letterSpacing: 6,
                    ),
                  ),
                  const Spacer(flex: 3),
                  // Divider + "一叩即问，技达天下"
                  Container(
                    width: 1,
                    height: 60,
                    color: Colors.white24,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '一叩即问  技达天下',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white38,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
