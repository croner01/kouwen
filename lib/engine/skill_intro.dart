import 'skill_parser.dart';

/// Chinese-friendly display info for a skill
class SkillIntro {
  final String chineseName;
  final String description;
  final String usage;
  final List<String> sampleQuestions;

  const SkillIntro({
    required this.chineseName,
    required this.description,
    required this.usage,
    required this.sampleQuestions,
  });
}

/// Maps raw skill names/descriptions to Chinese-friendly UI content.
class SkillIntroBuilder {
  /// Known skill names → Chinese display name (exact match)
  static const _nameMap = {
    // Collection names
    'Superpowers': 'Superpowers 工具集',

    // Built-in Anthropic skills
    'brainstorming': '头脑风暴',
    'brand-guidelines': '品牌设计规范',
    'doc-coauthoring': '文档协作撰写',
    'executing-plans': '计划执行器',
    'finishing-a-development-branch': '开发分支收尾',
    'frontend-design': '前端界面设计',
    'internal-comms': '内部沟通协作',
    'mcp-builder': 'MCP 服务构建',
    'pdf': 'PDF 文档处理',
    'requesting-code-review': '代码审查助手',
    'skill-creator': '技能创建器',
    'slack-gif-creator': 'Slack GIF 制作',
    'systematic-debugging': '系统化调试',
    'test-driven-development': '测试驱动开发',
    'using-superpowers': 'Superpowers 使用指南',
    'verification-before-completion': '完成前验证',
    'webapp-testing': 'Web 应用测试',
    'writing-plans': '方案撰写助手',
    'writing-skills': '技能编写指南',
    'xlsx': 'Excel 表格处理',

    // Trading / Finance
    'stock-screener': '股票筛选分析',
    'backtest-engine': '策略回测引擎',
    'technical-analysis': '技术分析工具',
    'fundamental-analysis': '基本面分析',
    'options-strategy': '期权策略分析',
    'portfolio-manager': '投资组合管理',
    'market-scanner': '市场扫描器',
    'risk-manager': '风险管理器',
    'earnings-analyzer': '财报分析器',
    'dividend-tracker': '股息追踪器',
    'breakout-detector': '突破检测器',
    'canslim-scanner': 'CANSLIM 选股器',
    'sector-rotation': '板块轮动分析',

    // Legal
    'contract-review': '合同审查助手',
    'legal-research': '法律文献检索',
    'compliance-check': '合规检查器',
    'ip-analyzer': '知识产权分析',
    'litigation-prep': '诉讼准备助手',
    'privacy-audit': '隐私合规审计',

    // Medical
    'symptom-checker': '症状分析助手',
    'drug-interaction': '药物相互作用检查',
    'medical-report': '医疗报告解读',
    'health-tracking': '健康追踪分析',

    // Education
    'lesson-planner': '教案设计助手',
    'essay-reviewer': '论文审阅助手',
    'quiz-generator': '试题生成器',
    'career-coach': '职业规划教练',
    'interview-prep': '面试准备教练',

    // DevOps
    'ci-cd-pipeline': 'CI/CD 流水线',
    'docker-compose': 'Docker 编排助手',
    'k8s-deploy': 'K8s 部署助手',
    'monitoring-setup': '监控配置助手',
    'security-audit': '安全审计工具',
    'incident-response': '事故响应助手',

    // Design
    'ui-review': 'UI 评审助手',
    'color-palette': '配色方案生成',
    'typography': '字体排版设计',
    'design-system': '设计系统构建',

    // Writing / Creative
    'blog-writer': '博客文章撰写',
    'copywriter': '文案撰写助手',
    'translator': '翻译助手',
    'ppt-generator': 'PPT 生成器',
    'gif-creator': 'GIF 动图制作',
  };

  /// Keyword-based Chinese name fallback
  static final _keywordMap = <String, String>{
    'stock': '股票',
    'trade': '交易',
    'backtest': '回测',
    'screener': '筛选',
    'analysis': '分析',
    'code': '代码',
    'review': '审查',
    'debug': '调试',
    'test': '测试',
    'design': '设计',
    'brand': '品牌',
    'doc': '文档',
    'pdf': 'PDF',
    'xlsx': '表格',
    'legal': '法律',
    'contract': '合同',
    'medical': '医疗',
    'health': '健康',
    'edu': '教育',
    'tutor': '教学',
    'coach': '教练',
    'devops': '运维',
    'deploy': '部署',
    'security': '安全',
    'monitor': '监控',
    'mcp': 'MCP',
    'api': 'API',
    'web': 'Web',
    'frontend': '前端',
    'write': '撰写',
    'creator': '创建',
    'builder': '构建',
    'plan': '方案',
    'theme': '主题',
  };

