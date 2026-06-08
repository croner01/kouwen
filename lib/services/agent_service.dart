import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';

/// Events emitted by the Agent SSE stream.
sealed class AgentEvent {}

class TextDeltaEvent extends AgentEvent {
  final String content;
  TextDeltaEvent(this.content);
}

class ToolUseEvent extends AgentEvent {
  final String id;
  final String name;
  final Map<String, dynamic> input;
  ToolUseEvent({required this.id, required this.name, required this.input});
}

class ToolResultEvent extends AgentEvent {
  final String id;
  final String name;
  final Map<String, dynamic> result;
  ToolResultEvent({required this.id, required this.name, required this.result});
}

class AgentDoneEvent extends AgentEvent {
  final int turns;
  final bool truncated;
  AgentDoneEvent({required this.turns, this.truncated = false});
}

class AgentErrorEvent extends AgentEvent {
  final String message;
  AgentErrorEvent(this.message);
}

/// SSE streaming client for the KouWen Agent Service.
///
/// The Agent backend handles tool-use loop (sandbox, web search) internally
/// and streams text + tool events back to the App.
class AgentService {
  final Dio _dio;
  final String _baseUrl;

  AgentService({required String baseUrl, Dio? dio})
      : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(minutes: 5);
  }

  String? _jwtToken;

  void setAuth(String token) => _jwtToken = token;
  void clearAuth() => _jwtToken = null;

  Future<bool> healthCheck() async {
    try {
      final resp = await _dio.get('$_baseUrl/api/v1/health');
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Stream agent events via SSE.
  Stream<AgentEvent> chat({
    required String apiKey,
    String baseUrl = 'https://api.deepseek.com/anthropic',
    String model = 'deepseek-v4-pro',
    required List<Map<String, String>> messages,
    String? systemPrompt,
    int maxTokens = 16384,
    int maxTurns = 15,
    bool webSearchEnabled = false,
    CancelToken? cancelToken,
  }) async* {
    final response = await _dio.post(
      '$_baseUrl/api/v1/agent/chat',
      data: {
        'api_key': apiKey,
        'base_url': baseUrl,
        'model': model,
        'messages': messages,
        if (systemPrompt != null) 'system': systemPrompt,
        'max_tokens': maxTokens,
        'max_turns': maxTurns,
        'web_search': webSearchEnabled,
      },
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Accept': 'text/event-stream',
          if (_jwtToken != null) 'Authorization': 'Bearer $_jwtToken',
        },
      ),
      cancelToken: cancelToken,
    );

    if (response.data is! ResponseBody) {
      yield AgentErrorEvent('服务器返回了非流式响应，请检查后端部署');
      return;
    }

    final stream = (response.data as ResponseBody).stream;
    String buffer = '';

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk, allowMalformed: true);
      // SSE: events separated by \n\n
      while (buffer.contains('\n\n')) {
        final idx = buffer.indexOf('\n\n');
        final raw = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 2);

        String? eventType;
        String? data;
        for (final line in raw.split('\n')) {
          if (line.startsWith('event: ')) {
            eventType = line.substring(7).trim();
          } else if (line.startsWith('data: ')) {
            data = line.substring(6).trim();
          }
        }

        if (eventType == null || data == null) continue;

        try {
          switch (eventType) {
            case 'text_delta':
              final json = jsonDecode(data) as Map<String, dynamic>;
              yield TextDeltaEvent(json['content'] as String);
            case 'tool_use':
              final json = jsonDecode(data) as Map<String, dynamic>;
              yield ToolUseEvent(
                id: json['id'] as String,
                name: json['name'] as String,
                input: json['input'] as Map<String, dynamic>,
              );
            case 'tool_result':
              final json = jsonDecode(data) as Map<String, dynamic>;
              yield ToolResultEvent(
                id: json['id'] as String,
                name: json['name'] as String,
                result: json['result'] as Map<String, dynamic>,
              );
            case 'done':
              final json = jsonDecode(data) as Map<String, dynamic>;
              yield AgentDoneEvent(
                turns: json['turns'] as int,
                truncated: (json['truncated'] as bool?) ?? false,
              );
            case 'error':
              final json = jsonDecode(data) as Map<String, dynamic>;
              yield AgentErrorEvent(json['message'] as String);
          }
        } catch (_) {
          // Skip malformed SSE events
        }
      }
    }

    // Flush: stream ended with unparsed data — connection was interrupted
    if (buffer.trim().isNotEmpty) {
      yield AgentErrorEvent('连接中断，回复可能不完整');
    }
  }
}
