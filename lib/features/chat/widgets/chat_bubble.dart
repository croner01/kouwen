import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/models.dart';
import '../../../widgets/markdown_view.dart';

class ChatBubble extends StatelessWidget {
  final Message message;
  final String? skillIcon;

  const ChatBubble({super.key, required this.message, this.skillIcon});

  void _copyText(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已复制'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        width: 100,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final hasFiles =
        message.attachments != null && message.attachments!.isNotEmpty;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final assistantBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final assistantBorder = isDark ? Colors.transparent : Colors.grey.shade200;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor:
                  const Color(0xFF4F46E5).withValues(alpha: 0.1),
              backgroundImage: skillIcon == null
                  ? const AssetImage('assets/icon/chat_avatar.png')
                  : null,
              child: skillIcon != null
                  ? Text(skillIcon!,
                      style: const TextStyle(fontSize: 16))
                  : null,
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () => _copyText(context, message.content),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isUser ? const Color(0xFF4F46E5) : assistantBg,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  border: isUser
                      ? null
                      : Border.all(color: assistantBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasFiles && isUser) ...[
                      ...message.attachments!.map((a) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.attach_file,
                                    size: 14, color: Colors.white70),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    a.split('/').last,
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          )),
                      Container(
                        height: 1,
                        color: Colors.white24,
                        margin: const EdgeInsets.only(bottom: 8),
                      ),
                    ],
                    isUser
                        ? Text(
                            message.content,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.5),
                          )
                        : MarkdownView(content: message.content, isDark: isDark),
                    // Copy button on AI messages
                    if (!isUser)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: GestureDetector(
                          onTap: () =>
                              _copyText(context, message.content),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Icon(Icons.copy,
                                size: 14, color: Colors.grey.shade400),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 10),
          if (isUser)
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFFEEF2FF),
              child: Text('\u{1F464}',
                  style: TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
  }
}
