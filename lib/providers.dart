import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/database.dart';
import 'data/repositories.dart';
import 'services/api_service.dart';
import 'services/github_service.dart';
import 'services/model_manager.dart';
import 'services/agent_service.dart';
import 'services/auth_service.dart';
import 'services/sandbox_service.dart';
import 'services/secure_storage_service.dart';
import 'services/skill_api_service.dart';

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

final sandboxServiceProvider = Provider<SandboxService>(
  (ref) => SandboxService(baseUrl: SandboxService.defaultUrl),
);

final agentServiceProvider = Provider<AgentService>(
  (ref) => AgentService(baseUrl: AgentService.defaultUrl),
);

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final skillApiServiceProvider = Provider<SkillApiService>((ref) {
  final service = SkillApiService(baseUrl: SkillApiService.defaultBaseUrl);
  // Auto-inject JWT if user is logged in
  final auth = ref.watch(authServiceProvider);
  if (auth.isLoggedIn && auth.token != null) {
    service.setAuth(auth.token!);
  }
  return service;
});
