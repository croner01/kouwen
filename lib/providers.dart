import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/database.dart';
import 'data/repositories.dart';
import 'services/api_service.dart';
import 'services/github_service.dart';
import 'services/model_manager.dart';
import 'services/secure_storage_service.dart';

final dbProvider = Provider<AppDatabase>((ref) => AppDatabase.instance);

final skillRepoProvider = Provider<SkillRepository>(
  (ref) => SkillRepository(ref.watch(dbProvider)),
);

final conversationRepoProvider = Provider<ConversationRepository>(
  (ref) => ConversationRepository(ref.watch(dbProvider)),
);

final modelConfigRepoProvider = Provider<ModelConfigRepository>(
  (ref) => ModelConfigRepository(ref.watch(dbProvider)),
);

final secureStorageProvider = Provider<SecureStorageService>(
  (ref) => SecureStorageService(),
);

final modelManagerProvider = Provider<ModelManager>(
  (ref) => ModelManager(
    ref.watch(modelConfigRepoProvider),
    ref.watch(secureStorageProvider),
  ),
);

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final githubServiceProvider = Provider<GitHubService>(
  (ref) => GitHubService(ref.watch(secureStorageProvider)),
);
