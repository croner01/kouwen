import 'package:flutter_test/flutter_test.dart';
import 'package:kouwen/services/file_attachment_service.dart';

void main() {
  group('FileAttachment', () {
    test('sizeLabel formats bytes correctly', () {
      final a = FileAttachment(name: 'test.txt', path: '/tmp/test.txt', size: 500);
      expect(a.sizeLabel, '500 B');
    });

    test('sizeLabel formats KB correctly', () {
      final a = FileAttachment(name: 'test.txt', path: '/tmp/test.txt', size: 2048);
      expect(a.sizeLabel, '2.0 KB');
    });

    test('sizeLabel formats MB correctly', () {
      final a = FileAttachment(name: 'test.txt', path: '/tmp/test.txt', size: 3 * 1024 * 1024);
      expect(a.sizeLabel, '3.0 MB');
    });
  });

  group('FileAttachmentService', () {
    test('buildAttachmentContext with text content', () {
      final attachments = [
        FileAttachment(
          name: 'readme.md',
          path: '/tmp/readme.md',
          size: 1024,
          extractedText: '# Hello\nThis is a test file.',
        ),
      ];

      final context = FileAttachmentService.buildAttachmentContext(attachments);

      expect(context, contains('--- 附件内容 ---'));
      expect(context, contains('[文件: readme.md (1.0 KB)]'));
      expect(context, contains('# Hello'));
      expect(context, contains('This is a test file.'));
      expect(context, contains('--- 附件结束 ---'));
    });

    test('buildAttachmentContext without text content', () {
      final attachments = [
        FileAttachment(
          name: 'photo.png',
          path: '/tmp/photo.png',
          size: 500000,
        ),
      ];

      final context = FileAttachmentService.buildAttachmentContext(attachments);

      expect(context, contains('photo.png'));
      expect(context, contains('此文件类型暂不支持文本提取'));
    });

    test('buildAttachmentContext with multiple files', () {
      final attachments = [
        FileAttachment(name: 'a.txt', path: '/tmp/a.txt', size: 100, extractedText: 'AAA'),
        FileAttachment(name: 'b.md', path: '/tmp/b.md', size: 200, extractedText: 'BBB'),
      ];

      final context = FileAttachmentService.buildAttachmentContext(attachments);

      expect(context, contains('a.txt'));
      expect(context, contains('b.md'));
      expect(context, contains('AAA'));
      expect(context, contains('BBB'));
    });

    test('buildAttachmentContext with empty list', () {
      final context = FileAttachmentService.buildAttachmentContext([]);

      expect(context, contains('--- 附件内容 ---'));
      expect(context, contains('--- 附件结束 ---'));
    });
  });
}
