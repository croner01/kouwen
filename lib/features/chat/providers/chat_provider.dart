import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers.dart';
import '../../../data/models.dart';
import '../../../data/repositories.dart';
import '../../../engine/skill_parser.dart';
import '../../../engine/skill_router.dart';
import '../../../services/agent_service.dart';
import '../../../services/api_service.dart';
import '../../../services/model_manager.dart';
import '../../../services/file_attachment_service.dart';

class ChatState {
  final List<Message> messages;
  final bool isLoading;
  final String? error;
  final Conversation? conversation;
  final ParsedSkill? skill;
  final List<SkillMatch> suggestedSkills;
  final String streamingContent;
  final bool webSearchEnabled;
  final bool streamInterrupted;   // true when SSE ended without done/error
  final bool isLoadingConversation; // true while loading a history conversation
  final bool compactSuggested;      // true when turn count >= threshold
  final bool isCompacting;          // true during summary generation
  final int? dismissedCompactAtTurnCount; // user dismissed at this turn, for cool-down

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.conversation,
    this.skill,
    this.suggestedSkills = const [],
    this.streamingContent = '',
    this.webSearchEnabled = false,
    this.streamInterrupted = false,
    this.isLoadingConversation = false,
    this.compactSuggested = false,
    this.isCompacting = false,
    this.dismissedCompactAtTurnCount,
  });

  ChatState copyWith({
    List<Message>? messages,
    bool? isLoading,
    Object? error = _sentinel,
    Object? conversation = _sentinel,
    Object? skill = _sentinel,
    List<SkillMatch>? suggestedSkills,
    String? streamingContent,
    bool? webSearchEnabled,
    bool? streamInterrupted,
    bool? isLoadingConversation,
    bool? compactSuggested,
    bool? isCompacting,
    Object? dismissedCompactAtTurnCount = _sentinel,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error == _sentinel ? this.error : error as String?,
      conversation: conversation == _sentinel ? this.conversation : conversation as Conversation?,
      skill: skill == _sentinel ? this.skill : skill as ParsedSkill?,
      suggestedSkills: suggestedSkills ?? this.suggestedSkills,
      streamingContent: streamingContent ?? this.streamingContent,
      webSearchEnabled: webSearchEnabled ?? this.webSearchEnabled,
      streamInterrupted: streamInterrupted ?? this.streamInterrupted,
      isLoadingConversation: isLoadingConversation ?? this.isLoadingConversation,
      compactSuggested: compactSuggested ?? this.compactSuggested,
      isCompacting: isCompacting ?? this.isCompacting,
      dismissedCompactAtTurnCount: dismissedCompactAtTurnCount == _sentinel
          ? this.dismissedCompactAtTurnCount
          : dismissedCompactAtTurnCount as int?,
    );
  }
  static const _sentinel = Object();
}

class ChatNotifier extends StateNotifier<ChatState> {
  final Ref _ref;
  final ConversationRepository _conversationRepo;
  final SkillRepository _skillRepo;
  final ModelManager _modelManager;
  CancelToken? _activeCancelToken;

  ChatNotifier(Ref ref)
      : _ref = ref,
        _conversationRepo = ref.read(conversationRepoProvider),
        _skillRepo = ref.read(skillRepoProvider),
        _modelManager = ref.read(modelManagerProvider),
        super(const ChatState());

  /// Create a new conversation
  Future<void> createConversation() async {
    final conversation = await _conversationRepo.createConversation(
      skillName: null,
    );
    state = state.copyWith(
      conversation: conversation,
      skill: null,
      messages: [],
      error: null,
      isLoading: false,
      streamingContent: '',
      streamInterrupted: false,
      isLoadingConversation: false,
      compactSuggested: false,
      isCompacting: false,
    );
  }

