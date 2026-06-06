import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _keyPrefix = 'kouwen_api_key_';
  static const giteeTokenKey = 'gitee_token';

  Future<void> saveApiKey(String configId, String apiKey) async {
    await _storage.write(key: '$_keyPrefix$configId', value: apiKey);
  }

  Future<String?> getApiKey(String configId) async {
    return _storage.read(key: '$_keyPrefix$configId');
  }

  Future<void> deleteApiKey(String configId) async {
    await _storage.delete(key: '$_keyPrefix$configId');
  }

  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  static const _githubTokenKey = 'github_pat';

  Future<void> saveGitHubToken(String token) async {
    await _storage.write(key: _githubTokenKey, value: token);
  }

  Future<String?> getGitHubToken() async {
    return _storage.read(key: _githubTokenKey);
  }

  Future<void> deleteGitHubToken() async {
    await _storage.delete(key: _githubTokenKey);
  }

  /// Generic read for non-API-key settings (theme, preferences, etc.)
  Future<String?> read({required String key}) async {
    return _storage.read(key: key);
  }

  /// Generic write for non-API-key settings
  Future<void> write({required String key, required String value}) async {
    await _storage.write(key: key, value: value);
  }

  /// Delete all keys managed by this service only (not all FlutterSecureStorage keys).
  Future<void> deleteAll() async {
    final allKeys = await _storage.readAll();
    for (final key in allKeys.keys) {
      if (key.startsWith(_keyPrefix) ||
          key == 'github_pat' ||
          key == giteeTokenKey) {
        await _storage.delete(key: key);
      }
    }
  }
}
