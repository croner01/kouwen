import '../data/models.dart';

class PromptBuilder {
  static List<Map<String, String>> buildMessages({
    required String systemPrompt,
    required String userInput,
    List<Message> history = const [],
    int maxHistoryRounds = 20,
    String? templateContent,
  }) {
    final messages = <Map<String, String>>[];

    messages.add({'role': 'system', 'content': systemPrompt});

    final recentHistory = _getRecentHistory(history, maxHistoryRounds);
    for (final msg in recentHistory) {
      if (msg.role == MessageRole.system) continue;
      messages.add({
        'role': msg.role.name,
        'content': msg.content,
      });
    }

    var finalInput = userInput;
    if (templateContent != null) {
      finalInput = '$templateContent\n\n$userInput';
    }
    messages.add({'role': 'user', 'content': finalInput});

    return messages;
  }

  static List<Message> _getRecentHistory(
      List<Message> history, int maxRounds) {
    if (history.isEmpty) return [];
    final maxMessages = maxRounds * 2;
    if (history.length <= maxMessages) return history;
    return history.sublist(history.length - maxMessages);
  }
}
