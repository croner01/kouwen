import 'package:flutter/material.dart';
import '../../../data/models.dart';

class SkillCard extends StatelessWidget {
  final Skill skill;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool isInstalled;

  const SkillCard({
    super.key,
    required this.skill,
    this.onTap,
    this.onDelete,
    this.isInstalled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        skill.name.isNotEmpty
                            ? skill.name[0]
                            : 'S',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          skill.name,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                        ),
                        if (skill.author != null)
                          Text(
                            skill.author!,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500),
                          ),
                      ],
                    ),
                  ),
                  if (isInstalled && onDelete != null) ...[
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 18,
                          color: Colors.grey.shade400),
                      onPressed: onDelete,
                      constraints: const BoxConstraints(
                          minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                    ),
                  ] else if (!isInstalled)
                    FilledButton(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('安装',
                          style: TextStyle(fontSize: 13)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  skill.category,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
