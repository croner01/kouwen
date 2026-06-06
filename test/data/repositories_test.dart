import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart' show Database, Transaction;
import 'package:kouwen/data/database.dart';
import 'package:kouwen/data/repositories.dart';
// ── Mocks ──

class _MockTransaction extends Mock implements Transaction {}

// Custom mock for Database that intercepts transaction() and invokes the callback.
class _MockDatabase extends Mock implements Database {
  final _MockTransaction _txn = _MockTransaction();

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
    bool? noEnqueue,
  }) async {
    return action(_txn);
  }
}

class _MockAppDatabase extends Mock implements AppDatabase {
  @override
  Future<Database> get database async => _db;
  final _MockDatabase _db = _MockDatabase();
}

// ── Helpers ──

Map<String, dynamic> _skillRow({
  String id = 's1',
  String name = '测试技能',
  String version = '1.0.0',
  String? author = '作者',
  String category = '通用',
  String yamlContent = 'name: 测试技能\nversion: 1.0.0',
  int installedAt = 0,
  String? parentId,
  bool isCollection = false,
}) {
  return {
    'id': id,
    'name': name,
    'version': version,
    'author': author,
    'category': category,
    'yaml_content': yamlContent,
    'installed_at': installedAt,
    'updated_at': null,
    'parent_id': parentId,
    'is_collection': isCollection ? 1 : 0,
    'description': null,
  };
}

void main() {
  late _MockAppDatabase mockAppDb;
  late _MockDatabase mockDb;
  late SkillRepository repo;

  setUp(() {
    mockAppDb = _MockAppDatabase();
    mockDb = mockAppDb._db;
    repo = SkillRepository(mockAppDb);
  });

  group('skillExists', () {
    test('returns true when a matching top-level skill exists', () async {
      when(() => mockDb.query(
            'installed_skills',
            where: any(named: 'where'),
            whereArgs: any(named: 'whereArgs'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [_skillRow()]);

      final exists = await repo.skillExists('测试技能');

      expect(exists, isTrue);
      verify(() => mockDb.query(
            'installed_skills',
            where: 'name = ? AND parent_id IS NULL',
            whereArgs: ['测试技能'],
            limit: 1,
          )).called(1);
    });

    test('returns false when no matching top-level skill exists', () async {
      when(() => mockDb.query(
            'installed_skills',
            where: any(named: 'where'),
            whereArgs: any(named: 'whereArgs'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => []);

      final exists = await repo.skillExists('不存在的技能');

      expect(exists, isFalse);
    });

    test('uses parent_id = ? for child skills', () async {
      when(() => mockDb.query(
            'installed_skills',
            where: any(named: 'where'),
            whereArgs: any(named: 'whereArgs'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [_skillRow()]);

      final exists = await repo.skillExists('子技能', parentId: 'collection1');

      expect(exists, isTrue);
      verify(() => mockDb.query(
            'installed_skills',
            where: 'name = ? AND parent_id = ?',
            whereArgs: ['子技能', 'collection1'],
            limit: 1,
          )).called(1);
    });
  });

  group('installSkill', () {
    test('inserts a new skill after double-check finds no duplicate', () async {
      final txn = mockDb._txn;
      when(() => txn.query(
            any(),
            where: any(named: 'where'),
            whereArgs: any(named: 'whereArgs'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => []);
      when(() => txn.insert(any(), any())).thenAnswer((_) async => 1);

      final skill = await repo.installSkill(
        name: '新技能',
        version: '1.0.0',
        category: '通用',
        yamlContent: 'name: 新技能',
      );

      expect(skill.name, '新技能');
      verify(() => txn.insert('installed_skills', any())).called(1);
    });

    test('skips insert when a skill with the same name already exists',
        () async {
      final txn = mockDb._txn;
      when(() => txn.query(
            any(),
            where: any(named: 'where'),
            whereArgs: any(named: 'whereArgs'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [_skillRow()]);

      await repo.installSkill(
        name: '测试技能',
        version: '1.0.0',
        category: '通用',
        yamlContent: 'name: 测试技能',
      );

      verifyNever(() => txn.insert('installed_skills', any()));
    });
  });
}
