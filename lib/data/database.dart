import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static Database? _db;
  static Future<Database>? _initFuture;
  static final AppDatabase instance = AppDatabase._();

  AppDatabase._();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _initFuture ??= _init().then((db) {
      _db = db;
      return db;
    }).catchError((_) {
      _initFuture = null; // allow retry on next call
      throw _; // rethrow so the caller sees the error
    });
    return _initFuture!;
  }

  Future<Database> _init() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'kouwen.db');
    final db = await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    await db.execute('PRAGMA foreign_keys = ON');
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE installed_skills (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        version TEXT NOT NULL,
        author TEXT,
        category TEXT NOT NULL,
        yaml_content TEXT NOT NULL,
        installed_at INTEGER NOT NULL,
        updated_at INTEGER,
        parent_id TEXT,
        is_collection INTEGER DEFAULT 0,
        description TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        skill_id TEXT,
        skill_name TEXT,
        model_config_id TEXT,
        title TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        attachments TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE model_configs (
        id TEXT PRIMARY KEY,
        alias TEXT NOT NULL,
        api_url TEXT NOT NULL,
        model_name TEXT NOT NULL,
        is_default INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    // Unique index on (name, parent_id) to prevent duplicate skill installs
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_skill_name_parent ON installed_skills(name, COALESCE(parent_id, \'\'))');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE installed_skills ADD COLUMN parent_id TEXT');
      await db.execute('ALTER TABLE installed_skills ADD COLUMN is_collection INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE installed_skills ADD COLUMN description TEXT');
    }
    if (oldVersion < 3) {
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_skill_name_parent ON installed_skills(name, COALESCE(parent_id, \'\'))');
    }
    if (oldVersion < 4) {
      // Make skill_id nullable — conversations can exist without a skill loaded.
      // SQLite doesn't support DROP COLUMN or ALTER COLUMN, so we recreate the table.
      // Use IF NOT EXISTS to be idempotent if the migration is re-run.
      await db.execute('CREATE TABLE IF NOT EXISTS conversations_v4 ('
          'id TEXT PRIMARY KEY,'
          'skill_id TEXT,'
          'skill_name TEXT,'
          'model_config_id TEXT,'
          'title TEXT,'
          'created_at INTEGER NOT NULL,'
          'updated_at INTEGER NOT NULL'
          ')');
      await db.execute('INSERT OR IGNORE INTO conversations_v4 SELECT * FROM conversations');
      await db.execute('DROP TABLE IF EXISTS conversations');
      await db.execute('ALTER TABLE conversations_v4 RENAME TO conversations');
    }
  }
}
