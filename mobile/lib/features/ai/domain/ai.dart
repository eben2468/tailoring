/// An insight card from the AI service (synced `ai_insights` rows). The AI only proposes; the owner acts.
class Insight {
  const Insight({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.body,
    required this.payload,
    required this.status,
    required this.generatedAt,
    this.entityType,
    this.entityId,
  });

  factory Insight.fromJson(Map<String, dynamic> json) => Insight(
        id: (json['id'] as num).toInt(),
        type: json['insight_type'] as String,
        severity: json['severity'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        status: json['insight_status'] as String,
        generatedAt: DateTime.parse(json['generated_at'] as String).toLocal(),
        entityType: json['entity_type'] as String?,
        entityId: json['entity_id'] as String?,
      );

  final int id;

  /// delay_risk · priority · workload · estimate_accuracy · inventory_forecast
  final String type;

  /// info · advice · warning · critical
  final String severity;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final String status;
  final DateTime generatedAt;
  final String? entityType;
  final String? entityId;

  bool get isNew => status == 'new';

  /// The suggested action: {type: open_job | restock | open_calendar | open_templates, label, …}.
  Map<String, dynamic>? get action => (payload['action'] as Map?)?.cast<String, dynamic>();
}

/// GET /ai/overview (calculated by the AI service; online only).
class AiOverview {
  const AiOverview(this.data);

  final Map<String, dynamic> data;

  Map<String, dynamic> get accuracy => (data['accuracy'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get workload => (data['workload'] as Map?)?.cast<String, dynamic>() ?? const {};
  int get completedJobs => (data['completed_jobs'] as num? ?? 0).toInt();
  bool get llmEnabled => ((data['llm'] as Map?)?['enabled'] as bool?) ?? false;

  List<Map<String, dynamic>> list(String key) => (data[key] as List? ?? const []).cast<Map<dynamic, dynamic>>().map((m) => m.cast<String, dynamic>()).toList();
}

/// One chat message.
class ChatMessage {
  const ChatMessage({required this.fromUser, required this.text, this.source, this.jobNumbers = const []});

  final bool fromUser;
  final String text;

  /// 'analytics' or the model name, for the assistant's answers.
  final String? source;
  final List<String> jobNumbers;

  Map<String, dynamic> toJson() => {'role': fromUser ? 'user' : 'assistant', 'text': text};
}

/// POST /ai/estimate, per stage.
class StageEstimate {
  const StageEstimate({required this.taskTypeId, required this.name, required this.suggestedSeconds, required this.basis, required this.sampleSize, required this.explanation, this.confidence});

  factory StageEstimate.fromJson(Map<String, dynamic> json) => StageEstimate(
        taskTypeId: (json['task_type_id'] as num).toInt(),
        name: json['name'] as String,
        suggestedSeconds: (json['suggested_seconds'] as num).toInt(),
        basis: json['basis'] as String,
        sampleSize: (json['sample_size'] as num? ?? 0).toInt(),
        confidence: (json['confidence'] as num?)?.toDouble(),
        explanation: json['explanation'] as String? ?? '',
      );

  final int taskTypeId;
  final String name;
  final int suggestedSeconds;

  /// history (learned from completed jobs) · defaults (template hours kept)
  final String basis;
  final int sampleSize;
  final double? confidence;
  final String explanation;

  bool get fromHistory => basis == 'history';
}
