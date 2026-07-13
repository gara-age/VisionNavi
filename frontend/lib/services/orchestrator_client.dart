import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/session_models.dart';

class OrchestratorClient {
  OrchestratorClient({
    String host = '127.0.0.1',
    int port = 8010,
  })  : _httpBaseUri = Uri.parse('http://$host:$port'),
        _wsBaseUri = Uri.parse('ws://$host:$port');

  final Uri _httpBaseUri;
  final Uri _wsBaseUri;

  String _errorMessage(String fallbackMessage, http.Response response) {
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = payload['detail'];
      if (detail is String && detail.isNotEmpty) {
        return '$fallbackMessage: $detail';
      }
    } catch (_) {
      // Fall back to the HTTP status when the response body is not JSON.
    }
    return '$fallbackMessage: ${response.statusCode}';
  }

  Future<CanonicalCommand> canonicalizeCommand(
    String text, {
    String inputMode = 'text',
    String? preferredLanguage,
  }) async {
    final response = await http.post(
      _httpBaseUri.resolve('/pipeline/canonicalize'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'input_mode': inputMode,
        'text': text,
        if (preferredLanguage != null) 'preferred_language': preferredLanguage,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
          _errorMessage('Failed to canonicalize command', response));
    }

    return CanonicalCommand.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<RunCommandResponse> runCommand(
    String text, {
    String inputMode = 'text',
    String? preferredLanguage,
  }) async {
    final response = await http.post(
      _httpBaseUri.resolve('/pipeline/run'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'input_mode': inputMode,
        'text': text,
        if (preferredLanguage != null) 'preferred_language': preferredLanguage,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_errorMessage('Failed to run command', response));
    }

    return RunCommandResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<RunCommandResponse> runCanonicalCommand(
    CanonicalCommand command, {
    bool confirmed = false,
    String? executionBackend,
  }) async {
    final response = await http.post(
      _httpBaseUri.resolve('/pipeline/run'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'canonical_command': command.toJson(),
        'confirmed': confirmed,
        if (executionBackend != null) 'execution_backend': executionBackend,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
          _errorMessage('Failed to run canonical command', response));
    }

    return RunCommandResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<AudioTranscriptionResponse> transcribeAudioFile(
    String filePath, {
    String? languageHint,
  }) async {
    final response = await http.post(
      _httpBaseUri.resolve('/pipeline/transcribe-audio'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'file_path': filePath,
        if (languageHint != null) 'language_hint': languageHint,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
          _errorMessage('Failed to transcribe audio file', response));
    }

    return AudioTranscriptionResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<PopupSummaryResponse> generatePopupSummary({
    required CanonicalCommand command,
    required Map<String, dynamic> result,
    required String language,
  }) async {
    final response = await http.post(
      _httpBaseUri.resolve('/pipeline/popup-summary'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'command': command.toJson(),
        'result': result,
        'language': language,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
          _errorMessage('Failed to generate popup summary', response));
    }

    return PopupSummaryResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<WakeWordStatusResponse> fetchWakeWordStatus() async {
    final response =
        await http.get(_httpBaseUri.resolve('/pipeline/wakeword/status'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
          _errorMessage('Failed to fetch wakeword status', response));
    }
    return WakeWordStatusResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AudioDiagnosticsResponse> fetchAudioDiagnostics() async {
    final response =
        await http.get(_httpBaseUri.resolve('/pipeline/audio-diagnostics'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
          _errorMessage('Failed to fetch audio diagnostics', response));
    }
    return AudioDiagnosticsResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<WakeWordStatusResponse> startWakeWord({
    required String language,
    String? phrase,
    String? profileId,
    double? threshold,
  }) async {
    final response = await http.post(
      _httpBaseUri.resolve('/pipeline/wakeword/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'language': language,
        if (phrase != null) 'phrase': phrase,
        if (profileId != null) 'profile_id': profileId,
        if (threshold != null) 'threshold': threshold,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
          _errorMessage('Failed to start wakeword listener', response));
    }
    return WakeWordStatusResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<WakeWordStatusResponse> stopWakeWord() async {
    final response =
        await http.post(_httpBaseUri.resolve('/pipeline/wakeword/stop'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
          _errorMessage('Failed to stop wakeword listener', response));
    }
    return WakeWordStatusResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<WakeWordStatusResponse> acknowledgeWakeWord() async {
    final response =
        await http.post(_httpBaseUri.resolve('/pipeline/wakeword/acknowledge'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
          _errorMessage('Failed to acknowledge wakeword detection', response));
    }
    return WakeWordStatusResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<SessionSnapshot> fetchSession(String sessionId) async {
    final response =
        await http.get(_httpBaseUri.resolve('/pipeline/sessions/$sessionId'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_errorMessage('Failed to fetch session', response));
    }
    return SessionSnapshot.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Stream<SessionEvent> watchSession(String sessionId) async* {
    var lastSequence = 0;
    try {
      final socketUri = _wsBaseUri.replace(
        scheme: 'ws',
        path: '/pipeline/sessions/$sessionId/events',
        fragment: '',
      );
      final socket = await WebSocket.connect(socketUri.toString());

      try {
        await for (final message in socket) {
          if (message is! String) {
            continue;
          }

          final decoded = jsonDecode(message) as Map<String, dynamic>;
          if (decoded['type'] == 'error') {
            throw HttpException(
                decoded['detail'] as String? ?? 'Unknown session error');
          }

          final sequence = decoded['sequence'];
          if (sequence is int && sequence > lastSequence) {
            lastSequence = sequence;
          }
          yield SessionEvent.fromJson(decoded);
        }
      } finally {
        await socket.close();
      }

      final finalSnapshot = await fetchSession(sessionId);
      for (final event in finalSnapshot.events) {
        if (event.sequence <= lastSequence) {
          continue;
        }
        lastSequence = event.sequence;
        yield SessionEvent(
          sequence: event.sequence,
          type: event.type,
          phase: event.phase,
          detail: event.detail,
          status: finalSnapshot.status,
          currentPhase: finalSnapshot.currentPhase,
          payload: event.payload,
          metadata: finalSnapshot.metadata,
          result: finalSnapshot.result,
        );
      }

      if (finalSnapshot.status == 'completed' ||
          finalSnapshot.status == 'failed' ||
          finalSnapshot.status == 'canceled') {
        return;
      }
    } on WebSocketException {
      // Fall back to polling when WebSocket upgrade is not available.
    } on SocketException {
      // Fall back to polling when the socket connection cannot be established.
    } on HttpException {
      // Fall back to polling when the backend rejects the WebSocket path.
    }

    while (true) {
      final snapshot = await fetchSession(sessionId);
      for (final event in snapshot.events) {
        if (event.sequence <= lastSequence) {
          continue;
        }
        lastSequence = event.sequence;
        yield SessionEvent(
          sequence: event.sequence,
          type: event.type,
          phase: event.phase,
          detail: event.detail,
          status: snapshot.status,
          currentPhase: snapshot.currentPhase,
          payload: event.payload,
          metadata: snapshot.metadata,
          result: snapshot.result,
        );
      }

      if (snapshot.status == 'completed' ||
          snapshot.status == 'failed' ||
          snapshot.status == 'canceled') {
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }

  Future<void> stopSession(String sessionId) async {
    final response = await http
        .post(_httpBaseUri.resolve('/pipeline/sessions/$sessionId/stop'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Failed to stop session: ${response.statusCode}');
    }
  }
}
