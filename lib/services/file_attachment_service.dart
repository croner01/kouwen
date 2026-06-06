import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

class FileAttachment {
  final String name;
  final String path;
  final int size;
  final String? extractedText;

  const FileAttachment({
    required this.name,
    required this.path,
    required this.size,
    this.extractedText,
  });

  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class FileAttachmentService {
  /// Take a photo using the system camera, compressed for API sending.
  static Future<FileAttachment?> pickCamera() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (xfile == null) return null;

    return FileAttachment(
      name: xfile.name,
      path: xfile.path,
      size: await File(xfile.path).length(),
    );
  }

  /// Pick files from device storage
  static Future<List<FileAttachment>> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'txt', 'md', 'json', 'xml', 'csv', 'log',
        'pdf', 'doc', 'docx',
        'png', 'jpg', 'jpeg',
      ],
    );

    if (result == null || result.files.isEmpty) return [];

    final attachments = <FileAttachment>[];
    for (final file in result.files) {
      if (file.path == null) continue;
      final path = file.path!;

      String? extracted;
      if (_isTextFile(file.name)) {
        extracted = await _readTextFile(path);
      }

      attachments.add(FileAttachment(
        name: file.name,
        path: path,
        size: file.size,
        extractedText: extracted,
      ));
    }
    return attachments;
  }

  static bool _isTextFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    return ['txt', 'md', 'json', 'xml', 'csv', 'log', 'html', 'css', 'js', 'py', 'dart', 'java', 'kt', 'swift'].contains(ext);
  }

  static Future<String?> _readTextFile(String path) async {
    try {
      final file = File(path);
      if (await file.length() > 500 * 1024) {
        // Skip files > 500KB to avoid performance issues
        return '[文件过大，已跳过内容提取]';
      }
      final content = await file.readAsString();
      if (content.length > 10000) {
        var end = 10000;
        // Avoid splitting in the middle of a UTF-16 surrogate pair
        if (end < content.length) {
          final cu = content.codeUnitAt(end);
          if (cu >= 0xDC00 && cu <= 0xDFFF) end--;
        }
        // Also check if end-1 is a high surrogate (pair spans the boundary)
        if (end > 0 && end <= content.length) {
          final prev = content.codeUnitAt(end - 1);
          if (prev >= 0xD800 && prev <= 0xDBFF) end--;
        }
        return '${content.substring(0, end)}\n\n...[内容已截断]';
      }
      return content;
    } catch (_) {
      return null;
    }
  }

  /// Build a formatted context string from attachments
  static String buildAttachmentContext(List<FileAttachment> attachments) {
    final sb = StringBuffer();
    sb.writeln('--- 附件内容 ---');
    for (final a in attachments) {
      sb.writeln('\n[文件: ${a.name} (${a.sizeLabel})]');
      if (a.extractedText != null) {
        sb.writeln('```');
        sb.writeln(a.extractedText);
        sb.writeln('```');
      } else {
        sb.writeln('[此文件类型暂不支持文本提取，请基于文件名推断内容]');
      }
    }
    sb.writeln('--- 附件结束 ---');
    return sb.toString();
  }
}
