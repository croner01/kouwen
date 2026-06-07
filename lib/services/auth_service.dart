import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  final Dio _dio;
  final FlutterSecureStorage _storage;
  final String _baseUrl;
  static const _tokenKey = 'kouwen_jwt';
  static const _userKey = 'kouwen_user';

  String? _token;
  Map<String, dynamic>? _user;

  AuthService({
    required String baseUrl,
    Dio? dio,
    FlutterSecureStorage? storage,
  })  : _baseUrl = baseUrl,
        _dio = dio ?? Dio(),
        _storage = storage ?? const FlutterSecureStorage() {
    _dio.options.connectTimeout = const Duration(seconds: 10);
  }

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isLoggedIn => _token != null;

  /// Restore saved session from secure storage.
  Future<bool> restoreSession() async {
    try {
      final t = await _storage.read(key: _tokenKey);
      final u = await _storage.read(key: _userKey);
      if (t == null || u == null) return false;
      _token = t;
      _user = jsonDecode(u) as Map<String, dynamic>;
      final resp = await _dio.get(
        '$_baseUrl/api/v1/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $_token'}),
      );
      if (resp.statusCode == 200) {
        _user = resp.data['user'] as Map<String, dynamic>;
        await _saveSession();
        return true;
      }
    } catch (_) {}
    _token = null;
    _user = null;
    return false;
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String nickname = '',
  }) async {
    final resp = await _dio.post(
      '$_baseUrl/api/v1/auth/register',
      data: {'email': email, 'password': password, 'nickname': nickname},
    );
    final data = resp.data as Map<String, dynamic>;
    _token = data['token'] as String;
    _user = data['user'] as Map<String, dynamic>;
    await _saveSession();
    return _user!;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final resp = await _dio.post(
      '$_baseUrl/api/v1/auth/login',
      data: {'email': email, 'password': password},
    );
    final data = resp.data as Map<String, dynamic>;
    _token = data['token'] as String;
    _user = data['user'] as Map<String, dynamic>;
    await _saveSession();
    return _user!;
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }

  Map<String, String> get authHeaders =>
      {'Authorization': 'Bearer $_token'};

  Future<void> _saveSession() async {
    if (_token == null || _user == null) return;
    await _storage.write(key: _tokenKey, value: _token!);
    await _storage.write(key: _userKey, value: jsonEncode(_user!));
  }
}
