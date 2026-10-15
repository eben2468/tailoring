import '../../../core/network/api_client.dart';
import '../../sync/data/sync_engine.dart';
import '../domain/ai.dart';

/// The AI assistant (docs/API_REFERENCE.md §16). Figures and chat need a connection (they are
/// calculated by the AI service); insight cards arrive with the sync and can be dismissed offline.
class AiApi {
  const AiApi(this._client, this._sync);

  final ApiClient _client;
  final SyncEngine _sync;

  Future<AiOverview> overview() async => AiOverview((await _client.get('/ai/overview') as Map).cast<String, dynamic>());

  /// Predicted finish and delay risk, or null when the job is not in production.
  Future<Map<String, dynamic>?> forecast(String jobId) async => (await _client.get('/jobs/$jobId/ai/forecast') as Map?)?.cast<String, dynamic>();

  Future<List<StageEstimate>> estimate(int jobTypeId, int quantity) async {
    final data = await _client.post('/ai/estimate', body: {'job_type_id': jobTypeId, 'quantity': quantity}) as Map;
    return [for (final t in (data['tasks'] as List).cast<Map<String, dynamic>>()) StageEstimate.fromJson(t)];
  }

  Future<ChatMessage> ask(List<ChatMessage> conversation) async {
    final data = await _client.post('/ai/chat', body: {'messages': [for (final m in conversation.skip(conversation.length > 8 ? conversation.length - 8 : 0)) m.toJson()]}) as Map;
    return ChatMessage(
      fromUser: false,
      text: data['answer'] as String,
      source: data['source'] as String?,
      jobNumbers: (data['job_numbers'] as List? ?? const []).cast<String>(),
    );
  }

  Future<void> dismiss(Insight i) => _sync.perform(label: 'Dismiss: ${i.title}', method: 'POST', path: '/ai/insights/${i.id}/dismiss');

  Future<void> markSeen(Insight i) async {
    if (!i.isNew) return;
    await _sync.perform(label: 'Seen: ${i.title}', method: 'POST', path: '/ai/insights/${i.id}/seen');
  }
}
