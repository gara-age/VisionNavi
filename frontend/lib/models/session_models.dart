class CanonicalCommand {
  const CanonicalCommand({
    required this.inputMode,
    required this.rawText,
    required this.normalizedText,
    required this.taskDomain,
    required this.intent,
    required this.riskLevel,
    required this.requiresConfirmation,
    this.targetApp,
    this.notes = const [],
  });

  factory CanonicalCommand.fromJson(Map<String, dynamic> json) {
    return CanonicalCommand(
      inputMode: json['input_mode'] as String,
      rawText: json['raw_text'] as String,
      normalizedText: json['normalized_text'] as String,
      taskDomain: json['task_domain'] as String,
      intent: json['intent'] as String,
      riskLevel: json['risk_level'] as String,
      requiresConfirmation: json['requires_confirmation'] as bool,
      targetApp: json['target_app'] as String?,
      notes: (json['notes'] as List<dynamic>? ?? const []).cast<String>(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'input_mode': inputMode,
      'raw_text': rawText,
      'normalized_text': normalizedText,
      'task_domain': taskDomain,
      'intent': intent,
      'risk_level': riskLevel,
      'requires_confirmation': requiresConfirmation,
      'target_app': targetApp,
      'notes': notes,
    };
  }

  final String inputMode;
  final String rawText;
  final String normalizedText;
  final String taskDomain;
  final String intent;
  final String riskLevel;
  final bool requiresConfirmation;
  final String? targetApp;
  final List<String> notes;
}

class SessionEvent {
  const SessionEvent({
    required this.sequence,
    required this.type,
    required this.phase,
    required this.detail,
    required this.status,
    this.currentPhase,
    this.payload,
    this.metadata,
    this.result,
  });

  factory SessionEvent.fromJson(Map<String, dynamic> json) {
    return SessionEvent(
      sequence: json['sequence'] as int,
      type: json['type'] as String,
      phase: json['phase'] as String,
      detail: json['detail'] as String,
      status: json['status'] as String? ?? 'queued',
      currentPhase: json['current_phase'] as String?,
      payload: (json['payload'] as Map?)?.cast<String, dynamic>(),
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>(),
      result: json['result'] as Map<String, dynamic>?,
    );
  }

  final int sequence;
  final String type;
  final String phase;
  final String detail;
  final String status;
  final String? currentPhase;
  final Map<String, dynamic>? payload;
  final Map<String, dynamic>? metadata;
  final Map<String, dynamic>? result;
}

class SessionSnapshot {
  const SessionSnapshot({
    required this.sessionId,
    required this.status,
    required this.currentPhase,
    required this.command,
    required this.steps,
    required this.events,
    required this.metadata,
    this.result,
  });

  factory SessionSnapshot.fromJson(Map<String, dynamic> json) {
    return SessionSnapshot(
      sessionId: json['session_id'] as String,
      status: json['status'] as String,
      currentPhase: json['current_phase'] as String,
      command:
          CanonicalCommand.fromJson(json['command'] as Map<String, dynamic>),
      steps: (json['steps'] as List<dynamic>? ?? const [])
          .map((item) => (item as Map<String, dynamic>).cast<String, String>())
          .toList(),
      events: (json['events'] as List<dynamic>? ?? const [])
          .map((item) => SessionEvent.fromJson(item as Map<String, dynamic>))
          .toList(),
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
      result: json['result'] as Map<String, dynamic>?,
    );
  }

  final String sessionId;
  final String status;
  final String currentPhase;
  final CanonicalCommand command;
  final List<Map<String, String>> steps;
  final List<SessionEvent> events;
  final Map<String, dynamic> metadata;
  final Map<String, dynamic>? result;
}

class RunCommandResponse {
  const RunCommandResponse({
    required this.sessionId,
    required this.command,
    required this.session,
  });

  factory RunCommandResponse.fromJson(Map<String, dynamic> json) {
    return RunCommandResponse(
      sessionId: json['session_id'] as String,
      command:
          CanonicalCommand.fromJson(json['command'] as Map<String, dynamic>),
      session:
          SessionSnapshot.fromJson(json['session'] as Map<String, dynamic>),
    );
  }

  final String sessionId;
  final CanonicalCommand command;
  final SessionSnapshot session;
}

class AudioTranscriptionResponse {
  const AudioTranscriptionResponse({
    required this.text,
    required this.filePath,
    required this.model,
    this.detectedLanguage,
    this.languageProbability,
    this.durationSeconds,
  });

  factory AudioTranscriptionResponse.fromJson(Map<String, dynamic> json) {
    return AudioTranscriptionResponse(
      text: json['text'] as String,
      filePath: json['file_path'] as String,
      model: json['model'] as String,
      detectedLanguage: json['detected_language'] as String?,
      languageProbability: (json['language_probability'] as num?)?.toDouble(),
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
    );
  }

  final String text;
  final String filePath;
  final String model;
  final String? detectedLanguage;
  final double? languageProbability;
  final double? durationSeconds;
}

class PopupSummaryResponse {
  const PopupSummaryResponse({
    required this.title,
    required this.message,
    this.notes = const [],
  });

  factory PopupSummaryResponse.fromJson(Map<String, dynamic> json) {
    return PopupSummaryResponse(
      title: json['title'] as String,
      message: json['message'] as String,
      notes: (json['notes'] as List<dynamic>? ?? const []).cast<String>(),
    );
  }

  final String title;
  final String message;
  final List<String> notes;
}
