import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

class MarkdownView extends StatelessWidget {
  final String content;
  final bool isDark;

  const MarkdownView({super.key, required this.content, this.isDark = false});

  /// Pre-process LaTeX math into readable plain-text / Unicode, then strip
  /// remaining delimiters so the output renders cleanly in Markdown.
  ///
  /// Handles three common patterns from LLM output:
  ///   1. Raw LaTeX commands: \frac{a}{b}, \sqrt{x}, \sum_{i=1}^{n}, …
  ///   2. Inline math delimiters: \( ... \)
  ///   3. Display math delimiters: $$ ... $$
  static String _preprocessLatex(String input) {
    // ── Step 1: Convert raw LaTeX commands (not inside delimiters) ──
    input = input.replaceAllMapped(
      RegExp(r'\\frac\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}'),
      (m) => '(${m.group(1)!}/${m.group(2)!})',
    );
    input = input.replaceAllMapped(
      RegExp(r'\\sqrt\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}'),
      (m) => '√(${m.group(1)!})', // √(...)
    );
    input = input.replaceAllMapped(
      RegExp(r'\\sqrt\[([^\]]+)\]\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}'),
      (m) => '∛(${m.group(2)!})', // ∛(...) — for cube root etc, use generic
    );
    input = input.replaceAllMapped(
      RegExp(r'\\sum_\{([^}]*)\}\^\{([^}]*)\}'),
      (m) => 'Σ(${m.group(1)!}→${m.group(2)!})', // Σ(lower→upper)
    );
    input = input.replaceAllMapped(
      RegExp(r'\\int_\{([^}]*)\}\^\{([^}]*)\}'),
      (m) => '∫(${m.group(1)!}→${m.group(2)!})', // ∫(lower→upper)
    );

    // Common LaTeX symbols → Unicode
    const latexToUnicode = {
      r'\pm': '±',       // ±
      r'\times': '×',    // ×
      r'\div': '÷',      // ÷
      r'\cdot': '·',     // ·
      r'\leq': '≤',      // ≤
      r'\geq': '≥',      // ≥
      r'\neq': '≠',      // ≠
      r'\approx': '≈',   // ≈
      r'\infty': '∞',    // ∞
      r'\alpha': 'α',    // α
      r'\beta': 'β',     // β
      r'\gamma': 'γ',    // γ
      r'\delta': 'δ',    // δ
      r'\epsilon': 'ε',  // ε
      r'\pi': 'π',       // π
      r'\sigma': 'σ',    // σ
      r'\omega': 'ω',    // ω
      r'\mu': 'μ',       // μ
      r'\lambda': 'λ',   // λ
      r'\theta': 'θ',    // θ
      r'\rho': 'ρ',      // ρ
      r'\to': '→',       // →
      r'\rightarrow': '→', // →
      r'\leftarrow': '←', // ←
      r'\Rightarrow': '⇒', // ⇒
      r'\Leftrightarrow': '⇔', // ⇔
      r'\ldots': '…',    // …
      r'\cdots': '⋯',    // ⋯
      r'\ge': '≥',       // ≥
      r'\le': '≤',       // ≤
      r'\ne': '≠',       // ≠
      r'\sim': '∼',      // ∼
      r'\propto': '∝',   // ∝
      r'\partial': '∂',  // ∂
      r'\nabla': '∇',    // ∇
      r'\forall': '∀',   // ∀
      r'\exists': '∃',   // ∃
      r'\in': '∈',       // ∈
      r'\notin': '∉',    // ∉
      r'\subset': '⊂',   // ⊂
      r'\supset': '⊃',   // ⊃
      r'\cup': '∪',      // ∪
      r'\cap': '∩',      // ∩
      r'\emptyset': '∅', // ∅
      r'\angle': '∠',    // ∠
      r'\triangle': '△', // △
      r'\equiv': '≡',    // ≡
      r'\cong': '≅',     // ≅
      r'\perp': '⟂',     // ⟂
      r'\parallel': '∥', // ∥
      r'\circ': '∘',     // ∘
      r'\star': '★',     // ★
    };
    for (final entry in latexToUnicode.entries) {
      input = input.replaceAll(entry.key, entry.value);
    }

    // ── Step 2: Strip inline math delimiters \( ... \) → keep content in backticks ──
    input = input.replaceAllMapped(
      RegExp(r'\\\((.+?)\\\)', dotAll: true),
      (m) => ' `${m.group(1)!.trim()}` ',
    );

    // ── Step 3: Display math $$ ... $$ → fenced code block ──
    input = input.replaceAllMapped(
      RegExp(r'\$\$(.+?)\$\$', dotAll: true),
      (m) => '\n```\n${m.group(1)!.trim()}\n```\n',
    );

    return input;
  }

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);
    final codeBg =
        isDark ? const Color(0xFF0F172A) : const Color(0xFF1E293B);

    final processed = _preprocessLatex(content);

    return MarkdownBody(
      data: processed,
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