  /// Load an existing conversation
  Future<void> loadConversation(String conversationId) async {
    state = state.copyWith(isLoadingConversation: true, error: null);
    try {
      final conversation =
          await _conversationRepo.getConversationById(conversationId);
      if (conversation == null) {
        state = state.copyWith(error: '对话未找到', isLoadingConversation: false);
        return;
      }
      final messages =
          await _conversationRepo.getMessages(conversationId);

      // Try to load skill if one was associated
      ParsedSkill? skill;
      final loadedSkillId = conversation.skillId;
      if (loadedSkillId != null) {
        try {
          final skillData =
              await _skillRepo.getSkillById(loadedSkillId);
          if (skillData != null) {
            skill = SkillParser.parse(skillData.yamlContent);
          }
        } catch (e) {
          // Skill data may be corrupted or missing — continue without it
          // ignore: avoid_print
          print('loadConversation: skill load skipped ($e)');
        }
      }

      state = state.copyWith(
        conversation: conversation,
        skill: skill,
        messages: messages,
        error: null,
        isLoadingConversation: false,
        compactSuggested: false,
        dismissedCompactAtTurnCount: null,
      );
    } catch (e) {
      // ignore: avoid_print
      print('loadConversation error: $e');
      state = state.copyWith(error: '对话加载失败: ${e.toString().replaceAll(RegExp(r'Exception:\s*|DioException\s*'), '').trim()}', isLoadingConversation: false);
    }
  }

  /// Load a skill into the current conversation
  Future<void> loadSkill(String skillId) async {
    var skillData = await _skillRepo.getSkillById(skillId);
    if (skillData == null) {
      // ignore: avoid_print
      print('loadSkill: skill not found by id=$skillId (${skillId.length} chars)');
      state = state.copyWith(error: '技能未找到');
      return;
    }

    // Collection parents have no yamlContent — can't be loaded directly
    if (skillData.isCollection) {
      state = state.copyWith(error: '技能集合无法直接加载，请选择具体子技能');
      return;
    }

    // Skill with empty content — try backend API fallback before giving up
    if (skillData.yamlContent.isEmpty) {
      String? fetchedContent;
      try {
        final api = _ref.read(skillApiServiceProvider);
        final backendSkills = await api.listSkills();
        final bs = backendSkills.where((s) => s.name == skillData.name).firstOrNull;
        if (bs != null && bs.yamlContent.isNotEmpty) {
          fetchedContent = bs.yamlContent;
          await _skillRepo.updateSkillYamlContent(skillId, bs.yamlContent);
        }
      } catch (_) {
        // Backend unreachable — fall through to error below
      }

      if (fetchedContent == null || fetchedContent.isEmpty) {
        state = state.copyWith(error: '技能内容为空，请尝试重新安装');
        return;
      }

      // Parse using fetched content
      ParsedSkill fetchedSkill;
      try {
        fetchedSkill = SkillParser.parse(fetchedContent);
      } catch (_) {
        state = state.copyWith(error: '技能文件格式错误');
        return;
      }

      // Persist skill association
      if (state.conversation != null) {
        await _conversationRepo.updateConversation(
          state.conversation!.id,
          skillId: skillId,
          skillName: skillData.name,
        );
      }
      state = state.copyWith(skill: fetchedSkill, suggestedSkills: [], error: null);
      return;
    }

    ParsedSkill skill;
    try {
      skill = SkillParser.parse(skillData.yamlContent);
    } catch (_) {
      state = state.copyWith(error: '技能文件格式错误');
      return;
    }

    // Persist skill association so it's restored when returning to this conversation
    if (state.conversation != null) {
      await _conversationRepo.updateConversation(
        state.conversation!.id,
        skillId: skillId,
        skillName: skillData.name,
      );
    }

    state = state.copyWith(skill: skill, suggestedSkills: [], error: null);
  }

  /// Unload the current skill
  void unloadSkill() {
    state = state.copyWith(skill: null);
  }

