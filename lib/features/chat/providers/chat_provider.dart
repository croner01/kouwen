import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers.dart';
import '../../../data/models.dart';
import '../../../data/repositories.dart';
import '../../../engine/skill_parser.dart';
import '../../../engine/skill_router.dart';
import '../../../engine/prompt_builder.dart';
import '../../../services/api_service.dart';
import '../../../services/model_manager.dart';
import '../../../services/file_attachment_service.dart';
import '../../../services/web_search_service.dart';

class ChatState {
  final List<Message> messages;
  final bool isLoading;
  final String? error;
  final Conversation? conversation;
  final ParsedSkill? skill;
  final List<SkillMatch> suggestedSkills;
  final String streamingContent;
  final bool webSearchEnabled;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.conversation,
    this.skill,
    this.suggestedSkills = const [],
    this.streamingContent = '',
    this.webSearchEnabled = false,
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
    );
  }
  static const _sentinel = Object();
}

class ChatNotifier extends StateNotifier<ChatState> {
  final ConversationRepository _conversationRepo;
  final SkillRepository _skillRepo;
  final ModelManager _modelManager;
  final ApiService _apiService;
  CancelToken? _activeCancelToken;

  ChatNotifier(Ref ref)
      : _conversationRepo = ref.read(conversationRepoProvider),
        _skillRepo = ref.read(skillRepoProvider),
        _modelManager = ref.read(modelManagerProvider),
        _apiService = ref.read(apiServiceProvider),
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
    );
  }

  /// Load an existing conversation
  Future<void> loadConversation(String conversationId) async {
    try {
      final conversation =
          await _conversationRepo.getConversationById(conversationId);
      if (conversation == null) {
        state = state.copyWith(error: '对话未找到');
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
      );
    } catch (e) {
      // ignore: avoid_print
      print('loadConversation error: $e');
      state = state.copyWith(error: '对话加载失败: ${e.toString().replaceAll(RegExp(r'Exception:\s*|DioException\s*'), '').trim()}');
    }
  }

  /// Load a skill into the current conversation
  Future<void> loadSkill(String skillId) async {
    final skillData = await _skillRepo.getSkillById(skillId);
    if (skillData == null) {
      state = state.copyWith(error: '技能未找到');
      return;
    }

    // Collection parents have no yamlContent — can't be loaded directly
    if (skillData.isCollection || skillData.yamlContent.isEmpty) {
      state = state.copyWith(error: '技能集合无法直接加载，请选择具体子技能');
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
    // Set loading immediately to prevent concurrent sends
    state = state.copyWith(isLoading: true, error: null);

    final modelConfig = await _modelManager.getDefaultConfig();
    if (modelConfig == null) {
      state = state.copyWith(
          error: '请先在设置中配置模型 API');
      return;
    }
    final apiKey = await _modelManager.getApiKey(modelConfig.id);
    if (apiKey == null) {
      state = state.copyWith(error: 'API Key 未找到');
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

    // ── Web Search ──
    // Auto-trigger on time-sensitive keywords even when toggle is off.
    final shouldSearch = state.webSearchEnabled || _needsSearch(content);
    String? searchContext;
    Map<String, dynamic>? searchParam;

    if (shouldSearch) {
      // 1) Model-native search: pass search param in API request body.
      //    The model itself searches, reads, and synthesizes the answer.
      searchParam = ApiService.detectSearchParam(modelConfig.modelName);
      if (searchParam == null) {
        // 2) Fallback: client-side search via Jina Reader (free, no Key).
        //    Search the web, fetch the top result's full content as
        //    clean Markdown, then inject it as context into the prompt.
        try {
          final ws = WebSearchService();
          final results = await ws.search(content);
          if (results.isNotEmpty) {
            String? fullContent;
            String? sourceTitle;
            if (results.first.url.isNotEmpty) {
              fullContent = await ws.fetch(results.first.url);
              sourceTitle = results.first.title;
            }
            searchContext = WebSearchService.formatForLLM(
              results,
              fullContent: fullContent,
              sourceTitle: sourceTitle,
            );
          }
        } catch (_) {
          // Search failed silently — continue without results
        }
      }
    }

    try {
      final systemPrompt =
          (state.skill?.systemPrompt ?? _defaultSystemPrompt()) +
              '\n\n${_dateContext()}';
      var userInput = content;
      if (searchContext != null) {
        userInput = '$searchContext\n\n用户问题: $content';
      }
      final messages = PromptBuilder.buildMessages(
        systemPrompt: systemPrompt,
        userInput: userInput,
        history: previousMessages,
        maxHistoryRounds: 20,
      );

      // Cancel any previous in-flight request
      _activeCancelToken?.cancel();
      _activeCancelToken = CancelToken();
      final stream = _apiService.chatStream(
        apiUrl: modelConfig.apiUrl,
        apiKey: apiKey,
        modelName: modelConfig.modelName,
        messages: messages,
        cancelToken: _activeCancelToken,
        searchParam: searchParam,
      );

      String fullResponse = '';
      await for (final chunk in stream) {
        fullResponse += chunk;
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
        );
      } else {
        state =
            state.copyWith(isLoading: false, streamingContent: '');
      }
    } catch (e) {
      var errMsg = e.toString();
      if (e is ApiException) {
        errMsg = e.message;
      }
      errMsg = errMsg
          .replaceAll('Exception: ', '')
          .replaceAll('DioException', '')
          .trim();

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

  /// Auto-detect whether the user's message needs a web search.
  /// Triggers on time-sensitive, real-time, or URL-containing queries.
  bool _needsSearch(String input) {
    if (input.startsWith('http://') || input.startsWith('https://')) return true;
    final lower = input.toLowerCase();
    const triggers = [
      '最新', '今天', '最近', '新闻', '行情', '价格', '天气',
      '股票', '比分', '汇率', '涨停', '跌停', '大盘',
      '2025', '2026', '今年',
    ];
    for (final t in triggers) {
      if (lower.contains(t)) return true;
    }
    return false;
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
