import 'package:dio/dio.dart';

class SearchResult {
  final String title;
  final String url;
  final String snippet;

  const SearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });
}

/// Web search service powered by Jina Reader — free, no API key needed.
///
/// Two endpoints:
///   - `s.jina.ai/{query}` — search the web, returns Markdown results
///   - `r.jina.ai/{url}`   — fetch a URL's content as clean Markdown
class WebSearchService {
  final Dio _dio;

  WebSearchService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  /// Search the web for [query] and return up to [count] results.
  /// Uses Jina Reader's search endpoint (s.jina.ai), free and keyless.
  Future<List<SearchResult>> search(String query, {int count = 5}) async {
    try {
      final resp = await _dio.get(
        'https://s.jina.ai/$query',
        options: Options(
          headers: {
            'Accept': 'text/plain',
            'User-Agent': 'KouWen/1.0',
          },
        ),
      );
      return _parseSearchResults(resp.data.toString(), query, count);
    } catch (_) {
      return [];
    }
  }

  /// Fetch the full content of [url] as clean Markdown.
  /// Uses Jina Reader's render endpoint (r.jina.ai), free and keyless.
  Future<String?> fetch(String url) async {
    try {
      final resp = await _dio.get(
        'https://r.jina.ai/$url',
        options: Options(
          headers: {
            'Accept': 'text/plain',
            'User-Agent': 'KouWen/1.0',
          },
        ),
      );
      if (resp.statusCode == 200) {
        return resp.data.toString();
      }
    } catch (_) {}
    return null;
  }

  /// Format search results + optional full content for LLM context injection.
  static String formatForLLM(
    List<SearchResult> results, {
    String? fullContent,
    String? sourceTitle,
  }) {
    final buf = StringBuffer();
    buf.writeln('以下是来自网络的实时搜索结果：');
    buf.writeln();
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buf.writeln('${i + 1}. ${r.title}');
      buf.writeln('   链接: ${r.url}');
      buf.writeln('   摘要: ${r.snippet}');
      buf.writeln();
    }
    if (fullContent != null && sourceTitle != null) {
      buf.writeln('---');
      buf.writeln('详细内容来自「$sourceTitle」：');
      buf.writeln(fullContent);
      buf.writeln('---');
    }
    buf.writeln('请基于以上实时信息回答用户问题，必要时引用来源。');
    return buf.toString();
  }

  /// Parse the plain-text / Markdown response from s.jina.ai into structured results.
  /// The response format is typically:
  ///   [Result #1]
  ///   Title: ...
  ///   URL: ...
  ///   Description: ...
  ///   ...
  List<SearchResult> _parseSearchResults(String body, String query, int maxCount) {
    final results = <SearchResult>[];
    final lines = body.split('\n');

    String? title, url, snippet;
    for (final line in lines) {
      if (line.startsWith('Title:') || line.startsWith('**Title:**')) {
        // Save previous result
        if (title != null) {
          results.add(SearchResult(
            title: title,
            url: url ?? '',
            snippet: snippet ?? '',
          ));
          if (results.length >= maxCount) break;
        }
        title = line.split(':').skip(1).join(':').trim().replaceAll('**', '');
        url = null;
        snippet = null;
      } else if (line.startsWith('URL:') || line.startsWith('**URL:**')) {
        url = line.split(':').skip(1).join(':').trim().replaceAll('**', '');
      } else if (line.startsWith('Description:') ||
          line.startsWith('**Description:**')) {
        snippet = line.split(':').skip(1).join(':').trim().replaceAll('**', '');
      }
    }
    // Last result
    if (title != null && results.length < maxCount) {
      results.add(SearchResult(
        title: title,
        url: url ?? '',
        snippet: snippet ?? '',
      ));
    }

    // Fallback: if parsing produced nothing, treat raw response as snippet
    if (results.isEmpty && body.trim().isNotEmpty) {
      results.add(SearchResult(
        title: query,
        url: '',
        snippet: body.trim().replaceAll('\n', ' '),
      ));
    }

    return results;
  }
}
