import 'dart:convert';
import 'package:dio/dio.dart';

class ApiException implements Exception {
  final String message;
  final bool isRetryable;

  const ApiException(this.message, {this.isRetryable = false});

  @override
  String toString() => message;
}

class ApiService {
  final Dio _dio;
  static const _maxRetries = 3;
  static const _connectTimeout = Duration(seconds: 15);
  static const _receiveTimeout = Duration(seconds: 120);

  ApiService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = _connectTimeout;
    _dio.options.receiveTimeout = _receiveTimeout;
    _dio.options.sendTimeout = _connectTimeout;
  }

  /// Auto-detect the search parameter name for model-native web search.
  /// Returns null if the model doesn't support native search.
  static Map<String, dynamic>? detectSearchParam(String modelName) {
    final name = modelName.toLowerCase();
    if (name.contains('deepseek')) return {'enable_search': true};
    if (name.contains('qwen') || name.contains('tongyi')) {
      return {'enable_search': true};
    }
    if (name.contains('kimi') || name.contains('moonshot')) {
      return {'use_search': true};
    }
    return null;
  }

  Stream<String> chatStream({
    required String apiUrl,
    required String apiKey,
    required String modelName,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxRetries = _maxRetries,
    CancelToken? cancelToken,
    Map<String, dynamic>? searchParam,
  }) async* {
    int attempt = 0;
    Object? lastError;

    while (attempt < maxRetries) {
      attempt++;
      try {
        yield* _chatStreamOnce(
          apiUrl: apiUrl,
          apiKey: apiKey,
          modelName: modelName,
          messages: messages,
          temperature: temperature,
          cancelToken: cancelToken,
          searchParam: searchParam,
        );
        return; // success
      } on DioException catch (e) {
        lastError = e;
        final errMsg = _parseDioError(e);
        // Retry on connection errors, timeouts, and server errors
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            (e.response != null && e.response!.statusCode! >= 500)) {
          if (attempt < maxRetries) {
            await Future.delayed(Duration(seconds: attempt));
            continue;
          }
        }
        throw ApiException(errMsg, isRetryable: false);
      } catch (e) {
        lastError = e;
        throw ApiException('请求异常: $e');
      }
    }

    throw ApiException(
      '请求失败，已重试 $maxRetries 次。\n原因: ${_parseDioError(lastError as DioException)}',
    );
  }

  Stream<String> _chatStreamOnce({
    required String apiUrl,
    required String apiKey,
    required String modelName,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    CancelToken? cancelToken,
    Map<String, dynamic>? searchParam,
  }) async* {
    // Normalize: strip trailing slash, add https:// if missing
    var baseUrl = apiUrl.endsWith('/')
        ? apiUrl.substring(0, apiUrl.length - 1)
        : apiUrl;
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'https://$baseUrl';
    }
    final response = await _dio.post(
      '$baseUrl/v1/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'User-Agent': 'KouWen/1.0',
          'Accept': 'application/json',
        },
        responseType: ResponseType.stream,
      ),
      cancelToken: cancelToken,
      data: {
        'model': modelName,
        'messages': messages,
        'stream': true,
        'temperature': temperature,
        if (searchParam != null) ...searchParam,
      },
    );

    // If the server returned a non-streaming response (e.g. JSON error body),
    // response.data will be a Map rather than a ResponseBody with .stream.
    // Throw a clear error so the caller can surface it instead of a cryptic TypeError.
    if (response.data is! ResponseBody) {
      throw ApiException(
        '模型不支持流式响应或返回了非预期的响应格式。'
        '请检查 API 地址和模型名称是否正确。',
      );
    }

    final body = response.data as ResponseBody;
    await for (final chunk in body.stream) {
      final data = utf8.decode(chunk as List<int>);
      for (final line in data.split('\n')) {
        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6).trim();
          if (jsonStr == '[DONE]') return;
          if (jsonStr.isEmpty) continue;
          try {
            final json = jsonDecode(jsonStr) as Map<String, dynamic>;
            final choices = json['choices'] as List<dynamic>?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              final content = delta?['content'] as String?;
              if (content != null && content.isNotEmpty) {
                yield content;
              }
            }
          } catch (_) {
            // Skip malformed chunks
          }
        }
      }
    }
  }

  String _parseDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
        return '无法连接到服务器，请检查网络和 API 地址';
      case DioExceptionType.connectionTimeout:
        return '连接超时，请稍后重试';
      case DioExceptionType.receiveTimeout:
        return '响应超时，模型可能正在处理大量请求';
      case DioExceptionType.sendTimeout:
        return '发送超时';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        if (code == 401) return 'API Key 无效，请检查配置';
        if (code == 403) return 'API Key 无权限访问该模型';
        if (code == 429) return '请求过于频繁，请稍后重试';
        if (code >= 500) return '服务器错误 ($code)，正在重试...';
        return '服务器返回错误 ($code)';
      default:
        return '网络异常: ${e.message}';
    }
  }
}
