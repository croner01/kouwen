import 'package:flutter_test/flutter_test.dart';
import 'package:kouwen/engine/prompt_builder.dart';
import 'package:kouwen/data/models.dart';

void main() {
  group('PromptBuilder', () {
    test('buildMessages includes system prompt and history', () {
      final messages = PromptBuilder.buildMessages(
        systemPrompt: 'You are a legal expert.',
        userInput: 'Contract question',
        history: [
          Message(
            id: '1',
            conversationId: 'c1',
            role: MessageRole.user,
            content: 'Hello',
            createdAt: DateTime.now(),
          ),
          Message(
            id: '2',
            conversationId: 'c1',
            role: MessageRole.assistant,
            content: 'Hi! How can I help?',
            createdAt: DateTime.now(),
          ),
        ],
        maxHistoryRounds: 20,
      );

      final systemMsg = messages.first;
      expect(systemMsg['role'], 'system');
      expect(systemMsg['content'], 'You are a legal expert.');

      final userMsg = messages.last;
      expect(userMsg['role'], 'user');
      expect(userMsg['content'], 'Contract question');
    });

    test('buildMessages limits history to maxHistoryRounds', () {
      final history = List.generate(
        30,
        (i) => Message(
          id: '$i',
          conversationId: 'c1',
          role: i.isEven ? MessageRole.user : MessageRole.assistant,
          content: 'Message$i',
          createdAt: DateTime.now(),
        ),
      );

      final messages = PromptBuilder.buildMessages(
        systemPrompt: 'system',
        userInput: 'current',
        history: history,
        maxHistoryRounds: 5,
      );

      // 1 system + 10 history + 1 user = 12
      expect(messages.length, 12);
      expect(messages.first['role'], 'system');
      expect(messages.last['role'], 'user');
      expect(messages.last['content'], 'current');
    });

    test('buildMessages with empty history works', () {
      final messages = PromptBuilder.buildMessages(
        systemPrompt: 'system',
        userInput: 'hello',
      );

      expect(messages.length, 2);
      expect(messages.first['role'], 'system');
      expect(messages.last['role'], 'user');
    });

    test('buildMessages with templateContent wraps user input', () {
      final messages = PromptBuilder.buildMessages(
        systemPrompt: 'system',
        userInput: '分析这段代码',
        templateContent: '请作为代码审查专家：',
      );

      final userMsg = messages.last;
      expect(userMsg['content'],
          contains('请作为代码审查专家：'));
      expect(userMsg['content'], contains('分析这段代码'));
    });

    test('buildMessages skips system messages in history', () {
      final history = [
        Message(
          id: '1',
          conversationId: 'c1',
          role: MessageRole.system,
          content: 'old system',
          createdAt: DateTime.now(),
        ),
        Message(
          id: '2',
          conversationId: 'c1',
          role: MessageRole.user,
          content: 'user msg',
          createdAt: DateTime.now(),
        ),
        Message(
          id: '3',
          conversationId: 'c1',
          role: MessageRole.assistant,
          content: 'assistant msg',
          createdAt: DateTime.now(),
        ),
      ];

      final messages = PromptBuilder.buildMessages(
        systemPrompt: 'new system',
        userInput: 'current',
        history: history,
      );

      // Should have: system + user + assistant + user = 4
      // No duplicate system messages from history
      expect(messages.length, 4);
      expect(messages[0]['role'], 'system');
      expect(messages[0]['content'], 'new system');
      expect(messages[1]['role'], 'user');
      expect(messages[1]['content'], 'user msg');
      expect(messages[2]['role'], 'assistant');
      expect(messages[3]['role'], 'user');
      expect(messages[3]['content'], 'current');
    });
  });
}
