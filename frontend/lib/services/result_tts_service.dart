import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

class ResultTtsService {
  ResultTtsService._();

  static final ResultTtsService instance = ResultTtsService._();

  final AudioPlayer _player = AudioPlayer();

  Future<bool> speak({
    required String text,
    required String language,
    required double speed,
    required double volume,
    String? provider,
    String? voice,
  }) async {
    if (!Platform.isWindows) {
      return false;
    }

    final normalized = text.trim();
    if (normalized.isEmpty) {
      return false;
    }

    try {
      final projectRoot = _resolveProjectRoot();
      final payload = await _requestSynthesis(
        projectRoot: projectRoot,
        text: normalized,
        language: language.trim().toLowerCase(),
        speed: speed,
        volume: volume,
        provider: provider,
        voice: voice,
      );
      if (payload == null) {
        return false;
      }
      if (payload['ok'] != true) {
        return false;
      }
      final audioPath = payload['audio_path']?.toString();
      if (audioPath == null || audioPath.isEmpty) {
        return false;
      }
      final file = File(audioPath);
      if (!await file.exists()) {
        return false;
      }

      await _player.stop();
      await _player.setVolume(volume.clamp(0.0, 1.0));
      final completed = Completer<void>();
      late final StreamSubscription<void> subscription;
      subscription = _player.onPlayerComplete.listen((_) {
        if (!completed.isCompleted) {
          completed.complete();
        }
      });
      await _player.play(DeviceFileSource(file.path));
      try {
        await completed.future.timeout(const Duration(seconds: 12));
      } on TimeoutException {
        // Do not block the main flow indefinitely if the player misses an event.
      } finally {
        await subscription.cancel();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _requestSynthesis({
    required Directory projectRoot,
    required String text,
    required String language,
    required double speed,
    required double volume,
    String? provider,
    String? voice,
  }) async {
    final uri = Uri.parse('http://127.0.0.1:8011/synthesize');
    final body = jsonEncode({
      'text': text,
      'language': language,
      'provider': provider,
      'voice': voice,
      'speed': speed,
      'volume': volume,
    });

    Future<Map<String, dynamic>?> invokeHttp() async {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: body,
          )
          .timeout(const Duration(seconds: 180));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return null;
    }

    try {
      return await invokeHttp();
    } catch (_) {
      final started = await _ensureWorkerStarted(projectRoot);
      if (!started) {
        return null;
      }
      try {
        return await invokeHttp();
      } catch (_) {
        return null;
      }
    }
  }

  Future<bool> _ensureWorkerStarted(Directory projectRoot) async {
    final scriptPath =
        File('${projectRoot.path}\\scripts\\start_tts_worker.ps1');
    if (!await scriptPath.exists()) {
      return false;
    }
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptPath.path,
        '-Port',
        '8011',
        '-Hidden',
        '-StartupTimeoutSec',
        '120',
      ],
      workingDirectory: projectRoot.path,
    );
    return result.exitCode == 0;
  }

  Directory _resolveProjectRoot() {
    final candidates = <Directory>[
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];

    for (final base in candidates) {
      Directory? current = base;
      for (var depth = 0; depth < 8 && current != null; depth++) {
        final script =
            File('${current.path}\\scripts\\render_guidance_tts.ps1');
        if (script.existsSync()) {
          return current;
        }
        final parent = current.parent;
        if (parent.path == current.path) {
          break;
        }
        current = parent;
      }
    }

    return Directory.current;
  }
}
