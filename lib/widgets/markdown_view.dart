import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

class MarkdownView extends StatelessWidget {
  final String content;
  final bool isDark;

  const MarkdownView({super.key, required this.content, this.isDark = false});

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);
    final codeBg =
        isDark ? const Color(0xFF0F172A) : const Color(0xFF1E293B);

    return MarkdownBody(
      data: content,
      selectable: true,
      builders: {
        'code': CodeBlockBuilder(isDark: isDark),
      },
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: 15, height: 1.6, color: textColor),
        h1: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w700, color: textColor),
        h2: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w600, color: textColor),
        h3: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
        code: TextStyle(
          backgroundColor:
              isDark ? Colors.grey.shade800 : Colors.grey.shade100,
          fontSize: 13,
          fontFamily: 'monospace',
          color: isDark ? const Color(0xFFC3E88D) : const Color(0xFF1E293B),
        ),
        codeblockDecoration: BoxDecoration(
          color: codeBg,
          borderRadius: BorderRadius.circular(8),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
              width: 3,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12),
      ),
    );
  }
}

/// Custom code block builder with dark background and monospace styling
class CodeBlockBuilder extends MarkdownElementBuilder {
  final bool isDark;

  CodeBlockBuilder({this.isDark = false});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final textContent = element.textContent;
    final bg = isDark ? const Color(0xFF0F172A) : const Color(0xFF1E293B);
    const fg = Color(0xFFC3E88D);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          textContent,
          style: const TextStyle(
            color: fg,
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
