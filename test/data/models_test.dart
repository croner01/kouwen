import 'package:flutter_test/flutter_test.dart';
import 'package:kouwen/data/models.dart';

void main() {
  group('Skill', () {
    test('toMap and fromMap roundtrip', () {
      final original = Skill(
        id: 's1',
        name: '测试技能',
        version: '1.0.0',
        author: '作者',
        category: '法律',
        yamlContent: 'name: test',
        installedAt: DateTime(2026, 6, 4, 10, 0),
        updatedAt: DateTime(2026, 6, 4, 12, 0),
      );

      final map = original.toMap();
      final restored = Skill.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.version, original.version);
      expect(restored.author, original.author);
      expect(restored.category, original.category);
      expect(restored.yamlContent, original.yamlContent);
      expect(restored.installedAt, original.installedAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('fromMap with null optional fields', () {
      final map = {
        'id': 's1',
        'name': 'minimal',
        'version': '1.0',
        'author': null,
        'category': 'other',
        'yaml_content': 'test',
        'installed_at': DateTime(2026).millisecondsSinceEpoch,
        'updated_at': null,
      };

      final skill = Skill.fromMap(map);

      expect(skill.author, isNull);
      expect(skill.updatedAt, isNull);
    });
  });

  group('Conversation', () {
    test('toMap and fromMap roundtrip', () {
      final original = Conversation(
        id: 'c1',
        skillId: 's1',
        skillName: '法律咨询',
        modelConfigId: 'm1',
        title: '合同纠纷咨询',
        createdAt: DateTime(2026, 6, 1),
        updatedAt: DateTime(2026, 6, 4),
      );

      final map = original.toMap();
      final restored = Conversation.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.skillId, original.skillId);
      expect(restored.skillName, original.skillName);
      expect(restored.title, original.title);
      expect(restored.createdAt, original.createdAt);
    });

    test('toMap/fromMap roundtrip with null skillId', () {
      final original = Conversation(
        id: 'c2',
        skillId: null,
        title: '无条件对话',
        createdAt: DateTime(2026, 6, 1),
        updatedAt: DateTime(2026, 6, 4),
      );

      final map = original.toMap();
      final restored = Conversation.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.skillId, isNull);
      expect(restored.title, original.title);
    });

    test('fromMap with null optional fields', () {
      final map = {
        'id': 'c1',
        'skill_id': 's1',
        'skill_name': null,
        'model_config_id': null,
        'title': null,
        'created_at': DateTime(2026).millisecondsSinceEpoch,
        'updated_at': DateTime(2026).millisecondsSinceEpoch,
      };

      final conv = Conversation.fromMap(map);

      expect(conv.skillName, isNull);
      expect(conv.title, isNull);
      expect(conv.modelConfigId, isNull);
    });

    test('fromMap with null skill_id', () {
      final map = {
        'id': 'c2',
        'skill_id': null,
        'skill_name': null,
        'title': '无条件对话',
        'created_at': DateTime(2026).millisecondsSinceEpoch,
        'updated_at': DateTime(2026).millisecondsSinceEpoch,
      };

      final conv = Conversation.fromMap(map);

      expect(conv.skillId, isNull);
      expect(conv.title, '无条件对话');
    });
  });

  group('Message', () {
    test('toMap and fromMap roundtrip', () {
      final original = Message(
        id: 'm1',
        conversationId: 'c1',
        role: MessageRole.user,
        content: '测试消息',
        attachments: ['/path/file.txt'],
        createdAt: DateTime(2026, 6, 4),
      );

      final map = original.toMap();
      final restored = Message.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.conversationId, original.conversationId);
      expect(restored.role, original.role);
      expect(restored.content, original.content);
      expect(restored.attachments, ['/path/file.txt']);
    });

    test('fromMap with null attachments', () {
      final map = {
        'id': 'm1',
        'conversation_id': 'c1',
        'role': 'assistant',
        'content': 'hello',
        'attachments': null,
        'created_at': DateTime(2026).millisecondsSinceEpoch,
      };

      final msg = Message.fromMap(map);

      expect(msg.attachments, isNull);
      expect(msg.role, MessageRole.assistant);
    });

    test('role serialization covers all values', () {
      for (final role in MessageRole.values) {
        final msg = Message(
          id: 'm',
          conversationId: 'c',
          role: role,
          content: 'test',
          createdAt: DateTime.now(),
        );
        final map = msg.toMap();
        final restored = Message.fromMap(map);
        expect(restored.role, role);
      }
    });
  });

  group('ModelConfig', () {
    test('toMap and fromMap roundtrip', () {
      final original = ModelConfig(
        id: 'mc1',
        alias: '我的DeepSeek',
        apiUrl: 'https://api.deepseek.com',
        modelName: 'deepseek-v4-pro',
        isDefault: true,
        createdAt: DateTime(2026, 6, 4),
      );

      final map = original.toMap();
      final restored = ModelConfig.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.alias, original.alias);
      expect(restored.apiUrl, original.apiUrl);
      expect(restored.modelName, original.modelName);
      expect(restored.isDefault, true);
    });

    test('isDefault = 0 maps to false', () {
      final map = {
        'id': 'mc1',
        'alias': 'test',
        'api_url': 'https://api.test.com',
        'model_name': 'test-model',
        'is_default': 0,
        'created_at': DateTime(2026).millisecondsSinceEpoch,
      };

      final config = ModelConfig.fromMap(map);

      expect(config.isDefault, false);
    });

    test('isDefault = 1 maps to true', () {
      final map = {
        'id': 'mc1',
        'alias': 'test',
        'api_url': 'https://api.test.com',
        'model_name': 'test-model',
        'is_default': 1,
        'created_at': DateTime(2026).millisecondsSinceEpoch,
      };

      final config = ModelConfig.fromMap(map);

      expect(config.isDefault, true);
    });
  });
}
