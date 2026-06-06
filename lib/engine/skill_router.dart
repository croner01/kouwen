import '../data/models.dart';
import '../data/repositories.dart';
import '../data/database.dart';
import 'skill_parser.dart';
import 'skill_intro.dart';

class SkillMatch {
  final Skill skill;
  final ParsedSkill parsed;
  final SkillIntro intro;
  final double score;
  final String reason;

  const SkillMatch({
    required this.skill,
    required this.parsed,
    required this.intro,
    required this.score,
    required this.reason,
  });
}

/// Intelligent skill router — matches user input to relevant installed skills.
///
/// Matching strategy (multi-dimensional):
/// 1. Category keyword match — domain-specific terms tied to categories
/// 2. Chinese name match — SkillIntroBuilder's Chinese display names
/// 3. System prompt full-text match — the most informative field
/// 4. Description keyword match — from SKILL.md frontmatter
/// 5. Skill file-name match — English names like "stock-screener"
class SkillRouter {
  /// Cache of parsed skills to avoid re-parsing YAML on every match() call.
  static final Map<String, _CachedSkill> _cache = {};

  /// Invalidate the parse cache — call after skill install/uninstall.
  static void invalidateCache() => _cache.clear();
  /// Category → trigger keywords (Chinese + English)
  static const _categoryKeywords = {
    '财经': [
      // Chinese
      '股票', 'A股', '美股', '港股', '基金', '理财', '投资', '交易',
      '止损', '止盈', 'K线', 'MACD', '技术分析', '基本面', '估值',
      '财报', 'PE', 'PB', 'ROE', '股息', '期权', '期货', '分红',
      '仓位', '回测', '策略', '量化', '选股', '板块', '行情',
      '买入', '卖出', '持仓', '涨幅', '跌幅', '涨停', '跌停',
      '大盘', '指数', '沪深', '创业板', '科创板', '北交所',
      '牛', '熊', '震荡', '突破', '支撑', '阻力', '均线',
      // English
      'stock', 'trade', 'invest', 'backtest', 'screener',
      'earnings', 'dividend', 'breakout', 'CANSLIM',
      'bull', 'bear', 'technical', 'fundamental', 'portfolio',
      'option', 'future', 'forex', 'crypto',
    ],
    '科技': [
      '代码', 'bug', '函数', 'API', '前端', 'React', 'Vue', 'CSS',
      'Python', 'Java', 'MCP', '测试', 'debug', '开发', '编程',
      'review', '重构', '优化', '接口', '服务器', '数据库',
      'Playwright', 'web', 'html', '后端', '架构', '部署',
      'docker', 'k8s', 'CI', 'CD', 'Git', 'Linux', 'shell',
      'npm', 'package', 'dart', 'flutter', 'react', 'node',
    ],
    '法律': [
      '合同', '法律', '诉讼', '律师', '仲裁', '侵权', '赔偿',
      '劳动法', '民法', '刑法', '知识产权', '维权', '官司',
      '条款', '违约', '合规', '法规', '判决', '起诉', '应诉',
    ],
    '医疗': [
      '症状', '医院', '药物', '手术', '诊断', '体检', '用药',
      '血压', '血糖', 'CT', 'B超', '内科', '外科', '处方',
      '头疼', '发烧', '咳嗽', '慢性病', '急诊', '疫苗',
    ],
    '教育': [
      '论文', '答辩', '学术', '文献', '导师', '写作', '选题',
      '考试', '学习', '课程', '面试', '求职', '简历', '教学',
      'offer', 'STAR', '职业', 'career', 'coach', '教案',
    ],
    '设计': [
      '设计', 'brand', '品牌', '色彩', '排版', '商标', 'logo',
      'UI', 'UX', '界面', '海报', 'theme', '配色', '字体',
    ],
    '文档': [
      'PDF', 'Excel', 'xlsx', 'docx', '文档', '报表', '表格',
      '幻灯片', 'PPT', 'word', 'csv', 'json', '数据', '图表',
    ],
    '创作': [
      '翻译', '写作', '文案', '润色', 'GIF', 'slack', '文章',
      'translate', 'blog', 'write', 'copywrite', '内容',
    ],
  };

