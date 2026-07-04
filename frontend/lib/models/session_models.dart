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

class WakeWordStatusResponse {
  const WakeWordStatusResponse({
    required this.backend,
    required this.running,
    required this.available,
    required this.pendingDetection,
    this.language,
    this.profileId,
    this.phrase,
    this.modelPath,
    this.threshold,
    this.debounceSeconds,
    this.lastError,
    this.lastDetectionAt,
    this.pendingDetectionPhrase,
  });

  factory WakeWordStatusResponse.fromJson(Map<String, dynamic> json) {
    return WakeWordStatusResponse(
      backend: json['backend'] as String? ?? 'livekit-wakeword',
      running: json['running'] as bool? ?? false,
      available: json['available'] as bool? ?? false,
      pendingDetection: json['pending_detection'] as bool? ?? false,
      language: json['language'] as String?,
      profileId: json['profile_id'] as String?,
      phrase: json['phrase'] as String?,
      modelPath: json['model_path'] as String?,
      threshold: (json['threshold'] as num?)?.toDouble(),
      debounceSeconds: (json['debounce_seconds'] as num?)?.toDouble(),
      lastError: json['last_error'] as String?,
      lastDetectionAt: json['last_detection_at'] as String?,
      pendingDetectionPhrase: json['pending_detection_phrase'] as String?,
    );
  }

  final String backend;
  final bool running;
  final bool available;
  final bool pendingDetection;
  final String? language;
  final String? profileId;
  final String? phrase;
  final String? modelPath;
  final double? threshold;
  final double? debounceSeconds;
  final String? lastError;
  final String? lastDetectionAt;
  final String? pendingDetectionPhrase;
}

class AudioDiagnosticEndpoint {
  const AudioDiagnosticEndpoint({
    required this.status,
    required this.className,
    required this.friendlyName,
    required this.instanceId,
  });

  factory AudioDiagnosticEndpoint.fromJson(Map<String, dynamic> json) {
    return AudioDiagnosticEndpoint(
      status: json['status'] as String? ?? '',
      className: json['class'] as String? ?? json['class_name'] as String? ?? '',
      friendlyName: json['friendly_name'] as String? ?? '',
      instanceId: json['instance_id'] as String? ?? '',
    );
  }

  final String status;
  final String className;
  final String friendlyName;
  final String instanceId;
}

class AudioDiagnosticsSummary {
  const AudioDiagnosticsSummary({
    required this.okCount,
    required this.unknownCount,
    required this.remoteAudioCount,
    required this.inputCandidateCount,
    required this.hasAnyOkEndpoint,
    required this.hasOkInputCandidate,
  });

  factory AudioDiagnosticsSummary.fromJson(Map<String, dynamic> json) {
    return AudioDiagnosticsSummary(
      okCount: json['ok_count'] as int? ?? 0,
      unknownCount: json['unknown_count'] as int? ?? 0,
      remoteAudioCount: json['remote_audio_count'] as int? ?? 0,
      inputCandidateCount: json['input_candidate_count'] as int? ?? 0,
      hasAnyOkEndpoint: json['has_any_ok_endpoint'] as bool? ?? false,
      hasOkInputCandidate: json['has_ok_input_candidate'] as bool? ?? false,
    );
  }

  final int okCount;
  final int unknownCount;
  final int remoteAudioCount;
  final int inputCandidateCount;
  final bool hasAnyOkEndpoint;
  final bool hasOkInputCandidate;
}

class AudioDiagnosticsResponse {
  const AudioDiagnosticsResponse({
    required this.platform,
    required this.inputEndpoints,
    required this.summary,
  });

  factory AudioDiagnosticsResponse.fromJson(Map<String, dynamic> json) {
    return AudioDiagnosticsResponse(
      platform: json['platform'] as String? ?? 'windows',
      inputEndpoints: (json['input_endpoints'] as List<dynamic>? ?? const [])
          .map((item) => AudioDiagnosticEndpoint.fromJson(item as Map<String, dynamic>))
          .toList(),
      summary: AudioDiagnosticsSummary.fromJson(
        (json['summary'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  final String platform;
  final List<AudioDiagnosticEndpoint> inputEndpoints;
  final AudioDiagnosticsSummary summary;
}
