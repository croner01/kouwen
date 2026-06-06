import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kouwen/core/theme_provider.dart';
import 'package:kouwen/services/secure_storage_service.dart';
import 'package:kouwen/providers.dart';

/// Fake SecureStorageService that stores values in memory (no platform channel needed)
class _FakeSecureStorageService implements SecureStorageService {
  final _store = <String, String>{};

  @override
  Future<String?> read({required String key}) async => _store[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _store[key] = value;
  }

  @override
  Future<void> saveApiKey(String configId, String apiKey) async {}

  @override
  Future<String?> getApiKey(String configId) async => null;

  @override
  Future<void> deleteApiKey(String configId) async {}

  @override
  Future<void> saveGitHubToken(String token) async {}

  @override
  Future<String?> getGitHubToken() async => null;

  @override
  Future<void> deleteGitHubToken() async {}

  @override
  Future<void> saveBraveSearchKey(String key) async {}

  @override
  Future<String?> getBraveSearchKey() async => null;

  @override
  Future<void> deleteAll() async {}

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }
}

void main() {
  group('ThemeModeNotifier', () {
    test('initial state is ThemeMode.system', () {
      final container = ProviderContainer(overrides: [
        secureStorageProvider.overrideWith((ref) => _FakeSecureStorageService()),
      ]);
      addTearDown(container.dispose);

      final mode = container.read(themeModeProvider);
      expect(mode, ThemeMode.system);
    });

    test('toggle switches between light and dark', () async {
      final container = ProviderContainer(overrides: [
        secureStorageProvider.overrideWith((ref) => _FakeSecureStorageService()),
      ]);
      addTearDown(container.dispose);

      // First toggle: system -> dark
      await container.read(themeModeProvider.notifier).toggle();
      expect(container.read(themeModeProvider), ThemeMode.dark);

      // Second toggle: dark -> light
      await container.read(themeModeProvider.notifier).toggle();
      expect(container.read(themeModeProvider), ThemeMode.light);

      // Third toggle: light -> dark
      await container.read(themeModeProvider.notifier).toggle();
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('setMode changes to specified mode', () async {
      final container = ProviderContainer(overrides: [
        secureStorageProvider.overrideWith((ref) => _FakeSecureStorageService()),
      ]);
      addTearDown(container.dispose);

      await container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
      expect(container.read(themeModeProvider), ThemeMode.dark);

      await container.read(themeModeProvider.notifier).setMode(ThemeMode.light);
      expect(container.read(themeModeProvider), ThemeMode.light);

      await container.read(themeModeProvider.notifier).setMode(ThemeMode.system);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });
  });
}
