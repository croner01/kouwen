import 'package:flutter/material.dart';
import '../../../services/file_attachment_service.dart';

class ChatInputBar extends StatefulWidget {
  final Function(String text, List<FileAttachment> attachments) onSend;
  final bool webSearchEnabled;
  final VoidCallback onToggleWebSearch;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.webSearchEnabled = false,
    required this.onToggleWebSearch,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  bool _hasContent = false;
  final List<FileAttachment> _attachments = [];
  bool _isPicking = false;
  bool _isShooting = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateState);
  }

  void _updateState() {
    setState(() {
      _hasContent = _controller.text.trim().isNotEmpty || _attachments.isNotEmpty;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_updateState);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    setState(() => _isPicking = true);
    try {
      final files = await FileAttachmentService.pickFiles();
      setState(() {
        _attachments.addAll(files);
        _updateState();
      });
    } finally {
      setState(() => _isPicking = false);
    }
  }

  Future<void> _takePhoto() async {
    setState(() => _isShooting = true);
    try {
      final file = await FileAttachmentService.pickCamera();
      if (file != null) {
        setState(() {
          _attachments.add(file);
          _updateState();
        });
      }
    } finally {
      setState(() => _isShooting = false);
    }
  }

  void _send() {
    if (!_hasContent) return;
    final text = _controller.text.trim();
    final attachments = List<FileAttachment>.from(_attachments);
    widget.onSend(text, attachments);
    _controller.clear();
    setState(() => _attachments.clear());
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
      _updateState();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
            top: BorderSide(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Attachment chips
          if (_attachments.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: List.generate(_attachments.length, (i) {
                final a = _attachments[i];
                return Chip(
                  avatar: Icon(
                    _iconForFile(a.name),
                    size: 16,
                    color: const Color(0xFF4F46E5),
                  ),
                  label: Text(
                    a.name,
                    style: const TextStyle(fontSize: 12),
                  ),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => _removeAttachment(i),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              }),
            ),
          if (_attachments.isNotEmpty) const SizedBox(height: 6),
          // Input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: _isPicking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file, size: 22),
                onPressed: _isPicking ? null : _pickFiles,
                padding: EdgeInsets.zero,
                tooltip: '选择文件',
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              IconButton(
                icon: _isShooting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt_outlined, size: 22),
                onPressed: _isShooting ? null : _takePhoto,
                padding: EdgeInsets.zero,
                tooltip: '拍照',
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              IconButton(
                icon: Icon(
                  Icons.language,
                  size: 22,
                  color: widget.webSearchEnabled
                      ? const Color(0xFF4F46E5)
                      : Colors.grey.shade400,
                ),
                onPressed: widget.onToggleWebSearch,
                padding: EdgeInsets.zero,
                tooltip: widget.webSearchEnabled ? '已开启联网搜索' : '开启联网搜索',
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '输入你的问题...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  Icons.send_rounded,
                  color: _hasContent
                      ? const Color(0xFF4F46E5)
                      : Colors.grey.shade400,
                ),
                onPressed: _hasContent ? _send : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconForFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'txt':
      case 'md':
        return Icons.article;
      case 'json':
      case 'xml':
        return Icons.code;
      case 'png':
      case 'jpg':
      case 'jpeg':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }
}
