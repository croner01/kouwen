import 'package:dio/dio.dart';
import 'github_skill_loader.dart';
import '../data/skill_market_service.dart';

class SkillSource {
  final String name;
  final String owner;
  final String repo;
  final String branch;
  final bool isGitee;

  const SkillSource({
    required this.name,
    required this.owner,
    required this.repo,
    this.branch = 'main',
    this.isGitee = false,
  });
}

class GitHubSkillSource {
  final GitHubSkillLoader _loader;

  static const official = SkillSource(
    name: 'Gitee 技能市场',
    owner: 'ren02',
    repo: 'skills',
    branch: 'main',
    isGitee: true,
  );

  // Gitee mirror for Chinese users
  static const giteeSource = SkillSource(
    name: 'Gitee 技能市场',
    owner: 'kouwen-app',
    repo: 'skills-market',
    branch: 'main',
    isGitee: true,
  );

  GitHubSkillSource({Dio? dio, String? token, String? giteeToken})
      : _loader = GitHubSkillLoader(dio: dio, token: token, giteeToken: giteeToken);

  /// Fast scan: list skills from a GitHub source (no content download).
  /// If the repo is detected as a collection, returns a single MarketSkill entry.
  Future<List<MarketSkill>> fetchFromSource(SkillSource source) async {
    final prefix = source.isGitee ? 'https://gitee.com/' : '';
    final input = '$prefix${source.owner}/${source.repo}/${source.branch}';
    final result = await _loader.scanRepo(input);

    // If it's a collection, return one entry representing the whole thing
    if (result.isCollection && result.collection != null) {
      final coll = result.collection!;
      return [
        MarketSkill(
          name: coll.name,
          displayName: coll.name,
          version: 'latest',
          author: source.name,
          description: coll.description,
          icon: _guessIcon(coll.category),
          category: coll.category,
          tags: [],
          file: '',
          sourceUrl: null,
          sourceRepo: '${source.owner}/${source.repo}',
          downloads: 0,
          rating: 0,
          isCollection: true,
          childCount: coll.childSkills.length,
        )
      ];
    }

    final skills = <MarketSkill>[];
    for (final r in result.skills) {
      final category = r.category ?? '通用';
      final parts = r.path.split('/');
      // Use parent dir name if nested, otherwise filename minus extension
      final displayName = parts.length >= 2
          ? parts[parts.length - 2]
              .replaceAll('-', ' ')
              .replaceAll('_', ' ')
          : parts.last
              .replaceAll('.md', '')
              .replaceAll('.yaml', '')
              .replaceAll('.yml', '')
              .replaceAll('-', ' ')
              .replaceAll('_', ' ');

      skills.add(MarketSkill(
        name: displayName,
        displayName: displayName,
        version: 'latest',
        author: source.name,
        description: r.path,
        icon: _guessIcon(category),
        category: category,
        tags: [],
        file: parts.last,
        sourceUrl: r.url,
        sourceRepo: '${source.owner}/${source.repo}',
        downloads: 0,
        rating: 0,
      ));
    }
    return skills;
  }

  /// Download and install a skill's real content from GitHub
  Future<String?> downloadSkillContent(String url) =>
      _loader.downloadSkillContent(url);

  String _guessIcon(String cat) {
    switch (cat) {
      case '科技': return '\u{1F4BB}';
      case '设计': return '\u{1F3A8}';
      case '文档': return '\u{1F4C4}';
      case '财经': return '\u{1F4C8}';
      default: return '\u{1F916}';
    }
  }
}
