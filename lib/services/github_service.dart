import 'dart:convert';
import 'package:dio/dio.dart';
import 'secure_storage_service.dart';

class GitHubRepo {
  final String name;
  final String fullName;
  final String description;
  final String language;
  final int stars;
  final bool isPrivate;

  const GitHubRepo({
    required this.name,
    required this.fullName,
    required this.description,
    required this.language,
    required this.stars,
    required this.isPrivate,
  });

  factory GitHubRepo.fromJson(Map<String, dynamic> json) {
    return GitHubRepo(
      name: json['name'] as String,
      fullName: json['full_name'] as String,
      description: (json['description'] ?? '') as String,
      language: (json['language'] ?? '') as String,
      stars: (json['stargazers_count'] ?? 0) as int,
      isPrivate: (json['private'] ?? false) as bool,
    );
  }
}

class GitHubFile {
  final String name;
  final String path;
  final String type; // 'file' or 'dir'
  final int? size;

  const GitHubFile({
    required this.name,
    required this.path,
    required this.type,
    this.size,
  });

  factory GitHubFile.fromJson(Map<String, dynamic> json) {
    return GitHubFile(
      name: json['name'] as String,
      path: json['path'] as String,
      type: json['type'] as String,
      size: json['size'] as int?,
    );
  }
}

class GitHubPr {
  final int number;
  final String title;
  final String body;
  final String author;
  final String state;
  final String? diffUrl;

  const GitHubPr({
    required this.number,
    required this.title,
    required this.body,
    required this.author,
    required this.state,
    this.diffUrl,
  });

  factory GitHubPr.fromJson(Map<String, dynamic> json) {
    return GitHubPr(
      number: json['number'] as int,
      title: json['title'] as String,
      body: (json['body'] ?? '') as String,
      author: json['user']?['login'] as String? ?? '',
      state: json['state'] as String,
      diffUrl: json['diff_url'] as String?,
    );
  }
}

class GitHubIssue {
  final int number;
  final String title;
  final String body;
  final String author;
  final String state;
  final List<String> labels;

  const GitHubIssue({
    required this.number,
    required this.title,
    required this.body,
    required this.author,
    required this.state,
    required this.labels,
  });

  factory GitHubIssue.fromJson(Map<String, dynamic> json) {
    return GitHubIssue(
      number: json['number'] as int,
      title: json['title'] as String,
      body: (json['body'] ?? '') as String,
      author: json['user']?['login'] as String? ?? '',
      state: json['state'] as String,
      labels: (json['labels'] as List<dynamic>?)
              ?.map((l) => (l as Map<String, dynamic>)['name'] as String)
              .toList() ??
          [],
    );
  }
}

class GitHubService {
  final SecureStorageService _secureStorage;
  final Dio _dio;
  bool useGitee = false;

  GitHubService(this._secureStorage, {Dio? dio}) : _dio = dio ?? Dio();

  // ---- Token Management ----

  Future<void> saveToken(String token) async {
    await _secureStorage.saveGitHubToken(token);
  }

  Future<String?> getToken() async => _secureStorage.getGitHubToken();

  Future<String?> getGiteeToken() async =>
      _secureStorage.read(key: 'gitee_token');

  Future<void> deleteToken() async {
    await _secureStorage.deleteGitHubToken();
  }

  Future<bool> isConnected() async {
    final gh = await getToken();
    if (gh != null && gh.isNotEmpty) return true;
    final gt = await getGiteeToken();
    return gt != null && gt.isNotEmpty;
  }

  Future<String?> getUsername() async {
    // Try GitHub first
    final ghToken = await getToken();
    if (ghToken != null) {
      try {
        final resp = await _dio.get(
          'https://api.github.com/user',
          options: Options(headers: _headers(ghToken)),
        );
        return resp.data['login'] as String?;
      } catch (_) {}
    }
    // Try Gitee
    final giteeToken = await getGiteeToken();
    if (giteeToken != null) {
      try {
        final resp = await _giteeGet('https://gitee.com/api/v5/user');
        return resp.data['login'] as String?;
      } catch (_) {}
    }
    return null;
  }

