import 'package:yaml/yaml.dart';

class SkillParseException implements Exception {
  final String message;
  const SkillParseException(this.message);

  @override
  String toString() => 'SkillParseException: $message';
}

class ParsedSkill {
  final String name;
  final String version;
  final String? author;
  final String? description;
  final String icon;
  final String category;
  final String systemPrompt;
  final List<String> capabilities;
  final String welcomeMessage;
  final List<String> sampleQuestions;
  final Map<String, String> promptTemplates;
  final String? sourceUrl; // GitHub source
  final String? sourceRepo;

  const ParsedSkill({
    required this.name,
    required this.version,
    this.author,
    this.description,
    required this.icon,
    required this.category,
    required this.systemPrompt,
    required this.capabilities,
    required this.welcomeMessage,
    required this.sampleQuestions,
    required this.promptTemplates,
    this.sourceUrl,
    this.sourceRepo,
  });
}

class SkillParser {
  /// Auto-detect format: YAML or SKILL.md (YAML frontmatter + markdown body)
  static ParsedSkill parse(String content) {
    final trimmed = content.trim();
    // SKILL.md format: starts with "---" frontmatter
    if (trimmed.startsWith('---')) {
      return _parseSkillMd(trimmed);
    }
    // Legacy YAML format
    return _parseYaml(trimmed);
  }

  /// Parse SKILL.md format (YAML frontmatter + Markdown body)
  static ParsedSkill _parseSkillMd(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty || lines[0].trim() != '---') {
      throw const SkillParseException('SKILL.md must start with ---');
    }

    // Extract frontmatter (--- must be alone on its own line, not inside a YAML value)
    var i = 1;
    final fmLines = <String>[];
    while (i < lines.length) {
      final trimmed = lines[i].trim();
      if (trimmed == '---') break; // valid closing delimiter (alone on line)
      fmLines.add(lines[i]);
      i++;
    }

    if (i >= lines.length) {
      throw const SkillParseException('SKILL.md frontmatter not closed');
    }

    // Body starts after the closing ---
    final body = lines.sublist(i + 1).join('\n').trim();

    // Parse frontmatter as YAML
    final fmYaml = fmLines.join('\n');
    dynamic fm;
    try {
      fm = loadYaml(fmYaml);
    } catch (e) {
      throw SkillParseException('Frontmatter YAML invalid: $e');
    }

    if (fm is! YamlMap) {
      throw const SkillParseException('Frontmatter must be key-value pairs');
    }

    final name = (fm['name'] as String?)?.trim();
    final description = (fm['description'] as String?)?.trim();

    if (name == null || name.isEmpty) {
      throw const SkillParseException('SKILL.md missing name in frontmatter');
    }

    // Build category from skill name patterns
    final category = _guessCategory(name.toLowerCase());

    return ParsedSkill(
      name: name,
      version: fm['version'] as String? ?? '1.0.0',
      author: fm['author'] as String?,
      description: description,
      icon: _guessIcon(name.toLowerCase()),
      category: category,
      systemPrompt: body.isNotEmpty ? body : (description ?? ''),
      capabilities: ['text_generation'],
      welcomeMessage: description ?? 'Hi! How can I help?',
      sampleQuestions: [],
      promptTemplates: {},
    );
  }

  /// Legacy YAML format parser
  static ParsedSkill _parseYaml(String yamlContent) {
    dynamic doc;
    try {
      doc = loadYaml(yamlContent);
    } catch (e) {
      throw SkillParseException('YAML format invalid: $e');
    }

    if (doc is! YamlMap) {
      throw SkillParseException('YAML content must be a key-value mapping');
    }

    final name = doc['name'] as String?;
    final version = doc['version'] as String?;
    final category = doc['category'] as String?;
    final systemPrompt = doc['system_prompt'] as String?;

    if (name == null || name.isEmpty) {
      throw SkillParseException('Missing required field: name');
    }
    if (version == null || version.isEmpty) {
      throw SkillParseException('Missing required field: version');
    }
    if (category == null || category.isEmpty) {
      throw SkillParseException('Missing required field: category');
    }
    if (systemPrompt == null || systemPrompt.toString().isEmpty) {
      throw SkillParseException('Missing required field: system_prompt');
    }

    final caps = doc['capabilities'];
    final List<String> capabilities;
    if (caps is YamlList) {
      capabilities = caps.map((e) => e.toString()).toList();
    } else {
      capabilities = [];
    }

    final samples = doc['sample_questions'];
    final List<String> sampleQuestions;
    if (samples is YamlList) {
      sampleQuestions = samples.map((e) => e.toString()).toList();
    } else {
      sampleQuestions = [];
    }

    final templates = doc['prompt_templates'];
    final Map<String, String> promptTemplates = {};
    if (templates is YamlMap) {
      for (final entry in templates.entries) {
        promptTemplates[entry.key.toString()] =
            entry.value.toString().trim();
      }
    }

    return ParsedSkill(
      name: name,
      version: version,
      author: doc['author'] as String?,
      description: doc['description'] as String?,
      icon: (doc['icon'] as String?) ?? '\u{1F916}',
      category: category,
      systemPrompt: systemPrompt.toString().trim(),
      capabilities: capabilities,
      welcomeMessage: (doc['welcome_message'] as String?) ??
          'Hello! How can I help you?',
      sampleQuestions: sampleQuestions,
      promptTemplates: promptTemplates,
    );
  }

  static String _guessCategory(String name) {
    if (name.contains('code') || name.contains('mcp') || name.contains('api') ||
        name.contains('web') || name.contains('frontend')) return '科技';
    if (name.contains('design') || name.contains('brand') || name.contains('theme') ||
        name.contains('art') || name.contains('canvas')) return '设计';
    if (name.contains('doc') || name.contains('xls') || name.contains('pdf') ||
        name.contains('pptx')) return '文档';
    if (name.contains('legal') || name.contains('law')) return '法律';
    if (name.contains('medical') || name.contains('health')) return '医疗';
    if (name.contains('finance') || name.contains('stock') || name.contains('invest')) return '财经';
    if (name.contains('edu') || name.contains('tutor') || name.contains('coach')) return '教育';
    return '通用';
  }

  static String _guessIcon(String name) {
    if (name.contains('code') || name.contains('mcp')) return '\u{1F4BB}';
    if (name.contains('design') || name.contains('brand')) return '\u{1F3A8}';
    if (name.contains('doc') || name.contains('xls') || name.contains('pptx') || name.contains('pdf')) return '\u{1F4C4}';
    if (name.contains('web') || name.contains('frontend')) return '\u{1F310}';
    if (name.contains('test')) return '\u{1F9EA}';
    if (name.contains('art')) return '\u{1F3A8}';
    if (name.contains('theme')) return '\u{1F308}';
    if (name.contains('api')) return '\u{1F527}';
    if (name.contains('coach') || name.contains('interview')) return '\u{1F3AF}';
    return '\u{1F916}';
  }
}
