import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'secure_storage_service.dart';

/// Single source of truth for the default server URL.
const kDefaultServerUrl =
    'https://none-ringtone-adaptor-materials.trycloudflare.com';

/// Persists and exposes the backend server URL via SecureStorage.
///
/// Fallback: [kDefaultServerUrl].
/// On change: saved to SecureStorage immediately.
class ServerUrlNotifier extends StateNotifier<String> {
  final SecureStorageService _storage;
  static const _key = 'server_url';
  bool _loaded = false;

  ServerUrlNotifier(this._storage) : super(kDefaultServerUrl);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final saved = await _storage.read(key: _key);
      if (saved != null && saved.isNotEmpty) {
        state = saved;
      }
    } catch (_) {}
  }

  Future<void> setUrl(String url) async {
    state = url.trim();
    await _storage.write(key: _key, value: state);
  }

  Future<void> resetToDefault() async {
    state = kDefaultServerUrl;
    await _storage.delete(_key);
  }
}