  /// Build a SkillIntro from a ParsedSkill (if available) or raw content.
  static SkillIntro build({
    required String rawName,
    ParsedSkill? parsed,
    String? rawYaml,
  }) {
    final lower = rawName.toLowerCase().replaceAll('_', '-').replaceAll(' ', '-');

    // 1. Exact match in name map
    String chineseName = _nameMap[lower] ?? _nameMap[rawName] ?? '';

    // 2. Partial match: strip common prefixes/suffixes
    if (chineseName.isEmpty) {
      for (final entry in _nameMap.entries) {
        if (lower.contains(entry.key) || entry.key.contains(lower)) {
          chineseName = entry.value;
          break;
        }
      }
    }

    // 3. Keyword-based fallback
    if (chineseName.isEmpty) {
      final parts = <String>[];
      for (final entry in _keywordMap.entries) {
        if (lower.contains(entry.key)) {
          parts.add(entry.value);
        }
      }
      if (parts.isNotEmpty) {
        chineseName = parts.take(3).join('');
      }
    }

    // 4. Absolute fallback
    if (chineseName.isEmpty) {
      chineseName = rawName.replaceAll('-', ' ').replaceAll('_', ' ');
    }

    // Description: prefer parsed description, then derive from name
    String description = '';
    if (parsed?.description != null && parsed!.description!.isNotEmpty) {
      description = parsed.description!;
      // Truncate very long descriptions
      if (description.length > 300) {
        description = '${description.substring(0, 300)}...';
      }
    }
    if (description.isEmpty) {
      description = _defaultDescription(chineseName, lower);
    }

    // Usage guide
    final usage = _buildUsage(chineseName, lower, parsed);

    // Sample questions
    List<String> samples = parsed?.sampleQuestions ?? [];
    if (samples.isEmpty) {
      samples = _defaultSamples(chineseName, lower);
    }

    return SkillIntro(
      chineseName: chineseName,
      description: description,
      usage: usage,
      sampleQuestions: samples,
    );
  }

  static String _defaultDescription(String chineseName, String lower) {
    if (lower.contains('stock') || lower.contains('trade')) return '股票筛选、技术分析、策略回测等量化交易相关功能';
    if (lower.contains('code') || lower.contains('debug')) return '代码审查、Bug调试、重构建议等开发辅助功能';
    if (lower.contains('design') || lower.contains('brand')) return '界面设计、品牌规范、色彩排版等设计辅助功能';
    if (lower.contains('doc') || lower.contains('pdf') || lower.contains('xlsx')) return '文档处理、格式转换、表格操作等办公自动化功能';
    if (lower.contains('legal') || lower.contains('law') || lower.contains('contract')) return '合同审查、法律检索、合规检查等法律辅助功能';
    if (lower.contains('medical') || lower.contains('health')) return '症状分析、用药咨询、报告解读等健康管理功能';
    if (lower.contains('edu') || lower.contains('tutor') || lower.contains('coach')) return '教学设计、论文辅导、职业规划等教育辅助功能';
    if (lower.contains('devops') || lower.contains('deploy')) return 'CI/CD流水线、容器编排、监控配置等运维辅助功能';
    if (lower.contains('mcp') || lower.contains('api')) return 'MCP服务构建、API开发、接口调试等工具开发功能';
    if (lower.contains('test')) return '自动化测试、测试用例生成、测试覆盖率分析';
    if (lower.contains('write') || lower.contains('blog') || lower.contains('copy')) return '文案撰写、内容创作、多语言翻译等写作辅助功能';
    return '通用AI助手技能，根据具体问题智能响应';
  }

  static String _buildUsage(String chineseName, String lower, ParsedSkill? parsed) {
    final buf = StringBuffer();

    // System prompt summary
    if (parsed != null && parsed.systemPrompt.isNotEmpty) {
      final prompt = parsed.systemPrompt;
      // Extract first meaningful paragraph as usage overview
      final lines = prompt.split('\n');
      var overview = '';
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.startsWith('#') || trimmed.startsWith('-') || trimmed.startsWith('*')) continue;
        if (trimmed.startsWith('---')) continue;
        overview = trimmed;
        break;
      }
      if (overview.length > 200) {
        overview = '${overview.substring(0, 200)}...';
      }
      if (overview.isNotEmpty) {
        buf.writeln(overview);
      }
    }

    // Add capabilities
    if (parsed != null && parsed.capabilities.isNotEmpty) {
      buf.writeln();
      buf.writeln('**能力范围：**');
      for (final cap in parsed.capabilities.take(8)) {
        buf.writeln('- $cap');
      }
    }

    if (buf.isEmpty) {
      buf.writeln('在对话中描述你的需求，「$chineseName」会自动分析并提供专业建议。');
      buf.writeln();
      buf.writeln('**使用技巧：**');
      buf.writeln('- 提供尽可能详细的背景信息');
      buf.writeln('- 明确说明期望的输出格式');
      buf.writeln('- 必要时可以上传相关文件作为参考');
    }

    return buf.toString();
  }

  static List<String> _defaultSamples(String chineseName, String lower) {
    if (lower.contains('stock') || lower.contains('trade')) {
      return ['帮我筛选出PE<15且ROE>15%的A股股票', '分析贵州茅台最近一年的技术走势', '回测这个均线交叉策略的收益率'];
    }
    if (lower.contains('code') || lower.contains('review')) {
      return ['帮我审查这段代码的安全漏洞', '如何优化这个函数的性能？', '请为这个模块写单元测试'];
    }
    if (lower.contains('design') || lower.contains('brand')) {
      return ['为我的SaaS产品设计一套配色方案', '优化这个登录页面的用户体验', '生成符合品牌规范的名片设计'];
    }
    if (lower.contains('doc') || lower.contains('pdf') || lower.contains('xlsx')) {
      return ['把这份Excel数据做成图表', '提取PDF中的表格数据', '把这个CSV文件清理并格式化'];
    }
    if (lower.contains('debug')) {
      return ['这段代码报NullPointerException怎么修？', '帮我系统性地排查这个性能瓶颈', '线上服务偶发超时，如何定位根因？'];
    }
    if (lower.contains('test')) {
      return ['为这个UserService写完整的单元测试', '用Playwright测试这个登录流程', '设计这个支付模块的测试用例'];
    }
    if (lower.contains('mcp')) {
      return ['帮我创建一个新的MCP Server', '给这个API添加OAuth认证', '如何设计一个RESTful接口？'];
    }
    return ['请问你能帮我做什么？', '这个技能有什么使用技巧？'];
  }
}