  /// Send a message
  Future<void> sendMessage(String content,
      {List<FileAttachment> attachments = const []}) async {
    if (state.conversation == null) {
      state = state.copyWith(error: '对话未初始化');
      return;
    }
    if (state.isLoading) {
      state = state.copyWith(error: '正在回复中，请稍候');
      return;
    }
    if (state.isCompacting) {
      state = state.copyWith(error: '正在压缩对话中，请稍候');
      return;
    }
    // Set loading immediately to prevent concurrent sends
    state = state.copyWith(isLoading: true, error: null, streamInterrupted: false);

    final modelConfig = await _modelManager.getDefaultConfig();
    if (modelConfig == null) {
      state = state.copyWith(
          isLoading: false,
          error: '请先在设置中配置模型 API');
      return;
    }
    final apiKey = await _modelManager.getApiKey(modelConfig.id);
    if (apiKey == null) {
      state = state.copyWith(
          isLoading: false,
          error: 'API Key 未找到');
      return;
    }

    final attachmentContext = attachments.isNotEmpty
        ? '\n\n${FileAttachmentService.buildAttachmentContext(attachments)}'
        : '';
    final attachmentNames = attachments.isNotEmpty
        ? attachments.map((a) => a.path).toList()
        : null;

    // Capture history BEFORE adding current user message —
    // PromptBuilder adds userInput separately, so history must exclude it.
    final previousMessages = state.messages;

    final userMsg = await _conversationRepo.addMessage(
      conversationId: state.conversation!.id,
      role: MessageRole.user,
      content: '$content$attachmentContext',
      attachments: attachmentNames,
    );
    state = state.copyWith(
      messages: [...state.messages, userMsg],
    );

    // Auto-match skill if none loaded (await so it takes effect on THIS message)
    if (state.skill == null) {
      try {
        final matches = await SkillRouter.match(content, repo: _skillRepo)
            .timeout(const Duration(milliseconds: 500));
        if (matches.isNotEmpty) {
          final best = matches.first;
          if (best.score >= SkillRouter.autoMatchThreshold) {
            // High confidence — auto-load immediately, takes effect on this msg
            await loadSkill(best.skill.id);
          } else {
            // Show ALL matches above suggestThreshold as a persistent list
            final suggestions = matches
                .where((m) => m.score >= SkillRouter.suggestThreshold)
                .toList();
            if (suggestions.isNotEmpty) {
              state = state.copyWith(suggestedSkills: suggestions);
            }
          }
        }
      } catch (_) {
        // Timeout or DB error — continue with default prompt
      }
    }

    if (state.conversation!.title == null) {
      await _conversationRepo.updateConversation(
        state.conversation!.id,
        title: content.length > 30
            ? '${content.substring(0, 30)}...'
            : content,
      );
    }

    try {
      // Build messages for Agent
      final systemPrompt = (state.skill?.systemPrompt ?? _defaultSystemPrompt());

      // Build conversation messages (no context injection — Agent handles tools)
      // Limit history to prevent unbounded context growth over many turns.
      const int maxHistoryMessages = 60;
      final agentMessages = <Map<String, String>>[];
      final nonSystemMsgs =
          previousMessages.where((m) => m.role != MessageRole.system).toList();
      var recentMsgs = nonSystemMsgs.length > maxHistoryMessages
          ? nonSystemMsgs.sublist(nonSystemMsgs.length - maxHistoryMessages)
          : nonSystemMsgs;

      // Always include the compact summary (marked with 📋 prefix)
      if (nonSystemMsgs.length > maxHistoryMessages) {
        final summaryIdx = nonSystemMsgs.indexWhere((m) => m.content.startsWith('📋'));
        if (summaryIdx >= 0 && !recentMsgs.any((m) => m.id == nonSystemMsgs[summaryIdx].id)) {
          recentMsgs = [nonSystemMsgs[summaryIdx], ...recentMsgs];
        }
      }

      for (final msg in recentMsgs) {
        agentMessages.add({'role': msg.role.name, 'content': msg.content});
      }
      agentMessages.add({'role': 'user', 'content': content});

      // Cancel any previous in-flight request
      _activeCancelToken?.cancel();
      _activeCancelToken = CancelToken();

      // ── Agent Service (handles sandbox + search internally) ──
      final agent = _ref.read(agentServiceProvider);
      // Use JWT if available for backend conversation management
      final auth = _ref.read(authServiceProvider);
      if (auth.isLoggedIn && auth.token != null) {
        agent.setAuth(auth.token!);
      }
      final stream = agent.chat(
        apiKey: apiKey,
        baseUrl: modelConfig.apiUrl,
        model: modelConfig.modelName,
        messages: agentMessages,
        systemPrompt: '$systemPrompt\n\n${_dateContext()}',
        webSearchEnabled: state.webSearchEnabled,
        cancelToken: _activeCancelToken,
      );

      String fullResponse = '';
      final currentSkill = state.skill; // capture for tool label context
      bool gotFinalEvent = false;
      await for (final event in stream) {
        if (event is TextDeltaEvent) {
          fullResponse += event.content;
          state = state.copyWith(streamingContent: fullResponse);
        } else if (event is ToolUseEvent) {
          final toolLabel = _toolLabel(event.name, event.input, skill: currentSkill);
          fullResponse += '\n\n> $toolLabel\n\n';
          state = state.copyWith(streamingContent: fullResponse);
        } else if (event is ToolResultEvent) {
          // Tool results are internal — handled by Agent
        } else if (event is AgentDoneEvent) {
          gotFinalEvent = true;
          if (event.truncated) {
            final msg = switch (event.truncationReason) {
              'max_tokens' => '⚠️ 回复达到 Token 上限，内容可能被截断。',
              'max_turns' => '⚠️ 达到最大工具调用次数，回复可能不完整。',
              _ => '⚠️ 回复被截断，可能不完整。',
            };
            fullResponse += '\n\n> $msg\n\n';
            state = state.copyWith(streamingContent: fullResponse);
          }
        } else if (event is AgentErrorEvent) {
          gotFinalEvent = true;
          fullResponse += '\n\n> ❌ 错误: ${event.message}';
          state = state.copyWith(streamingContent: fullResponse);
        }
      }

      // Stream ended without a final done/error event = interrupted
      final wasInterrupted = !gotFinalEvent && fullResponse.isNotEmpty;
      if (wasInterrupted) {
        fullResponse += '\n\n> ⚠️ 输出中断，回复可能不完整。';
        state = state.copyWith(streamingContent: fullResponse);
      }

      if (fullResponse.isNotEmpty) {
        final assistantMsg = await _conversationRepo.addMessage(
          conversationId: state.conversation!.id,
          role: MessageRole.assistant,
          content: fullResponse,
        );
        state = state.copyWith(
          messages: [...state.messages, assistantMsg],
          streamingContent: '',
          isLoading: false,
          streamInterrupted: wasInterrupted,
        );
        _checkCompactThreshold();
      } else {
        state = state.copyWith(
          isLoading: false,
          streamingContent: '',
          streamInterrupted: false,
        );
      }
    } catch (e) {
      var errMsg = e.toString();
      if (e is ApiException) {
        errMsg = e.message;
      } else if (e is DioException) {
        if (e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.connectionTimeout) {
          errMsg = '服务器响应超时，请稍后重试';
        } else if (e.type == DioExceptionType.connectionError) {
          errMsg = '无法连接到服务器，请检查网络连接';
        } else if (e.response?.statusCode == 524) {
          errMsg = '服务器处理超时（Cloudflare 网关超时），请稍后重试或缩短回复长度';
        } else if (e.response?.statusCode == 502) {
          errMsg = '服务器暂时不可用（网关错误），请稍后重试';
        } else if (e.response?.statusCode == 503) {
          errMsg = '服务器暂时不可用（服务过载），请稍后重试';
        } else if (e.response?.data != null) {
          final data = e.response!.data;
          if (data is Map) {
            errMsg = (data['detail'] ?? data['message'] ?? data.toString()).toString();
          } else {
            errMsg = data.toString();
          }
        }
      } else {
        errMsg = errMsg
            .replaceAll('Exception: ', '')
            .replaceAll('DioException', '')
            .trim();
        if (errMsg.contains('HttpConnection closed') || errMsg.contains('Connection closed')) {
          errMsg = '服务器连接中断，请稍后重试';
        } else if (errMsg.contains('SocketException') || errMsg.contains('Connection refused')) {
          errMsg = '无法连接到服务器，请检查网络连接';
        }
      }

      state = state.copyWith(
        isLoading: false,
        streamingContent: '',
        error: errMsg,
      );

      Future.delayed(const Duration(seconds: 12), () {
        if (state.error == errMsg) {
          state = state.copyWith(error: null);
        }
      });
    }
  }

