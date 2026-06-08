import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../engine/skill_parser.dart';
import '../../engine/skill_router.dart';
import 'providers/skill_provider.dart';

/// Dual-mode skill editor: form view + raw YAML view.
class SkillEditScreen extends ConsumerStatefulWidget {
  final String skillId;

  const SkillEditScreen({super.key, required this.skillId});

  @override
  ConsumerState<SkillEditScreen> createState() => _SkillEditScreenState();
}

class _SkillEditScreenState extends ConsumerState<SkillEditScreen> {
  bool _loading = true;
  Skill? _skill;

  // Form fields
  final _nameCtrl = TextEditingController();
  final _versionCtrl = TextEditingController();
  final _iconCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _welcomeCtrl = TextEditingController();
  final _promptCtrl = TextEditingController();
  final _yamlCtrl = TextEditingController();

  String _category = '通用';
  final _sampleQuestions = <String>[];
  final _questionCtrl = TextEditingController();

  // Edit mode toggle
  bool _rawMode = false;
  bool _saving = false;
  String? _error;

  static const _categories = ['通用', '科技', '设计', '文档', '法律', '医疗', '财经', '教育'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _versionCtrl.dispose();
    _iconCtrl.dispose();
    _descCtrl.dispose();
    _welcomeCtrl.dispose();
    _promptCtrl.dispose();
    _yamlCtrl.dispose();
    _questionCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = SkillRepository(ref.read(dbProvider));
    var skill = await repo.getSkillById(widget.skillId);
    if (skill == null || !mounted) return;

    // If yamlContent is empty, try backend API fallback
    if (skill.yamlContent.isEmpty) {
      try {
        final api = ref.read(skillApiServiceProvider);
        final backendSkills = await api.listSkills();
        final bs = backendSkills.where((s) => s.name == skill!.name).firstOrNull;
        if (bs != null && bs.yamlContent.isNotEmpty) {
          await repo.updateSkillYamlContent(widget.skillId, bs.yamlContent);
          skill = await repo.getSkillById(widget.skillId);
        }
      } catch (_) {}
    }

    if (skill == null || !mounted) return; // re-check after potential reassignment

    ParsedSkill? parsed;
    try {
      parsed = SkillParser.parse(skill.yamlContent);
    } catch (_) {}

    setState(() {
      _skill = skill;
      _loading = false;
      _nameCtrl.text = parsed?.name ?? skill!.name;
      _versionCtrl.text = parsed?.version ?? skill!.version;
      _iconCtrl.text = parsed?.icon ?? '🤖';
      _category = parsed?.category ?? skill!.category;
      _descCtrl.text = parsed?.description ?? skill!.description ?? '';
      _welcomeCtrl.text = parsed?.welcomeMessage ?? '';
      _promptCtrl.text = parsed?.systemPrompt ?? '';
      _sampleQuestions
        ..clear()
        ..addAll(parsed?.sampleQuestions ?? []);
      _yamlCtrl.text = skill!.yamlContent;
    });
  }

