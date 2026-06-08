import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:kouwen/services/github_skill_loader.dart';

// ── Mocks ──

class _MockDio extends Mock implements Dio {}

class _MockResponse extends Mock implements Response {
  @override
  final int? statusCode;

  @override
  final dynamic data;

  _MockResponse({this.statusCode, this.data});
}

// ── Helpers ──

Response _fakeResponse(int code, String body) {
  return _MockResponse(statusCode: code, data: body);
}

/// A Dio mock that uses a real BaseOptions so setter calls work.
_MockDio _createDio() {
  final d = _MockDio();
  when(() => d.options).thenReturn(BaseOptions());
  return d;
}

void main() {
  late _MockDio mockDio;
  late GitHubSkillLoader loader;

  setUp(() {
    mockDio = _createDio();
    loader = GitHubSkillLoader(dio: mockDio, giteeToken: 'test_gitee_token');
  });

  group('downloadSkillContent', () {
    test('applies gitee auth token for Gitee URLs on first attempt', () async {
      const giteeUrl = 'https://gitee.com/ren02/skills/raw/main/skills/brand-guidelines/SKILL.md';
      final expectedAuthedUrl = '$giteeUrl?access_token=test_gitee_token';

      when(() => mockDio.get(
            any(),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _fakeResponse(200, 'name: test-skill\nsystem_prompt: test'));

      final result = await loader.downloadSkillContent(giteeUrl);

      expect(result, 'name: test-skill\nsystem_prompt: test');
      verify(() => mockDio.get(
            expectedAuthedUrl,
            options: any(named: 'options'),
          )).called(1);
    });

    test('does NOT apply gitee auth for GitHub URLs', () async {
      const githubUrl = 'https://raw.githubusercontent.com/ren02/skills/main/skills/test/SKILL.md';

      when(() => mockDio.get(
            any(),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _fakeResponse(200, 'name: test'));

      await loader.downloadSkillContent(githubUrl);

      // Original GitHub URL is used without ?access_token
      verify(() => mockDio.get(
            githubUrl,
            options: any(named: 'options'),
          )).called(1);
    });

    test('tries branch fallback when Gitee first attempt fails', () async {
      const giteeUrl = 'https://gitee.com/ren02/skills/raw/main/skills/test/SKILL.md';
      const fallbackMainUrl = '$giteeUrl?access_token=test_gitee_token';
      const fallbackMasterUrl = 'https://gitee.com/ren02/skills/raw/master/skills/test/SKILL.md?access_token=test_gitee_token';

      // First attempt returns 404
      when(() => mockDio.get(
            any(),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _fakeResponse(404, ''));

      await loader.downloadSkillContent(giteeUrl);

      // Should have tried: original+auth, main (same branch skipped), master+auth
      verify(() => mockDio.get(
            fallbackMainUrl,
            options: any(named: 'options'),
          )).called(1);
      verify(() => mockDio.get(
            fallbackMasterUrl,
            options: any(named: 'options'),
          )).called(1);
    });

    test('returns null when all attempts fail', () async {
      when(() => mockDio.get(
            any(),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _fakeResponse(404, ''));

      final result = await loader.downloadSkillContent(
          'https://gitee.com/ren02/skills/raw/main/nonexistent/SKILL.md');

      expect(result, isNull);
    });

    test('returns null on DioException', () async {
      when(() => mockDio.get(
            any(),
            options: any(named: 'options'),
          )).thenThrow(DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.connectionTimeout,
          ));

      final result = await loader.downloadSkillContent(
          'https://gitee.com/ren02/skills/raw/main/test/SKILL.md');

      expect(result, isNull);
    });

    test('without giteeToken, no query param is appended', () async {
      final noTokenDio = _createDio();
      when(() => noTokenDio.get(
            any(),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _fakeResponse(200, 'name: test'));

      final loaderNoToken = GitHubSkillLoader(dio: noTokenDio);

      await loaderNoToken.downloadSkillContent(
          'https://gitee.com/ren02/skills/raw/main/test/SKILL.md');

      // URL should NOT have ?access_token=
      verify(() => noTokenDio.get(
            'https://gitee.com/ren02/skills/raw/main/test/SKILL.md',
            options: any(named: 'options'),
          )).called(1);
    });
  });
}
