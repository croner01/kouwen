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
import 'services/server_url_service.dart';

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

/// Persisted server URL. Initialized from SecureStorage on first access.
final serverUrlProvider =
    StateNotifierProvider<ServerUrlNotifier, String>((ref) {
  final notifier = ServerUrlNotifier(ref.watch(secureStorageProvider));
  notifier.load();
  return notifier;
});

final sandboxServiceProvider = Provider<SandboxService>((ref) {
  final url = ref.watch(serverUrlProvider);
  return SandboxService(baseUrl: url);
});

final agentServiceProvider = Provider<AgentService>((ref) {
  final url = ref.watch(serverUrlProvider);
  return AgentService(baseUrl: url);
});

final authServiceProvider = Provider<AuthService>((ref) {
  final url = ref.watch(serverUrlProvider);
  return AuthService(baseUrl: url);
});

final skillApiServiceProvider = Provider<SkillApiService>((ref) {
  final url = ref.watch(serverUrlProvider);
  final service = SkillApiService(baseUrl: url);
  // Auto-inject JWT if user is logged in
  final auth = ref.watch(authServiceProvider);
  if (auth.isLoggedIn && auth.token != null) {
    service.setAuth(auth.token!);
  }
  return service;
});
