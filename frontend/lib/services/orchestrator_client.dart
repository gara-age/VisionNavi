import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/session_models.dart';

class OrchestratorClient {
  OrchestratorClient({
    String host = '127.0.0.1',
    int port = 8000,
  }) : _httpBaseUri = Uri.parse('http://$host:$port'),
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

  Future<CanonicalCommand> canonicalizeCommand(String text, {String inputMode = 'text'}) async {
    final response = await http.post(
      _httpBaseUri.resolve('/pipeline/canonicalize'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'input_mode': inputMode,
        'text': text,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_errorMessage('Failed to canonicalize command', response));
    }

    return CanonicalCommand.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<RunCommandResponse> runCommand(String text, {String inputMode = 'text'}) async {
    final response = await http.post(
      _httpBaseUri.resolve('/pipeline/run'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'input_mode': inputMode,
        'text': text,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_errorMessage('Failed to run command', response));
    }

    return RunCommandResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<RunCommandResponse> runCanonicalCommand(
    CanonicalCommand command, {
    bool confirmed = false,
  }) async {
    final response = await http.post(
      _httpBaseUri.resolve('/pipeline/run'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'canonical_command': command.toJson(),
        'confirmed': confirmed,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_errorMessage('Failed to run canonical command', response));
    }

    return RunCommandResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Stream<SessionEvent> watchSession(String sessionId) async* {
    final socket = await WebSocket.connect(
      _wsBaseUri.resolve('/pipeline/sessions/$sessionId/events').toString(),
    );

    try {
      await for (final message in socket) {
        if (message is! String) {
          continue;
        }

        final decoded = jsonDecode(message) as Map<String, dynamic>;
        if (decoded['type'] == 'error') {
          throw HttpException(decoded['detail'] as String? ?? 'Unknown session error');
        }

        yield SessionEvent.fromJson(decoded);
      }
    } finally {
      await socket.close();
    }
  }

  Future<void> stopSession(String sessionId) async {
    final response = await http.post(_httpBaseUri.resolve('/pipeline/sessions/$sessionId/stop'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Failed to stop session: ${response.statusCode}');
    }
  }
}
