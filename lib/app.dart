import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/theme_provider.dart';
import 'features/splash_screen.dart';
import 'features/skills/providers/install_provider.dart' show installScaffoldKey;

class KouWenApp extends ConsumerWidget {
  const KouWenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: '叩问',
      scaffoldMessengerKey: installScaffoldKey,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}
