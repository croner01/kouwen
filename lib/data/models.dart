import 'dart:convert';

class Skill {
  final String id;
  final String name;
  final String version;
  final String? author;
  final String category;
  final String yamlContent;
  final DateTime installedAt;
  final DateTime? updatedAt;
  final String? parentId;
  final bool isCollection;
  final String? description;

  const Skill({
    required this.id,
    required this.name,
    required this.version,
    this.author,
    required this.category,
    required this.yamlContent,
    required this.installedAt,
    this.updatedAt,
    this.parentId,
    this.isCollection = false,
    this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'author': author,
      'category': category,
      'yaml_content': yamlContent,
      'installed_at': installedAt.millisecondsSinceEpoch,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
      'parent_id': parentId,
      'is_collection': isCollection ? 1 : 0,
      'description': description,
    };
  }

  factory Skill.fromMap(Map<String, dynamic> map) {
    return Skill(
      id: map['id'] as String,
      name: map['name'] as String,
      version: map['version'] as String,
      author: map['author'] as String?,
      category: map['category'] as String,
      yamlContent: map['yaml_content'] as String,
      installedAt:
          DateTime.fromMillisecondsSinceEpoch(map['installed_at'] as int),
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : null,
      parentId: map['parent_id'] as String?,
      isCollection: (map['is_collection'] as int?) == 1,
      description: map['description'] as String?,
    );
  }
}

class Conversation {
  final String id;
  final String? skillId;
  final String? skillName;
  final String? modelConfigId;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Conversation({
    required this.id,
    this.skillId,
    this.skillName,
    this.modelConfigId,
    this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'skill_id': skillId,
      'skill_name': skillName,
      'model_config_id': modelConfigId,
      'title': title,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'] as String,
      skillId: map['skill_id'] as String?,
      skillName: map['skill_name'] as String?,
      modelConfigId: map['model_config_id'] as String?,
      title: map['title'] as String?,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }
}

enum MessageRole { user, assistant, system }

MessageRole _parseRole(String? raw) {
  if (raw == null) return MessageRole.system;
  try {
    return MessageRole.values.byName(raw);
  } catch (_) {
    return MessageRole.system; // unknown role → system fallback
  }
}

List<String>? _parseAttachments(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  // Try JSON first (new format)
  try {
    return (jsonDecode(raw) as List<dynamic>).cast<String>();
  } catch (_) {
    // Fall back to comma-separated (legacy format)
    return raw.split(',').where((s) => s.isNotEmpty).toList();
  }
}

class Message {
  final String id;
  final String conversationId;
  final MessageRole role;
  final String content;
  final List<String>? attachments;
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.attachments,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'role': role.name,
      'content': content,
      'attachments': attachments != null ? jsonEncode(attachments) : null,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      role: _parseRole(map['role'] as String?),
      content: map['content'] as String,
      attachments: _parseAttachments(map['attachments'] as String?),
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}

class ModelConfig {
  final String id;
  final String alias;
  final String apiUrl;
  final String modelName;
  final bool isDefault;
  final DateTime createdAt;

  const ModelConfig({
    required this.id,
    required this.alias,
    required this.apiUrl,
    required this.modelName,
    required this.isDefault,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'alias': alias,
      'api_url': apiUrl,
      'model_name': modelName,
      'is_default': isDefault ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory ModelConfig.fromMap(Map<String, dynamic> map) {
    return ModelConfig(
      id: map['id'] as String,
      alias: map['alias'] as String,
      apiUrl: map['api_url'] as String,
      modelName: map['model_name'] as String,
      isDefault: (map['is_default'] as int) == 1,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}
