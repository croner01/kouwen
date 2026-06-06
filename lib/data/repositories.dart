import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'database.dart';
import 'models.dart';

const _uuid = Uuid();

class SkillRepository {
  final AppDatabase _db;

  SkillRepository(this._db);

  Future<List<Skill>> getInstalledSkills() async {
    final db = await _db.database;
    final maps =
        await db.query('installed_skills', orderBy: 'installed_at DESC');
    return maps.map(Skill.fromMap).toList();
  }

  /// Returns only top-level skills (collections + standalone skills)
  Future<List<Skill>> getTopLevelSkills() async {
    final db = await _db.database;
    final maps = await db.query(
      'installed_skills',
      where: 'parent_id IS NULL',
      orderBy: 'is_collection DESC, installed_at DESC',
    );
    final skills = maps.map(Skill.fromMap).toList();
    // Child counts are queried on demand in the UI via getChildCount()
    return skills;
  }

  /// Returns child skills of a collection
  Future<List<Skill>> getChildSkills(String parentId) async {
    final db = await _db.database;
    final maps = await db.query(
      'installed_skills',
      where: 'parent_id = ?',
      whereArgs: [parentId],
      orderBy: 'name ASC',
    );
    return maps.map(Skill.fromMap).toList();
  }

  /// Batch-fetch children for multiple parent collections (single query).
  Future<List<Skill>> getChildSkillsForParents(List<String> parentIds) async {
    if (parentIds.isEmpty) return [];
    final db = await _db.database;
    final placeholders = parentIds.map((_) => '?').join(',');
    final maps = await db.query(
      'installed_skills',
      where: 'parent_id IN ($placeholders)',
      whereArgs: parentIds,
      orderBy: 'name ASC',
    );
    return maps.map(Skill.fromMap).toList();
  }

