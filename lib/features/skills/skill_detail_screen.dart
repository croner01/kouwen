import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../../providers.dart';
import '../../engine/skill_parser.dart';
import '../../engine/skill_intro.dart';
import '../chat/chat_screen.dart';
import 'skill_edit_screen.dart';

/// Detail page shown when tapping a skill — shows Chinese name, description,
/// usage guide, and sample questions before entering chat.
class SkillDetailScreen extends ConsumerStatefulWidget {
  final String skillId;

  const SkillDetailScreen({super.key, required this.skillId});

  @override
  ConsumerState<SkillDetailScreen> createState() => _SkillDetailScreenState();
}

class _SkillDetailScreenState extends ConsumerState<SkillDetailScreen> {
  Skill? _skill;
  SkillIntro? _intro;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = SkillRepository(ref.read(dbProvider));
      final skill = await repo.getSkillById(widget.skillId);
      if (skill == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      // Try to parse the YAML content for richer info
      ParsedSkill? parsed;
      try {
        parsed = SkillParser.parse(skill.yamlContent);
      } catch (_) {}

      final intro = SkillIntroBuilder.build(
        rawName: skill.name,
        parsed: parsed,
        rawYaml: skill.yamlContent,
      );

      if (mounted) {
        setState(() {
          _skill = skill;
          _intro = intro;
          _loading = false;
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('SkillDetailScreen._load error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_intro?.chineseName ?? _skill?.name ?? '技能详情'),
        actions: [
          if (_skill != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑技能',
              onPressed: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => SkillEditScreen(skillId: _skill!.id),
                  ),
                );
                if (changed == true) _load();
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _skill == null
              ? const Center(child: Text('技能未找到'))
              : _buildContent(context),
      bottomNavigationBar: _skill == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () {
                    // Replace current route with chat screen
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) =>
                            ChatScreen(autoLoadSkillId: _skill!.id),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble),
                  label: const Text('开始对话'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final intro = _intro!;
    final skill = _skill!;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Header card
        _HeaderCard(skill: skill, intro: intro),
        const SizedBox(height: 20),

        // Description section
        if (intro.description.isNotEmpty) ...[
          _SectionTitle(title: '功能介绍', icon: Icons.info_outline),
          const SizedBox(height: 8),
          Text(
            intro.description,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade800,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Usage guide
        if (intro.usage.isNotEmpty) ...[
          _SectionTitle(title: '使用说明', icon: Icons.menu_book_outlined),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              intro.usage,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Sample questions
        if (intro.sampleQuestions.isNotEmpty) ...[
          _SectionTitle(title: '试试这样问', icon: Icons.lightbulb_outline),
          const SizedBox(height: 8),
          ...intro.sampleQuestions.map((q) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () {
                    // Enter chat with this question pre-filled
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          autoLoadSkillId: skill.id,
                          initialMessage: q,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 16,
                            color: const Color(0xFF4F46E5)
                                .withValues(alpha: 0.6)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            q,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF4F46E5),
                              height: 1.3,
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios,
                            size: 12,
                            color: const Color(0xFF4F46E5)
                                .withValues(alpha: 0.4)),
                      ],
                    ),
                  ),
                ),
              )),
          const SizedBox(height: 24),
        ],

        // Meta info
        _SectionTitle(title: '技能信息', icon: Icons.code),
        const SizedBox(height: 8),
        _MetaRow('原始名称', skill.name),
        _MetaRow('分类', skill.category),
        if (skill.author != null) _MetaRow('来源', skill.author!),
        _MetaRow('版本', skill.version),
        _MetaRow('安装时间', '${skill.installedAt.year}-'
            '${skill.installedAt.month.toString().padLeft(2, '0')}-'
            '${skill.installedAt.day.toString().padLeft(2, '0')}'),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Skill skill;
  final SkillIntro intro;

  const _HeaderCard({required this.skill, required this.intro});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF4F46E5),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  intro.chineseName.isNotEmpty
                      ? intro.chineseName[0]
                      : skill.name[0],
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              intro.chineseName,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              skill.name,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white70,
                fontFamily: 'monospace',
              ),
            ),
            if (skill.isCollection) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('技能集合',
                    style: TextStyle(fontSize: 12, color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF4F46E5)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF4F46E5),
          ),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
