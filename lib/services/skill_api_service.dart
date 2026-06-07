import 'package:dio/dio.dart';

/// A skill record returned by the backend API.
class BackendSkill {
  final String id;
  final String name;
  final String version;
  final String? author;
  final String category;
  final String? sourceRepo;
  final List<String> pythonDeps;
  final String yamlContent;
  final DateTime? installedAt;

  const BackendSkill({
    required this.id,
    required this.name,
    required this.version,
    this.author,
    required this.category,
    this.sourceRepo,
    this.pythonDeps = const [],
    this.yamlContent = '',
    this.installedAt,
  });

  factory BackendSkill.fromJson(Map<String, dynamic> json) {
    return BackendSkill(
      id: json['id'] as String,
      name: json['name'] as String,
      version: (json['version'] as String?) ?? '1.0.0',
      author: json['author'] as String?,
      category: (json['category'] as String?) ?? '通用',
      sourceRepo: json['source_repo'] as String?,
      pythonDeps: json['python_deps'] is List
          ? (json['python_deps'] as List).cast<String>()
          : [],
      yamlContent: (json['yaml_content'] as String?) ?? '',
      installedAt: json['installed_at'] != null
          ? DateTime.tryParse(json['installed_at'] as String)
          : null,
    );
  }
}

/// Result of a skill install operation from the backend.
class InstallResult {
  final String status;
  final List<InstallResultSkill> skills;

  const InstallResult({required this.status, required this.skills});

  factory InstallResult.fromJson(Map<String, dynamic> json) {
    final skillsList = (json['skills'] as List<dynamic>?)
            ?.map((e) => InstallResultSkill.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return InstallResult(
      status: json['status'] as String,
      skills: skillsList,
    );
  }
}

/// An individual skill installed by the backend.
class InstallResultSkill {
  final String id;
  final String name;
  final List<String> pythonDeps;
  final int files;
  final List<String> filesList;

  const InstallResultSkill({
    required this.id,
    required this.name,
    this.pythonDeps = const [],
    this.files = 0,
    this.filesList = const [],
  });

  factory InstallResultSkill.fromJson(Map<String, dynamic> json) {
    return InstallResultSkill(
      id: json['id'] as String,
      name: json['name'] as String,
      pythonDeps: json['python_deps'] is List
          ? (json['python_deps'] as List).cast<String>()
          : [],
      files: (json['files'] as int?) ?? 0,
      filesList: json['files_list'] is List
          ? (json['files_list'] as List).cast<String>()
          : [],
    );
  }
}

/// HTTP client for backend Skill API.
///
/// Handles skill listing, installation (full directory + pip deps via backend),
/// and deletion. Requires JWT authentication from [AuthService].
class SkillApiService {
  final Dio _dio;
  final String _baseUrl;

  SkillApiService({required String baseUrl, Dio? dio})
      : _baseUrl = baseUrl,
        _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 120);
  }

  static const defaultBaseUrl = 'https://none-ringtone-adaptor-materials.trycloudflare.com';

  String? _jwtToken;

  void setAuth(String token) => _jwtToken = token;
  void clearAuth() => _jwtToken = null;

  Map<String, String> get _headers =>
      _jwtToken != null ? {'Authorization': 'Bearer $_jwtToken'} : {};

  /// List installed skills from backend.
  Future<List<BackendSkill>> listSkills() async {
    final resp = await _dio.get(
      '$_baseUrl/api/v1/skills',
      options: Options(headers: _headers),
    );
    final data = resp.data as Map<String, dynamic>;
    final skills = (data['skills'] as List<dynamic>?)
            ?.map((e) => BackendSkill.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return skills;
  }

  /// Install a skill from a Gitee repo. Backend handles full directory download,
  /// PVC storage, and pip dependency installation.
  Future<InstallResult> installSkill(String sourceRepo) async {
    final resp = await _dio.post(
      '$_baseUrl/api/v1/skills/install',
      data: {'source_repo': sourceRepo},
      options: Options(headers: _headers),
    );
    return InstallResult.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Delete a skill by its backend ID.
  Future<void> deleteSkill(String skillId) async {
    await _dio.delete(
      '$_baseUrl/api/v1/skills/$skillId',
      options: Options(headers: _headers),
    );
  }
}
