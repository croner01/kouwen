import 'package:dio/dio.dart';

/// Result from executing a script in the sandbox.
class SandboxResult {
  final String stdout;
  final String stderr;
  final int exitCode;
  final double executionTime;
  final bool truncated;

  const SandboxResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.executionTime,
    required this.truncated,
  });

  bool get ok => exitCode == 0 && stderr.isEmpty;

  factory SandboxResult.fromJson(Map<String, dynamic> json) {
    return SandboxResult(
      stdout: (json['stdout'] as String?) ?? '',
      stderr: (json['stderr'] as String?) ?? '',
      exitCode: (json['exit_code'] as int?) ?? -1,
      executionTime: (json['execution_time'] as num?)?.toDouble() ?? 0,
      truncated: (json['truncated'] as bool?) ?? false,
    );
  }
}

/// Calls the KouWen Sandbox server to execute Python/Bash scripts.
///
/// The sandbox runs as a k8s pod in the kouwen namespace (NodePort 30081).
/// Data packages (baostock, akshare) are pre-installed for A-share/global
/// market data fetching. Accessed via the Cloudflare tunnel or server URL.
class SandboxService {
  final Dio _dio;
  final String _baseUrl;

  SandboxService({
    required String baseUrl,
    Dio? dio,
  })  : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 130); // max script timeout + buffer
  }

  /// Default sandbox server URL — fallback when no user-configured URL.
  static const defaultUrl = 'https://none-ringtone-adaptor-materials.trycloudflare.com';

  /// Try the given [preferredUrl] first, then fall back to [defaultUrl].
  static Future<String> discoverUrl({Dio? dio, String? preferredUrl}) async {
    final client = dio ?? Dio();
    client.options.connectTimeout = const Duration(seconds: 3);
    final candidates = [
      if (preferredUrl != null) preferredUrl,
      defaultUrl,
    ];
    for (final url in candidates) {
      try {
        final resp = await client.get('$url/api/v1/health');
        if (resp.statusCode == 200) return url;
      } catch (_) {}
    }
    return candidates.first; // best effort
  }

  /// Check if the sandbox server is reachable.
  Future<bool> healthCheck() async {
    try {
      final resp = await _dio.get('$_baseUrl/api/v1/health');
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Execute a Python script in the sandbox and return the result.
  Future<SandboxResult> executePython(
    String script, {
    int timeout = 30,
    Map<String, String>? env,
  }) async {
    return _execute('python', script, timeout: timeout, env: env);
  }

  /// Execute a Bash script in the sandbox and return the result.
  Future<SandboxResult> executeBash(
    String script, {
    int timeout = 30,
    Map<String, String>? env,
  }) async {
    return _execute('bash', script, timeout: timeout, env: env);
  }

  Future<SandboxResult> _execute(
    String language,
    String script, {
    int timeout = 30,
    Map<String, String>? env,
  }) async {
    try {
      final resp = await _dio.post(
        '$_baseUrl/api/v1/execute',
        data: {
          'language': language,
          'script': script,
          'timeout': timeout,
          if (env != null) 'env': env,
        },
      );
      return SandboxResult.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      return SandboxResult(
        stdout: '',
        stderr: 'Sandbox error: ${e.message}',
        exitCode: -1,
        executionTime: 0,
        truncated: false,
      );
    }
  }

  /// Fetch A-share daily kline data for [symbol] (6-digit code).
  /// Returns CSV-formatted OHLCV data or error message.
  Future<String> fetchAStockKline(
    String symbol, {
    String period = 'daily',
    String startDate = '',
    String endDate = '',
  }) async {
    // Default to last 90 days
    if (startDate.isEmpty || endDate.isEmpty) {
      final now = DateTime.now();
      endDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final ago = now.subtract(const Duration(days: 90));
      startDate = '${ago.year}${ago.month.toString().padLeft(2, '0')}${ago.day.toString().padLeft(2, '0')}';
    }

    final prefix = switch (symbol[0]) {
      '6' => 'sh',
      '0' || '3' => 'sz',
      '4' || '8' => 'bj',
      _ => 'sh',
    };
    final fullSymbol = '$prefix.$symbol';

    final script = '''
import baostock as bs
import pandas as pd

bs.login()
rs = bs.query_history_k_data_plus(
    "$fullSymbol",
    "date,code,open,high,low,close,volume,amount,turn,peTTM",
    start_date="$startDate", end_date="$endDate",
    frequency="${period == 'weekly' ? 'w' : period == 'monthly' ? 'm' : 'd'}",
    adjustflag="2"
)

rows = []
while (rs.error_code == "0") and rs.next():
    rows.append(rs.get_row_data())
bs.logout()

if not rows:
    print("ERROR: No data returned for $fullSymbol")
else:
    df = pd.DataFrame(rows, columns=rs.fields)
    print(df.to_string(index=False))
    print(f"\\nTotal: {len(df)} rows | Period: $period | Symbol: $fullSymbol")
''';

    final result = await executePython(script, timeout: 30);
    if (result.ok) {
      return result.stdout;
    }
    return 'ERROR: ${result.stderr}';
  }

  /// Fetch A-share real-time quote for [symbol].
  Future<String> fetchAStockQuote(String symbol) async {
    final prefix = switch (symbol[0]) {
      '6' => 'sh',
      '0' || '3' => 'sz',
      _ => 'sh',
    };
    final fullSymbol = '$prefix.$symbol';

    final script = '''
import baostock as bs
import pandas as pd

bs.login()
# Get latest daily data
rs = bs.query_history_k_data_plus(
    "$fullSymbol",
    "date,code,open,high,low,close,volume,amount,turn,peTTM,pbMRQ",
    start_date="${_todayStr()}", end_date="${_todayStr()}",
    frequency="d", adjustflag="2"
)

rows = []
while (rs.error_code == "0") and rs.next():
    rows.append(rs.get_row_data())

# If no data today, try last 5 days
if not rows:
    from datetime import datetime, timedelta
    ago = (datetime.now() - timedelta(days=5)).strftime("%Y-%m-%d")
    rs = bs.query_history_k_data_plus(
        "$fullSymbol",
        "date,code,open,high,low,close,volume,amount,turn,peTTM,pbMRQ",
        start_date=ago, end_date="${_todayStr()}",
        frequency="d", adjustflag="2"
    )
    while (rs.error_code == "0") and rs.next():
        rows.append(rs.get_row_data())

bs.logout()

if rows:
    df = pd.DataFrame(rows, columns=rs.fields)
    print(df.to_string(index=False))
else:
    print("No data for $fullSymbol")
''';

    final result = await executePython(script, timeout: 15);
    if (result.ok) {
      return result.stdout;
    }
    return 'ERROR: ${result.stderr}';
  }

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Build LLM context from raw stock data output.
  static String formatForLLM(
    String rawData, {
    required String symbol,
    required String stockName,
  }) {
    final buf = StringBuffer();
    buf.writeln('以下是来自实时行情数据库的「$stockName ($symbol)」数据：');
    buf.writeln();
    buf.writeln(rawData);
    buf.writeln();
    buf.writeln('请基于以上实时数据进行分析。');
    return buf.toString();
  }
}
