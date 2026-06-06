import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers.dart';
import '../../../data/models.dart';
import '../../../services/model_manager.dart';

final modelConfigsProvider =
    FutureProvider<List<ModelConfig>>((ref) async {
  final manager = ref.watch(modelManagerProvider);
  return manager.getConfigs();
});

class ModelConfigFormNotifier
    extends StateNotifier<AsyncValue<void>> {
  final ModelManager _manager;

  ModelConfigFormNotifier(this._manager)
      : super(const AsyncValue.data(null));

  Future<void> addConfig({
    required String alias,
    required String apiUrl,
    required String modelName,
    required String apiKey,
    bool isDefault = false,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _manager.addConfig(
        alias: alias,
        apiUrl: apiUrl,
        modelName: modelName,
        apiKey: apiKey,
        isDefault: isDefault,
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateConfig({
    required String id,
    String? alias,
    String? apiUrl,
    String? modelName,
    String? apiKey,
    bool? isDefault,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _manager.updateConfig(id,
          alias: alias,
          apiUrl: apiUrl,
          modelName: modelName,
          apiKey: apiKey,
          isDefault: isDefault);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteConfig(String id) async {
    state = const AsyncValue.loading();
    try {
      await _manager.deleteConfig(id);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final modelConfigFormProvider =
    StateNotifierProvider<ModelConfigFormNotifier, AsyncValue<void>>(
  (ref) =>
      ModelConfigFormNotifier(ref.watch(modelManagerProvider)),
);
