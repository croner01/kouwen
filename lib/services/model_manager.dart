import '../data/models.dart';
import '../data/repositories.dart';
import 'secure_storage_service.dart';

class ModelManager {
  final ModelConfigRepository _configRepo;
  final SecureStorageService _secureStorage;

  ModelManager(this._configRepo, this._secureStorage);

  Future<List<ModelConfig>> getConfigs() => _configRepo.getConfigs();

  Future<ModelConfig?> getDefaultConfig() => _configRepo.getDefaultConfig();

  Future<ModelConfig> addConfig({
    required String alias,
    required String apiUrl,
    required String modelName,
    required String apiKey,
    bool isDefault = false,
  }) async {
    final config = await _configRepo.addConfig(
      alias: alias,
      apiUrl: apiUrl,
      modelName: modelName,
      isDefault: isDefault,
    );
    await _secureStorage.saveApiKey(config.id, apiKey);
    return config;
  }

  Future<String?> getApiKey(String configId) =>
      _secureStorage.getApiKey(configId);

  Future<void> updateConfig(String id, {
    String? alias,
    String? apiUrl,
    String? modelName,
    String? apiKey,
    bool? isDefault,
  }) async {
    if (apiKey != null) {
      await _secureStorage.saveApiKey(id, apiKey);
    }
    await _configRepo.updateConfig(id,
        alias: alias, apiUrl: apiUrl, modelName: modelName, isDefault: isDefault);
  }

  Future<void> setDefault(String id) => _configRepo.setDefault(id);

  Future<void> deleteConfig(String id) async {
    // Delete DB record first — if it fails, nothing is lost.
    // If secure storage delete fails after, orphaned key is harmless.
    await _configRepo.deleteConfig(id);
    await _secureStorage.deleteApiKey(id);
  }
}
