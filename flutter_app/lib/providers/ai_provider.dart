import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ai.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

// AI Chat State
class AiChatState {
  final bool isLoading;
  final List<ChatMessage> messages;
  final List<AIInsight> insights;
  final String? error;

  const AiChatState({
    this.isLoading = false,
    this.messages = const [],
    this.insights = const [],
    this.error,
  });

  AiChatState copyWith({
    bool? isLoading,
    List<ChatMessage>? messages,
    List<AIInsight>? insights,
    String? error,
  }) {
    return AiChatState(
      isLoading: isLoading ?? this.isLoading,
      messages: messages ?? this.messages,
      insights: insights ?? this.insights,
      error: error,
    );
  }
}

// AI Chat Notifier
class AiChatNotifier extends StateNotifier<AiChatState> {
  final ApiService _apiService;

  AiChatNotifier(this._apiService) : super(const AiChatState());

  Future<void> sendMessage(String message) async {
    // Add user message immediately
    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: '', // Will be set by API
      messageType: 'user',
      content: message,
      createdAt: DateTime.now().toIso8601String(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
    );

    try {
      final response = await _apiService.chatWithAI(message);
      final aiMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: '', // Will be set by API
        messageType: 'assistant',
        content: response.response,
        createdAt: DateTime.now().toIso8601String(),
      );

      state = state.copyWith(
        messages: [...state.messages, aiMessage],
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadChatHistory() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // For now, we'll load from local state since there's no specific chat history API
      // This could be enhanced later with a proper chat history endpoint
      state = state.copyWith(
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadInsights() async {
    try {
      final insights = await _apiService.getAIInsights();
      state = state.copyWith(insights: insights);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Provider
final aiChatNotifierProvider = StateNotifierProvider<AiChatNotifier, AiChatState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return AiChatNotifier(apiService);
});