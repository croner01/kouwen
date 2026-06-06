import 'package:flutter_test/flutter_test.dart';
import 'package:kouwen/engine/skill_parser.dart';

void main() {
  group('SkillParser', () {
    const validYaml = '''
name: "法律咨询"
version: 1.0.0
author: "测试团队"
description: "测试技能"
icon: "⚖️"
category: "法律"
system_prompt: >
  你是一位法律专家。
  请客观回答。
capabilities:
  - text_generation
welcome_message: "你好"
sample_questions:
  - "问题1"
  - "问题2"
prompt_templates:
  review: >
    请审查：{{text}}
''';

    test('parse valid YAML returns ParsedSkill', () {
      final skill = SkillParser.parse(validYaml);

      expect(skill.name, '法律咨询');
      expect(skill.version, '1.0.0');
      expect(skill.author, '测试团队');
      expect(skill.category, '法律');
      expect(skill.icon, '⚖️');
      expect(skill.systemPrompt, contains('你是一位法律专家'));
      expect(skill.welcomeMessage, '你好');
      expect(skill.sampleQuestions, ['问题1', '问题2']);
      expect(skill.capabilities, ['text_generation']);
      expect(skill.promptTemplates['review'], contains('{{text}}'));
    });

    test('parse YAML without optional fields uses defaults', () {
      const minimalYaml = '''
name: "最小技能"
version: 1.0.0
category: "其他"
system_prompt: "你是一个助手。"
''';

      final skill = SkillParser.parse(minimalYaml);

      expect(skill.name, '最小技能');
      expect(skill.author, isNull);
      expect(skill.welcomeMessage, 'Hello! How can I help you?');
      expect(skill.sampleQuestions, isEmpty);
      expect(skill.promptTemplates, isEmpty);
    });

    test('parse invalid YAML throws SkillParseException', () {
      expect(
        () => SkillParser.parse('not: valid: yaml: [[['),
        throwsA(isA<SkillParseException>()),
      );
    });

    test('parse YAML missing required field throws SkillParseException', () {
      expect(
        () => SkillParser.parse('name: "测试"'),
        throwsA(isA<SkillParseException>()),
      );
    });
  });
}