  /// Match user input to the most relevant installed skills.
  /// Returns matches sorted by score descending.
  static Future<List<SkillMatch>> match(String userInput, {SkillRepository? repo}) async {
    final input = userInput.toLowerCase();
    repo ??= SkillRepository(AppDatabase.instance);
    final allSkills = await _getAllMatchableSkills(repo);

    final matches = <SkillMatch>[];

    for (final skill in allSkills) {
      if (skill.isCollection || skill.yamlContent.isEmpty) continue;

      double score = 0;
      final reasons = <String>[];

      try {
        // Use cached parse result if available (keyed by skill id + version)
        final cacheKey = '${skill.id}:${skill.version}';
        var cached = _cache[cacheKey];
        if (cached == null) {
          final parsed = SkillParser.parse(skill.yamlContent);
          final intro = SkillIntroBuilder.build(
            rawName: skill.name,
            parsed: parsed,
            rawYaml: skill.yamlContent,
          );
          cached = _CachedSkill(parsed: parsed, intro: intro);
          _cache[cacheKey] = cached;
        }
        final parsed = cached.parsed;
        final intro = cached.intro;
        final shortName = skill.name.contains('/')
            ? skill.name.split('/').last
            : skill.name;

        // 1) Category keyword match (+20 each)
        final catKeywords =
            _categoryKeywords[skill.category] ?? <String>[];
        int kwHits = 0;
        for (final kw in catKeywords) {
          if (input.contains(kw.toLowerCase())) {
            kwHits++;
          }
        }
        if (kwHits > 0) {
          score += kwHits * 20;
          reasons.add('关键词匹配($kwHits)');
        }

        // 2) Chinese name match (+35 — strongest signal)
        if (intro.chineseName.isNotEmpty &&
            intro.chineseName != shortName) {
          // Split Chinese name into chars and check multi-char substrings
          final cn = intro.chineseName;
          for (int len = cn.length; len >= 2; len--) {
            for (int i = 0; i + len <= cn.length; i++) {
              final sub = cn.substring(i, i + len);
              if (sub.length >= 2 && input.contains(sub)) {
                score += 35;
                reasons.add('中文名匹配');
                break;
              }
            }
            if (reasons.contains('中文名匹配')) break;
          }
        }

        // 3) System prompt full-text search (+3 per hit, high coverage)
        final promptLower = parsed.systemPrompt.toLowerCase();
        final promptWords = promptLower
            .split(RegExp(r'[\s,，。；、！？\n]+'))
            .where((w) => w.length >= 2)
            .toSet();
        int promptHits = 0;
        for (final w in promptWords) {
          if (input.contains(w)) {
            promptHits++;
          }
        }
        if (promptHits > 0) {
          score += promptHits * 3;
          if (!reasons.any((r) => r.startsWith('内容匹配'))) {
            reasons.add('内容匹配($promptHits)');
          }
        }

        // 4) Description keyword match (+5 each)
        if (parsed.description != null) {
          final descWords = parsed.description!
              .toLowerCase()
              .split(RegExp(r'[\s,，。；]+'));
          for (final w in descWords) {
            if (w.length > 2 && input.contains(w)) {
              score += 5;
            }
          }
        }

        // 5) Skill English name match (+30)
        if (input.contains(shortName.toLowerCase().replaceAll('-', '')) ||
            input.contains(parsed.name.toLowerCase())) {
          score += 30;
          reasons.add('技能名匹配');
        }

        if (score > 0) {
          matches.add(SkillMatch(
            skill: skill,
            parsed: parsed,
            intro: intro,
            score: score,
            reason: reasons.join(' · '),
          ));
        }
      } catch (_) {
        // Skip unparseable skills
      }
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches;
  }

  /// Fetch all matchable skills including collection children (single batch query).
  static Future<List<Skill>> _getAllMatchableSkills(
      SkillRepository repo) async {
    final top = await repo.getInstalledSkills();
    final result = <Skill>[];
    final collectionIds = <String>[];

    for (final skill in top) {
      if (skill.isCollection) {
        collectionIds.add(skill.id);
      } else if (skill.parentId == null) {
        result.add(skill);
      }
    }

    // Batch-fetch all collection children in one query instead of N queries
    if (collectionIds.isNotEmpty) {
      final children = await repo.getChildSkillsForParents(collectionIds);
      result.addAll(children);
    }

    return result;
  }

  /// Minimum score to auto-load without user confirmation
  static const double autoMatchThreshold = 25;

  /// Minimum score to show a suggestion chip (user can tap to load)
  static const double suggestThreshold = 8;
}

class _CachedSkill {
  final ParsedSkill parsed;
  final SkillIntro intro;
  const _CachedSkill({required this.parsed, required this.intro});
}
