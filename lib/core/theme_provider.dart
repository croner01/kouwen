import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/secure_storage_service.dart';
import '../providers.dart';

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.read(secureStorageProvider));
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final SecureStorageService _storage;
  static const _themeKey = 'theme_mode';

  ThemeModeNotifier(this._storage) : super(ThemeMode.system) {
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await _storage.read(key: _themeKey);
    if (saved == 'dark') {
      state = ThemeMode.dark;
    } else if (saved == 'light') {
      state = ThemeMode.light;
    }
  }

  Future<void> toggle() async {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await _storage.write(
        key: _themeKey, value: state == ThemeMode.dark ? 'dark' : 'light');
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final value = mode == ThemeMode.dark
        ? 'dark'
        : mode == ThemeMode.light
            ? 'light'
            : 'system';
    await _storage.write(key: _themeKey, value: value);
  }
}