  Future<Skill?> getSkillById(String id) async {
    final db = await _db.database;
    final maps =
        await db.query('installed_skills', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Skill.fromMap(maps.first);
  }

  Future<Skill> installSkill({
    required String name,
    required String version,
    String? author,
    required String category,
    required String yamlContent,
    String? parentId,
    bool isCollection = false,
    String? description,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final id = _uuid.v4();
    // Double-check dedup inside transaction to prevent race
    await db.transaction((txn) async {
      final conflictWhere = parentId != null
          ? 'name = ? AND parent_id = ?'
          : 'name = ? AND parent_id IS NULL';
      final existing = await txn.query(
        'installed_skills',
        where: conflictWhere,
        whereArgs: parentId != null ? [name, parentId] : [name],
        limit: 1,
      );
      if (existing.isNotEmpty) return; // already exists — skip
      await txn.insert('installed_skills', {
        'id': id,
        'name': name,
        'version': version,
        'author': author,
        'category': category,
        'yaml_content': yamlContent,
        'installed_at': now.millisecondsSinceEpoch,
        'parent_id': parentId,
        'is_collection': isCollection ? 1 : 0,
        'description': description,
      });
    });
    return Skill(
      id: id,
      name: name,
      version: version,
      author: author,
      category: category,
      yamlContent: yamlContent,
      installedAt: now,
      parentId: parentId,
      isCollection: isCollection,
      description: description,
    );
  }

  Future<void> deleteSkill(String id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      // Cascade: messages → conversations → skill + children
      // 1. Delete messages for all conversations of this skill
      final convoIds = await txn.query('conversations',
          columns: ['id'], where: 'skill_id = ?', whereArgs: [id]);
      for (final row in convoIds) {
        await txn.delete('messages',
            where: 'conversation_id = ?', whereArgs: [row['id']]);
      }
      // 2. Delete conversations
      await txn.delete('conversations', where: 'skill_id = ?', whereArgs: [id]);
      // 3. Delete child skills
      await txn.delete('installed_skills', where: 'parent_id = ?', whereArgs: [id]);
      // 4. Delete the skill itself
      await txn.delete('installed_skills', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Check if a skill with the same name already exists (top-level or child).
  /// Uses conditional WHERE to handle NULL parent_id correctly (IS NULL vs = ?).
  Future<bool> skillExists(String name, {String? parentId}) async {
    final db = await _db.database;
    final where = parentId != null
        ? 'name = ? AND parent_id = ?'
        : 'name = ? AND parent_id IS NULL';
    final maps = await db.query(
      'installed_skills',
      where: where,
      whereArgs: parentId != null ? [name, parentId] : [name],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  Future<void> updateSkill(
    String id, {
    required String name,
    required String version,
    String? author,
    String? description,
    required String category,
    required String yamlContent,
  }) async {
    final db = await _db.database;
    await db.update(
      'installed_skills',
      {
        'name': name,
        'version': version,
        'author': author,
        'category': category,
        'description': description,
        'yaml_content': yamlContent,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

class ConversationRepository {
  final AppDatabase _db;

  ConversationRepository(this._db);

  Future<List<Conversation>> getConversations() async {
    final db = await _db.database;
    final maps =
        await db.query('conversations', orderBy: 'updated_at DESC');
    return maps.map(Conversation.fromMap).toList();
  }

  Future<Conversation?> getConversationById(String id) async {
    final db = await _db.database;
    final maps =
        await db.query('conversations', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Conversation.fromMap(maps.first);
  }

  Future<Conversation> createConversation({
    String? skillId,
    String? skillName,
    String? modelConfigId,
    String? title,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final id = _uuid.v4();
    await db.insert('conversations', {
      'id': id,
      'skill_id': skillId,
      'skill_name': skillName,
      'model_config_id': modelConfigId,
      'title': title,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
    return Conversation(
      id: id,
      skillId: skillId,
      skillName: skillName,
      modelConfigId: modelConfigId,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> updateConversation(String id, {String? title, String? skillId, String? skillName}) async {
    final db = await _db.database;
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    if (title != null) updates['title'] = title;
    if (skillId != null) updates['skill_id'] = skillId;
    if (skillName != null) updates['skill_name'] = skillName;
    await db.update(
      'conversations',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteConversation(String id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('messages', where: 'conversation_id = ?', whereArgs: [id]);
      await txn.delete('conversations', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Message>> getMessages(String conversationId) async {
    final db = await _db.database;
    final maps = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );
    return maps.map(Message.fromMap).toList();
  }

  Future<Message> addMessage({
    required String conversationId,
    required MessageRole role,
    required String content,
    List<String>? attachments,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final id = _uuid.v4();
    await db.transaction((txn) async {
      await txn.insert('messages', {
        'id': id,
        'conversation_id': conversationId,
        'role': role.name,
        'content': content,
        'attachments': attachments != null ? jsonEncode(attachments) : null,
        'created_at': now.millisecondsSinceEpoch,
      });
      await txn.update(
        'conversations',
        {'updated_at': now.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    });
    return Message(
      id: id,
      conversationId: conversationId,
      role: role,
      content: content,
      attachments: attachments,
      createdAt: now,
    );
  }
}

class ModelConfigRepository {
  final AppDatabase _db;

  ModelConfigRepository(this._db);

  Future<List<ModelConfig>> getConfigs() async {
    final db = await _db.database;
    final maps =
        await db.query('model_configs', orderBy: 'created_at DESC');
    return maps.map(ModelConfig.fromMap).toList();
  }

  Future<ModelConfig?> getDefaultConfig() async {
    final db = await _db.database;
    final maps = await db
        .query('model_configs', where: 'is_default = 1', limit: 1);
    if (maps.isEmpty) return null;
    return ModelConfig.fromMap(maps.first);
  }

  Future<ModelConfig> addConfig({
    required String alias,
    required String apiUrl,
    required String modelName,
    bool isDefault = false,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final id = _uuid.v4();
    await db.transaction((txn) async {
      if (isDefault) {
        await txn.update('model_configs', {'is_default': 0});
      } else {
        final count = (await txn
                .rawQuery('SELECT COUNT(*) as c FROM model_configs'))
            .first['c'] as int;
        if (count == 0) isDefault = true;
      }
      await txn.insert('model_configs', {
        'id': id,
        'alias': alias,
        'api_url': apiUrl,
        'model_name': modelName,
        'is_default': isDefault ? 1 : 0,
        'created_at': now.millisecondsSinceEpoch,
      });
    });
    return ModelConfig(
      id: id,
      alias: alias,
      apiUrl: apiUrl,
      modelName: modelName,
      isDefault: isDefault,
      createdAt: now,
    );
  }

  Future<void> updateConfig(String id, {
    String? alias,
    String? apiUrl,
    String? modelName,
    bool? isDefault,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      var effectiveDefault = isDefault;
      if (effectiveDefault == true) {
        await txn.update('model_configs', {'is_default': 0});
      } else if (effectiveDefault == false) {
        // Prevent removing the last default config
        final count = (await txn
                .rawQuery('SELECT COUNT(*) as c FROM model_configs WHERE is_default = 1'))
            .first['c'] as int;
        final isOnlyDefault = count <= 1;
        if (isOnlyDefault) {
          // Keep this config as default to ensure system always has one
          effectiveDefault = true;
        }
      }
      final updates = <String, dynamic>{};
      if (alias != null) updates['alias'] = alias;
      if (apiUrl != null) updates['api_url'] = apiUrl;
      if (modelName != null) updates['model_name'] = modelName;
      if (effectiveDefault != null) updates['is_default'] = effectiveDefault ? 1 : 0;
      if (updates.isNotEmpty) {
        await txn.update('model_configs', updates,
            where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  Future<void> setDefault(String id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update('model_configs', {'is_default': 0});
      await txn.update('model_configs', {'is_default': 1},
          where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> deleteConfig(String id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      // Clear model_config_id references in existing conversations
      await txn.update('conversations', {'model_config_id': null},
          where: 'model_config_id = ?', whereArgs: [id]);
      await txn.delete('model_configs', where: 'id = ?', whereArgs: [id]);
    });
  }
}