  void clearConversation() {
    state = state.copyWith(messages: []);
  }

  /// Start a truly new conversation (new DB record, not just in-memory clear)
  Future<void> newConversation() async {
    // Cancel any in-flight streaming request to prevent it from
    // writing to the wrong conversation
    _activeCancelToken?.cancel();
    _activeCancelToken = null;
    final conversation = await _conversationRepo.createConversation(
      skillName: null,
    );
    final webSearch = state.webSearchEnabled;
    state = ChatState(conversation: conversation, webSearchEnabled: webSearch);
  }

  @override
  void dispose() {
    _activeCancelToken?.cancel();
    super.dispose();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void toggleWebSearch() {
    state = state.copyWith(webSearchEnabled: !state.webSearchEnabled);
  }

  void clearSuggestion() {
    state = state.copyWith(suggestedSkills: []);
  }

  // ── Compact / Summary ──

  static const int compactTurnThreshold = 30;
  static const int compactReSuggestTurns = 5; // cool-down after dismiss

  /// Check if conversation has reached the compact threshold and suggest it.
  void _checkCompactThreshold() {
    if (state.compactSuggested || state.isCompacting) return;
    final turnCount = state.messages.where((m) => m.role == MessageRole.user).length;
    if (turnCount < compactTurnThreshold) return;

    // Respect cool-down after user dismissed
    if (state.dismissedCompactAtTurnCount != null &&
        turnCount - state.dismissedCompactAtTurnCount! < compactReSuggestTurns) {
      return;
    }

    state = state.copyWith(compactSuggested: true);
  }

  /// Dismiss the compact suggestion bar (re-suggests after [compactReSuggestTurns] more turns).
  void dismissCompact() {
    final turnCount = state.messages.where((m) => m.role == MessageRole.user).length;
    state = state.copyWith(
      compactSuggested: false,
      dismissedCompactAtTurnCount: turnCount,
    );
  }

  /// Compress the conversation: summarize all history via LLM and replace messages.
  Future<void> compactConversation() async {
    final targetConvId = state.conversation?.id;
    final targetTitle = state.conversation?.title; // capture early, avoid race on switch
    if (targetConvId == null || state.messages.length < 4) return;
    state = state.copyWith(isCompacting: true, compactSuggested: false, error: null);

    try {
      final modelConfig = await _modelManager.getDefaultConfig();
      if (modelConfig == null) {
        state = state.copyWith(isCompacting: false, error: '请先在设置中配置模型 API');
        return;
      }
      final apiKey = await _modelManager.getApiKey(modelConfig.id);
      if (apiKey == null) {
        state = state.copyWith(isCompacting: false, error: 'API Key 未找到');
        return;
      }

      // Build conversation history as messages for summarization (exclude system role
      // — Anthropic Messages API only supports user/assistant in the messages array)
      final summaryMessages = state.messages
          .where((m) => m.role != MessageRole.system)
          .map((m) => {
        'role': m.role.name,
        'content': m.content,
      }).toList();
      summaryMessages.add({
        'role': 'user',
        'content': '请总结以上所有对话。保留用户的核心需求、已获取的数据、分析结果和关键决策。去掉问候语和工具调用细节。用中文输出。',
      });

      // Use Agent Service for summary generation (maxTurns: 3 for safety)
      final agent = _ref.read(agentServiceProvider);
      final stream = agent.chat(
        apiKey: apiKey,
        baseUrl: modelConfig.apiUrl,
        model: modelConfig.modelName,
        messages: summaryMessages,
        systemPrompt: '你是一个对话摘要助手，只做一件事：总结对话。不要使用任何工具。',
        maxTokens: 8192,
        maxTurns: 3,
      );

      String summary = '';
      await for (final event in stream) {
        if (event is TextDeltaEvent) {
          summary += event.content;
        } else if (event is AgentErrorEvent) {
          state = state.copyWith(isCompacting: false, error: '压缩失败: ${event.message}');
          return;
        }
      }

      if (summary.trim().isEmpty) {
        state = state.copyWith(isCompacting: false, error: '压缩失败，摘要为空');
        return;
      }

      final turnCount = state.messages.where((m) => m.role == MessageRole.user).length;
      final summaryContent = '📋 以下是对之前 $turnCount 轮对话的摘要，请基于此继续对话：\n\n$summary';

      // Atomically replace all messages with the summary
      await _conversationRepo.replaceConversationMessages(
        targetConvId,
        [
          {
            'role': MessageRole.user.name,
            'content': summaryContent,
          },
        ],
      );

      // Update conversation title to indicate compressed
      var compactTitle = targetTitle;
      if (compactTitle != null && !compactTitle.startsWith('📋')) {
        compactTitle = '📋 $compactTitle';
        await _conversationRepo.updateConversation(
          targetConvId,
          title: compactTitle,
        );
      }

      // Reload fresh state from DB (only if still on the same conversation)
      if (state.conversation?.id == targetConvId) {
        final freshMessages = await _conversationRepo.getMessages(targetConvId);
        state = state.copyWith(
          messages: freshMessages,
          isCompacting: false,
        );
      } else {
        state = state.copyWith(isCompacting: false);
      }
    } catch (e) {
      state = state.copyWith(
        isCompacting: false,
        error: '压缩失败: ${e.toString().replaceAll('Exception: ', '').trim()}',
      );
    }
  }

  String _defaultSystemPrompt() {
    return '你是叩问 AI 助手，一个知识广博、无所不谈的专业分析伙伴。\n\n'
        '核心原则：\n'
        '1. 对所有问题给出实质性回答，不回避、不敷衍、不说「我不能回答」\n'
        '2. 如果问题涉及假设性、学术讨论或知识探讨，直接给出专业分析\n'
        '3. 遇到不确定的内容，给出你知道的部分，标注不确定之处\n'
        '4. 优先提供有用信息，而非拒绝回答\n\n'
        '你是用户的深度思考伙伴，任何问题都值得认真对待和分析。';
  }

  /// Human-readable label for tool calls shown in the chat.
  /// Includes the active skill's icon and name when available.
  static String _toolLabel(String name, Map<String, dynamic> input, {ParsedSkill? skill}) {
    final skillPrefix = skill != null ? '${skill.icon} ${skill.name} → ' : '🔧 ';
    final label = switch (name) {
      'sandbox_execute' =>
        '执行${input['language'] == 'bash' ? 'Bash' : 'Python'}脚本',
      'web_search' => '搜索: ${input['query'] ?? ''}',
      _ => '调用工具: $name',
    };
    return '$skillPrefix$label';
  }

  /// Build current date/time context so the LLM knows "now".
  String _dateContext() {
    final now = DateTime.now();
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final wd = weekdays[now.weekday - 1];
    return '当前时间: ${now.year}年${now.month}月${now.day}日 $wd '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}\n'
        '请基于以上当前时间回答用户问题。如果用户问「现在」「今天」「最近」等涉及时间的问题，以上述时间为准。';
  }
}

final chatProvider =
    StateNotifierProvider<ChatNotifier, ChatState>(
        (ref) => ChatNotifier(ref));
