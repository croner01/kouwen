import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models.dart';
import 'providers/model_config_provider.dart';

class ModelConfigEditScreen extends ConsumerStatefulWidget {
  final ModelConfig? config; // null = create mode
  final String? existingApiKey;

  const ModelConfigEditScreen({super.key, this.config, this.existingApiKey});

  bool get isEditing => config != null;

  @override
  ConsumerState<ModelConfigEditScreen> createState() =>
      _ModelConfigEditScreenState();
}

class _ModelConfigEditScreenState
    extends ConsumerState<ModelConfigEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _aliasController;
  late final TextEditingController _apiUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  late bool _isDefault;

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _aliasController = TextEditingController(
        text: c?.alias ?? 'My DeepSeek');
    _apiUrlController = TextEditingController(
        text: c?.apiUrl ?? 'https://api.deepseek.com/anthropic');
    _modelController = TextEditingController(
        text: c?.modelName ?? 'deepseek-v4-pro');
    _apiKeyController = TextEditingController();
    _isDefault = c?.isDefault ?? true;
  }

  @override
  void dispose() {
    _aliasController.dispose();
    _apiUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(modelConfigFormProvider);
    final isEdit = widget.isEditing;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? '编辑模型' : '添加模型')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _aliasController,
              decoration: const InputDecoration(
                labelText: '配置名称',
                hintText: '如：我的DeepSeek',
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? '请输入' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _apiUrlController,
              decoration: const InputDecoration(
                labelText: 'API 地址',
                hintText: 'https://api.deepseek.com/anthropic',
                helperText: 'Anthropic 兼容的 API endpoint',
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? '请输入' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: '模型名称',
                hintText: 'deepseek-v4-pro',
                helperText: '如 deepseek-v4-pro, qwen-max, glm-4',
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? '请输入' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: isEdit ? '留空则不修改' : 'sk-xxxxxxxx',
                helperText: isEdit ? '输入新 Key 才会更新' : null,
              ),
              obscureText: true,
              validator: isEdit
                  ? null
                  : (v) => (v == null || v.isEmpty) ? '请输入' : null,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('设为默认'),
              subtitle: const Text('新对话自动使用此模型'),
              value: _isDefault,
              onChanged: (v) => setState(() => _isDefault = v),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: state.isLoading
                  ? null
                  : () async {
                      if (!_formKey.currentState!.validate()) return;
                      final notifier = ref.read(
                          modelConfigFormProvider.notifier);
                      final alias = _aliasController.text.trim();
                      final apiUrl = _apiUrlController.text
                          .trim()
                          .replaceAll(RegExp(r'/+$'), '');
                      final modelName =
                          _modelController.text.trim();
                      final apiKey =
                          _apiKeyController.text.trim();

                      if (isEdit) {
                        await notifier.updateConfig(
                          id: widget.config!.id,
                          alias: alias,
                          apiUrl: apiUrl,
                          modelName: modelName,
                          apiKey:
                              apiKey.isNotEmpty ? apiKey : null,
                          isDefault: _isDefault,
                        );
                      } else {
                        await notifier.addConfig(
                          alias: alias,
                          apiUrl: apiUrl,
                          modelName: modelName,
                          apiKey: apiKey,
                          isDefault: _isDefault,
                        );
                      }

                      if (!context.mounted) return;
                      ref.invalidate(modelConfigsProvider);
                      Navigator.of(context).pop();
                    },
              child: state.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator())
                  : Text(isEdit ? '保存修改' : '添加'),
            ),
          ],
        ),
      ),
    );
  }
}