  Future<void> _save() async {
    if (_skill == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      String yaml;
      String name;
      String version;
      String category;
      String? description;

      if (_rawMode) {
        // Raw YAML mode — parse to validate and extract fields
        try {
          final parsed = SkillParser.parse(_yamlCtrl.text);
          name = parsed.name;
          version = parsed.version;
          category = parsed.category;
          description = parsed.description;
          yaml = _yamlCtrl.text;
        } on SkillParseException catch (e) {
          setState(() {
            _error = 'YAML 格式错误: ${e.message}';
            _saving = false;
          });
          return;
        }
      } else {
        // Form mode — reconstruct YAML from fields
        name = _nameCtrl.text.trim();
        version = _versionCtrl.text.trim();
        category = _category;
        description = _descCtrl.text.trim();

        if (name.isEmpty) {
          setState(() { _error = '技能名称不能为空'; _saving = false; });
          return;
        }
        if (version.isEmpty) {
          setState(() { _error = '版本号不能为空'; _saving = false; });
          return;
        }
        if (category.isEmpty) {
          setState(() { _error = '分类不能为空'; _saving = false; });
          return;
        }

        yaml = _buildYaml(
          name: name,
          version: version,
          description: description,
          icon: _iconCtrl.text.trim(),
          category: category,
          systemPrompt: _promptCtrl.text,
          welcomeMessage: _welcomeCtrl.text.trim(),
          sampleQuestions: _sampleQuestions,
        );

        // Validate reconstructed YAML
        try {
          SkillParser.parse(yaml);
        } on SkillParseException catch (e) {
          setState(() {
            _error = '生成的 YAML 无效: ${e.message}';
            _saving = false;
          });
          return;
        }
      }

      // Update DB
      final repo = SkillRepository(ref.read(dbProvider));
      await repo.updateSkill(
        _skill!.id,
        name: name,
        version: version,
        author: _skill!.author,
        description: description,
        category: category,
        yamlContent: yaml,
      );

      // Invalidate providers and router cache so UI refreshes
      ref.invalidate(installedSkillsProvider);
      ref.invalidate(topLevelSkillsProvider);
      SkillRouter.invalidateCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('技能已更新'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() { _error = '保存失败: $e'; });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Build YAML string from form fields.
  String _buildYaml({
    required String name,
    required String version,
    String? description,
    String icon = '🤖',
    required String category,
    String systemPrompt = '',
    String welcomeMessage = '',
    List<String> sampleQuestions = const [],
  }) {
    final buf = StringBuffer();
    buf.writeln('name: $name');
    buf.writeln('version: $version');
    if (description != null && description.isNotEmpty) {
      buf.writeln('description: $description');
    }
    buf.writeln('icon: $icon');
    buf.writeln('category: $category');
    // Write system_prompt with proper block scalar for multiline,
    // empty string otherwise (no trailing space).
    if (systemPrompt.contains('\n')) {
      buf.writeln('system_prompt: |');
      for (final line in systemPrompt.split('\n')) {
        buf.writeln('  $line');
      }
    } else if (systemPrompt.isNotEmpty) {
      buf.writeln('system_prompt: $systemPrompt');
    }
    // welcome_message needs block scalar if it contains newlines
    if (welcomeMessage.contains('\n')) {
      buf.writeln('welcome_message: |');
      for (final line in welcomeMessage.split('\n')) {
        buf.writeln('  $line');
      }
    } else if (welcomeMessage.isNotEmpty) {
      buf.writeln('welcome_message: $welcomeMessage');
    }
    if (sampleQuestions.isNotEmpty) {
      buf.writeln('sample_questions:');
      for (final q in sampleQuestions) {
        // Quote the value if it starts with a special YAML character
        final quoted = (q.startsWith('- ') || q.startsWith('>') || q.startsWith('|') ||
                q.startsWith('&') || q.startsWith('*') || q.startsWith('!') ||
                q.startsWith('?') || q.contains(': '))
            ? '"${q.replaceAll('"', '\\"')}"'
            : q;
        buf.writeln('  - $quoted');
      }
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('编辑技能')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_skill == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('编辑技能')),
        body: const Center(child: Text('技能未找到')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑技能'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check, size: 18),
            label: const Text('保存'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Mode toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('表单编辑'), icon: Icon(Icons.edit_note, size: 18)),
                ButtonSegment(value: true, label: Text('原始 YAML'), icon: Icon(Icons.code, size: 18)),
              ],
              selected: {_rawMode},
              onSelectionChanged: (v) {
                if (_rawMode != v.first) _switchMode(v.first);
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          // Error banner
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.red.shade50,
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: TextStyle(fontSize: 13, color: Colors.red.shade900))),
                  GestureDetector(child: Icon(Icons.close, size: 16, color: Colors.red.shade400), onTap: () => setState(() => _error = null)),
                ],
              ),
            ),
          // Editor body
          Expanded(
            child: _rawMode ? _buildRawEditor() : _buildFormEditor(),
          ),
        ],
      ),
    );
  }

  void _switchMode(bool toRaw) {
    if (toRaw) {
      // Form → YAML: rebuild YAML from form data
      final yaml = _buildYaml(
        name: _nameCtrl.text.trim(),
        version: _versionCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        icon: _iconCtrl.text.trim(),
        category: _category,
        systemPrompt: _promptCtrl.text,
        welcomeMessage: _welcomeCtrl.text.trim(),
        sampleQuestions: _sampleQuestions,
      );
      _yamlCtrl.text = yaml;
    } else {
      // YAML → Form: parse YAML to populate fields
      try {
        final parsed = SkillParser.parse(_yamlCtrl.text);
        setState(() {
          _nameCtrl.text = parsed.name;
          _versionCtrl.text = parsed.version;
          _iconCtrl.text = parsed.icon;
          _category = parsed.category;
          _descCtrl.text = parsed.description ?? '';
          _welcomeCtrl.text = parsed.welcomeMessage;
          _promptCtrl.text = parsed.systemPrompt;
          _sampleQuestions
            ..clear()
            ..addAll(parsed.sampleQuestions);
        });
      } catch (e) {
        setState(() => _error = 'YAML 解析失败，无法切换到表单模式');
        return;
      }
    }
    setState(() { _rawMode = toRaw; _error = null; });
  }

  // ── Form Editor ──

  Widget _buildFormEditor() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _FieldLabel('技能名称'),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(hintText: '输入技能名称'),
        ),
        const SizedBox(height: 16),

        _FieldLabel('版本'),
        TextField(
          controller: _versionCtrl,
          decoration: const InputDecoration(hintText: '1.0.0'),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FieldLabel('图标 (emoji)'),
                  TextField(
                    controller: _iconCtrl,
                    decoration: const InputDecoration(hintText: '🤖'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FieldLabel('分类'),
                  DropdownButtonFormField<String>(
                    value: _categories.contains(_category) ? _category : _categories.first,
                    items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setState(() => _category = v ?? '通用'),
                    decoration: const InputDecoration(isDense: true),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _FieldLabel('描述'),
        TextField(
          controller: _descCtrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '技能描述'),
        ),
        const SizedBox(height: 16),

        _FieldLabel('欢迎语'),
        TextField(
          controller: _welcomeCtrl,
          maxLines: 2,
          decoration: const InputDecoration(hintText: '你好！有什么可以帮你的？'),
        ),
        const SizedBox(height: 16),

        _FieldLabel('系统提示 (System Prompt)'),
        TextField(
          controller: _promptCtrl,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: '你是...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        _FieldLabel('示例问题'),
        ..._sampleQuestions.asMap().entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InputChip(
            label: Text(e.value, style: const TextStyle(fontSize: 13)),
            onDeleted: () => setState(() => _sampleQuestions.removeAt(e.key)),
          ),
        )),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _questionCtrl,
                decoration: const InputDecoration(hintText: '添加示例问题...', isDense: true),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () {
                final text = _questionCtrl.text.trim();
                if (text.isNotEmpty) {
                  setState(() => _sampleQuestions.add(text));
                  _questionCtrl.clear();
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Raw YAML Editor ──

  Widget _buildRawEditor() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _yamlCtrl,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
    );
  }
}
