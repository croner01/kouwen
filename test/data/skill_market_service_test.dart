import 'package:flutter_test/flutter_test.dart';
import 'package:kouwen/data/skill_market_service.dart';
import 'package:kouwen/services/skill_api_service.dart';

void main() {
  group('MarketSkill.fromBackendSkill', () {
    test('carries yamlContent from backend when non-empty', () {
      const backend = BackendSkill(
        id: 'b1',
        name: 'brand-guidelines',
        version: '1.0.0',
        author: 'ren02',
        category: '设计',
        yamlContent: 'name: brand-guidelines\nversion: 1.0.0\nsystem_prompt: 你是品牌设计专家',
      );

      final ms = MarketSkill.fromBackendSkill(backend);

      expect(ms.yamlContent, isNotNull);
      expect(ms.yamlContent, contains('system_prompt'));
      expect(ms.yamlContent, contains('品牌设计专家'));
    });

    test('sets yamlContent to null when backend yamlContent is empty', () {
      const backend = BackendSkill(
        id: 'b2',
        name: 'empty-skill',
        version: '1.0.0',
        author: 'test',
        category: '通用',
        yamlContent: '', // empty
      );

      final ms = MarketSkill.fromBackendSkill(backend);

      expect(ms.yamlContent, isNull);
    });

    test('preserves other fields when yamlContent is carried', () {
      const backend = BackendSkill(
        id: 'b3',
        name: 'code-review',
        version: '2.0.0',
        author: 'official',
        category: '科技',
        sourceRepo: 'ren02/skills',
        pythonDeps: ['pytest'],
        yamlContent: 'name: code-review',
      );

      final ms = MarketSkill.fromBackendSkill(backend);

      expect(ms.name, 'code-review');
      expect(ms.version, '2.0.0');
      expect(ms.author, 'official');
      expect(ms.category, '科技');
      expect(ms.sourceRepo, 'ren02/skills');
      expect(ms.pythonDeps, contains('pytest'));
      expect(ms.isInstalled, isTrue);
      expect(ms.id, 'b3');
      expect(ms.yamlContent, 'name: code-review');
    });
  });
}
