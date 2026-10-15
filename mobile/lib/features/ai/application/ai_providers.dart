import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../sync/application/sync_providers.dart';
import '../data/ai_api.dart';
import '../domain/ai.dart';

final aiApiProvider = Provider<AiApi>((ref) => AiApi(ref.watch(apiClientProvider), ref.watch(syncEngineProvider)));

/// Active insight cards from the local copy (works offline).
final insightsProvider = Provider<AsyncValue<List<Insight>>>((ref) => fromStore(ref, (p) => [for (final i in p.insights()) Insight.fromJson(i)]));

/// Live figures from the AI service (online).
final aiOverviewProvider = FutureProvider.autoDispose<AiOverview>((ref) => ref.watch(aiApiProvider).overview());

final jobForecastProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, jobId) => ref.watch(aiApiProvider).forecast(jobId));

/// The conversation on the AI screen (kept while the app runs).
final chatProvider = NotifierProvider<ChatController, ChatState>(ChatController.new);

class ChatState {
  const ChatState({this.messages = const [], this.busy = false, this.error});

  final List<ChatMessage> messages;
  final bool busy;
  final String? error;
}

class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState();

  Future<void> ask(String question) async {
    final text = question.trim();
    if (text.isEmpty || state.busy) return;
    final conversation = [...state.messages, ChatMessage(fromUser: true, text: text)];
    state = ChatState(messages: conversation, busy: true);
    try {
      final answer = await ref.read(aiApiProvider).ask(conversation);
      state = ChatState(messages: [...conversation, answer]);
    } on ApiException catch (e) {
      state = ChatState(messages: conversation, error: e.message);
    }
  }

  void clear() => state = const ChatState();
}