  /// Validate a Gitee token directly (bypasses GitHub check in getUsername).
  Future<String?> validateGiteeToken(String token) async {
    try {
      final resp = await _dio.get(
        'https://gitee.com/api/v5/user?access_token=$token',
      );
      return resp.data['login'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ---- Repos (Gitee-aware) ----

  Future<List<GitHubRepo>> listRepos({bool isGitee = false}) async {
    if (isGitee) return _listGiteeRepos();
    return _listGitHubRepos();
  }

  Future<List<GitHubRepo>> _listGitHubRepos() async {
    final token = await getToken();
    if (token == null) throw Exception('GitHub 未连接');
    final resp = await _dio.get(
      'https://api.github.com/user/repos?sort=updated&per_page=50',
      options: Options(headers: _headers(token)),
    );
    final list = resp.data as List<dynamic>;
    return list
        .map((e) => GitHubRepo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<GitHubRepo>> _listGiteeRepos() async {
    final resp = await _giteeGet(
      'https://gitee.com/api/v5/user/repos?sort=updated&per_page=50',
    );
    // Gitee returns a different field name for full_name
    final list = resp.data as List<dynamic>;
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return GitHubRepo(
        name: m['name'] as String,
        fullName: m['full_name'] as String? ?? '${m['owner']?['login']}/${m['name']}',
        description: (m['description'] ?? '') as String,
        language: (m['language'] ?? '') as String,
        stars: (m['stargazers_count'] ?? 0) as int,
        isPrivate: (m['private'] ?? false) as bool,
      );
    }).toList();
  }

  // ---- Files (Gitee-aware) ----

  Future<List<GitHubFile>> listFiles(String owner, String repo,
      {String path = '', bool isGitee = false}) async {
    if (isGitee) return _listGiteeFiles(owner, repo, path: path);

    final token = await getToken();
    if (token == null) throw Exception('GitHub 未连接');
    final url = path.isEmpty
        ? 'https://api.github.com/repos/$owner/$repo/contents'
        : 'https://api.github.com/repos/$owner/$repo/contents/$path';
    final resp = await _dio.get(url, options: Options(headers: _headers(token)));
    final data = resp.data;
    if (data is List) {
      return data.map((e) => GitHubFile.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<List<GitHubFile>> _listGiteeFiles(String owner, String repo,
      {String path = ''}) async {
    final url = path.isEmpty
        ? 'https://gitee.com/api/v5/repos/$owner/$repo/contents'
        : 'https://gitee.com/api/v5/repos/$owner/$repo/contents/$path';
    final resp = await _giteeGet(url);
    final data = resp.data;
    if (data is List) {
      return data.map((e) {
        final m = e as Map<String, dynamic>;
        return GitHubFile(
          name: m['name'] as String,
          path: m['path'] as String? ?? m['name'] as String,
          type: m['type'] as String,
          size: m['size'] as int?,
        );
      }).toList();
    }
    return [];
  }

  // ---- Read File ----

  Future<String> readFile(String owner, String repo, String path,
      {bool isGitee = false}) async {
    if (isGitee) return _readGiteeFile(owner, repo, path);

    final token = await getToken();
    if (token == null) throw Exception('GitHub 未连接');
    final resp = await _dio.get(
      'https://api.github.com/repos/$owner/$repo/contents/$path',
      options: Options(headers: _headers(token)),
    );
    final content = resp.data['content'] as String;
    return utf8.decode(base64.decode(content.replaceAll('\n', '')));
  }

  Future<String> _readGiteeFile(String owner, String repo, String path) async {
    // Gitee content API returns content directly (sometimes base64, sometimes plain)
    final resp = await _giteeGet(
      'https://gitee.com/api/v5/repos/$owner/$repo/contents/$path');
    final data = resp.data as Map<String, dynamic>;
    final content = data['content'] as String?;
    if (content != null) {
      try {
        return utf8.decode(base64.decode(content.replaceAll('\n', '')));
      } catch (_) {
        return content;
      }
    }
    // Fallback: use raw URL (try main first, then master)
    for (final branch in ['main', 'master']) {
      try {
        final rawResp = await _dio.get(
          'https://gitee.com/$owner/$repo/raw/$branch/$path',
        );
        if (rawResp.statusCode == 200) {
          return rawResp.data.toString();
        }
      } catch (_) {}
    }
    return content ?? '(无法读取文件内容)';
  }

  // ---- PRs ----

  Future<List<GitHubPr>> listPRs(String owner, String repo) async {
    final token = await getToken();
    if (token == null) throw Exception('GitHub 未连接');
    final resp = await _dio.get(
      'https://api.github.com/repos/$owner/$repo/pulls?state=open&per_page=20',
      options: Options(headers: _headers(token)),
    );
    final list = resp.data as List<dynamic>;
    return list
        .map((e) => GitHubPr.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> getPRDiff(String owner, String repo, int prNumber) async {
    final token = await getToken();
    if (token == null) throw Exception('GitHub 未连接');
    final resp = await _dio.get(
      'https://api.github.com/repos/$owner/$repo/pulls/$prNumber',
      options: Options(headers: {
        ..._headers(token),
        'Accept': 'application/vnd.github.v3.diff',
      }),
    );
    return resp.data as String;
  }

  // ---- Issues ----

  Future<List<GitHubIssue>> listIssues(String owner, String repo) async {
    final token = await getToken();
    if (token == null) throw Exception('GitHub 未连接');
    final resp = await _dio.get(
      'https://api.github.com/repos/$owner/$repo/issues?state=open&per_page=20',
      options: Options(headers: _headers(token)),
    );
    final list = resp.data as List<dynamic>;
    return list
        .where((e) => (e as Map<String, dynamic>)['pull_request'] == null)
        .map((e) => GitHubIssue.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Headers ----

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
      };

  /// Perform an authenticated GET to a Gitee API endpoint.
  /// Private tokens go in ?access_token= query param.
  Future<Response> _giteeGet(String url) async {
    final token = await getGiteeToken();
    var finalUrl = url;
    if (token != null && token.isNotEmpty) {
      final sep = url.contains('?') ? '&' : '?';
      finalUrl = '$url${sep}access_token=$token';
    }
    return _dio.get(finalUrl);
  }
}
