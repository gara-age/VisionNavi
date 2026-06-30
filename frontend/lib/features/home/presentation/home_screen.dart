import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/typography.dart';
import '../models/home_user_settings.dart';
import '../services/home_settings_store.dart';
import '../../../models/session_models.dart';
import '../../../services/orchestrator_client.dart';
import '../../../services/taskbar_popup_service.dart';
import 'widgets/action_panel.dart';
import 'widgets/home_settings_dialog.dart';
import 'widgets/status_card.dart';
import 'widgets/text_command_composer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController(
    text:
        'Search Naver for Incheon youth monthly rent support and read the conditions.',
  );
  final OrchestratorClient _client = OrchestratorClient();
  final SpeechToText _speechToText = SpeechToText();

  StreamSubscription<SessionEvent>? _sessionSubscription;
  CanonicalCommand? _command;
  List<SessionEvent> _events = const [];
  String _status = 'Idle';
  String _phase = 'idle';
  String? _sessionId;
  String? _error;
  Map<String, dynamic>? _result;
  Map<String, dynamic> _sessionMetadata = const {};
  bool _isSubmitting = false;
  bool _isCanonicalizing = false;
  String _selectedExecutionChannel = 'external';
  bool _debugMode = false;
  HomeUserSettings _userSettings = const HomeUserSettings();
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _speechBusy = false;
  String? _speechMessage;
  String? _speechLocaleId;
  String? _attachedVoiceFilePath;
  String? _lastExecutionPopupKey;

  @override
  void initState() {
    super.initState();
    unawaited(_loadUserSettings());
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _speechToText.cancel();
    _controller.dispose();
    super.dispose();
  }

  String _policySummary(CanonicalCommand command) {
    if (command.requiresConfirmation) {
      return 'Approval is required before execution because this command changes system state or carries elevated risk.';
    }
    if (command.intent == 'change_system_setting') {
      return 'Auto-run enabled for reversible setting changes such as dark mode.';
    }
    if (command.riskLevel == 'medium') {
      return 'Medium-risk action is allowed to run automatically by current policy.';
    }
    return 'This command can run immediately.';
  }

  Future<void> _interpretCommand() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isCanonicalizing || _isSubmitting) {
      return;
    }

    setState(() {
      _isCanonicalizing = true;
      _error = null;
      _command = null;
      _result = null;
      _sessionMetadata = const {};
      _status = 'Interpreting';
      _phase = 'canonicalize';
    });

    try {
      final command = await _client.canonicalizeCommand(text);
      if (!mounted) {
        return;
      }
      setState(() {
        _command = command;
        _status = 'Ready';
        _phase = 'review';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _status = 'Error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCanonicalizing = false;
        });
      }
    }
  }

  Future<void> _runReviewedCommand({bool confirmed = false}) async {
    final command = _command;
    if (command == null || _isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
      _events = const [];
      _result = null;
      _sessionMetadata = const {};
      _status = 'Starting';
      _phase = 'queued';
    });

    try {
      final response = await _client.runCanonicalCommand(
        command,
        confirmed: confirmed,
        executionBackend: _requestedExecutionBackendForCommand(command),
      );
      await _sessionSubscription?.cancel();

      setState(() {
        _command = response.command;
        _sessionId = response.sessionId;
        _status = _toTitleCase(response.session.status);
        _phase = response.session.currentPhase;
        _events = response.session.events;
        _result = response.session.result;
        _sessionMetadata = response.session.metadata;
      });
      _maybeShowExecutionPopup();

      _sessionSubscription = _client.watchSession(response.sessionId).listen(
        (event) {
          if (!mounted) {
            return;
          }

          setState(() {
            final alreadySeen =
                _events.any((existing) => existing.sequence == event.sequence);
            if (!alreadySeen) {
              _events = [..._events, event];
            }
            _status = _toTitleCase(event.status);
            _phase = event.currentPhase ?? event.phase;
            _result = event.result ?? _result;
            _sessionMetadata = event.metadata ?? _sessionMetadata;
            _isSubmitting =
                event.status == 'queued' || event.status == 'running';
          });
          _maybeShowExecutionPopup();
        },
        onError: (Object error) {
          if (!mounted) {
            return;
          }

          setState(() {
            _error = error.toString();
            _status = 'Error';
            _isSubmitting = false;
          });
        },
        onDone: () {
          if (!mounted) {
            return;
          }
          final sessionId = _sessionId;
          if (sessionId == null) {
            setState(() {
              _isSubmitting = false;
            });
            return;
          }
          unawaited(_syncFinalSessionSnapshot(sessionId));
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _status = 'Error';
        _isSubmitting = false;
      });
    }
  }

  Future<void> _approveAndRun() async {
    final command = _command;
    if (command == null) {
      return;
    }

    final approved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Approval Required'),
          content: Text(
            'This command is classified as ${command.riskLevel} risk and needs explicit approval before execution.\n\n'
            'Intent: ${command.intent}\n'
            'Command: ${command.normalizedText}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Approve and Run'),
            ),
          ],
        );
      },
    );

    if (approved == true) {
      await _runReviewedCommand(confirmed: true);
    }
  }

  Future<void> _stopSession() async {
    final sessionId = _sessionId;
    if (sessionId == null) {
      return;
    }

    try {
      await _client.stopSession(sessionId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    }
  }

  Future<void> _syncFinalSessionSnapshot(String sessionId) async {
    try {
      final snapshot = await _client.fetchSession(sessionId);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _toTitleCase(snapshot.status);
        _phase = snapshot.currentPhase;
        _events = snapshot.events;
        _result = snapshot.result;
        _sessionMetadata = snapshot.metadata;
        _isSubmitting = false;
      });
      _maybeShowExecutionPopup();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  String _toTitleCase(String value) {
    if (value.isEmpty) {
      return value;
    }
    return value[0].toUpperCase() + value.substring(1);
  }

  void _maybeShowExecutionPopup() {
    final sessionId = _sessionId;
    final result = _result;
    final command = _command;
    final status = _status.toLowerCase();
    if (sessionId == null || result == null || command == null) {
      return;
    }
    if (status != 'completed' && status != 'error' && status != 'canceled') {
      return;
    }

    final failureReason = _failureReason(result) ?? _error ?? '';
    final popupKey = '$sessionId|$status|$failureReason';
    if (_lastExecutionPopupKey == popupKey) {
      return;
    }
    _lastExecutionPopupKey = popupKey;

    final isFailed = _isFailedResult(result) || status == 'error' || status == 'canceled';
    final popupState =
        isFailed ? TaskbarPopupState.error : TaskbarPopupState.success;
    final popupThemeMode = _userSettings.highContrast
        ? TaskbarPopupThemeMode.contrast
        : (_userSettings.darkTheme
            ? TaskbarPopupThemeMode.dark
            : TaskbarPopupThemeMode.light);

    unawaited(_showExecutionPopupForSession(
      command: command,
      result: result,
      isFailed: isFailed,
      state: popupState,
      themeMode: popupThemeMode,
    ));
  }

  Future<void> _showExecutionPopupForSession({
    required CanonicalCommand command,
    required Map<String, dynamic> result,
    required bool isFailed,
    required TaskbarPopupState state,
    required TaskbarPopupThemeMode themeMode,
  }) async {
    var title = isFailed
        ? _ux('작업 확인 필요', '作業の確認が必要です')
        : _ux('작업이 완료되었습니다', '作業が完了しました');
    var message = _popupMessageForResult(result, isFailed);

    if (!isFailed) {
      try {
        final response = await _client.generatePopupSummary(
          command: command,
          result: result,
          language: _isJapanese ? 'ja' : 'ko',
        );
        if (response.title.trim().isNotEmpty) {
          title = response.title.trim();
        }
        if (response.message.trim().isNotEmpty) {
          message = response.message.trim();
        }
      } catch (_) {
        // Fall back to deterministic user-facing copy when popup-specific LLM summarization fails.
      }
    }

    await _showExecutionPopup(
      title: title,
      message: message,
      state: state,
      themeMode: themeMode,
    );
  }

  String _popupMessageForResult(Map<String, dynamic> result, bool isFailed) {
    if (isFailed) {
      final reason = _failureReason(result);
      if (reason != null && reason.isNotEmpty) {
        return _ux(
          '요청을 끝까지 처리하지 못했습니다. 사유: $reason',
          '依頼を最後まで処理できませんでした。理由: $reason',
        );
      }
      return _ux(
        '요청 처리 중 다시 확인이 필요한 문제가 생겼습니다.',
        '依頼の処理中に再確認が必要な問題が発生しました。',
      );
    }

    final intentMessage = _popupIntentMessage(result);
    if (intentMessage != null) {
      return intentMessage;
    }

    return _popupFallbackSuccessMessage(result);
  }

  String _popupFallbackSuccessMessage(Map<String, dynamic> result) {
    final executor = result['executor']?.toString();
    if (executor == 'desktop') {
      final filePath = result['file_path']?.toString();
      if (filePath != null && filePath.isNotEmpty) {
        return _ux(
          '메모 저장을 마쳤습니다. 앱 화면에서 저장 위치를 확인할 수 있습니다.',
          'メモの保存が終わりました。アプリ画面で保存場所を確認できます。',
        );
      }
      return _ux(
        '데스크톱 작업을 마쳤습니다. 앱 화면에서 결과를 확인해 주세요.',
        'デスクトップ作業が完了しました。アプリ画面で結果を確認してください。',
      );
    }

    return _ux(
      '결과를 준비했습니다. 앱 화면에서 자세한 내용을 확인할 수 있습니다.',
      '結果を準備しました。アプリ画面で詳しい内容を確認できます。',
    );
  }

  String? _popupIntentMessage(Map<String, dynamic> result) {
    final intent = _command?.intent;
    final normalized = (_command?.normalizedText ?? '').toLowerCase();

    switch (intent) {
      case 'search_and_read':
        if (_looksLikeWelfareSearch(normalized)) {
          return _ux(
            '복지나 지원 정보를 찾았습니다. 앱 화면에서 자세한 내용을 확인할 수 있습니다.',
            '福祉や支援の情報を見つけました。アプリ画面で詳しい内容を確認できます。',
          );
        }
        return _ux(
          '검색 결과를 준비했습니다. 앱 화면에서 자세한 내용을 확인할 수 있습니다.',
          '検索結果を準備しました。アプリ画面で詳しい内容を確認できます。',
        );
      case 'find_map_route':
        return _ux(
          '길찾기 결과를 준비했습니다. 앱 화면에서 이동 경로를 확인할 수 있습니다.',
          '経路案内の結果を準備しました。アプリ画面で移動経路を確認できます。',
        );
      case 'open_notepad_and_type':
        return _ux(
          '메모 입력을 마쳤습니다. 앱 화면에서 저장 결과를 확인할 수 있습니다.',
          'メモ入力が完了しました。アプリ画面で保存結果を確認できます。',
        );
      case 'inspect_workspace_files':
        return _ux(
          '파일 확인을 마쳤습니다. 앱 화면에서 목록을 확인할 수 있습니다.',
          'ファイル確認が完了しました。アプリ画面で一覧を確認できます。',
        );
      case 'change_system_setting':
        return _ux(
          '설정 변경을 마쳤습니다. 적용된 내용을 앱 화면에서 확인할 수 있습니다.',
          '設定変更が完了しました。適用内容をアプリ画面で確認できます。',
        );
    }

    final filePath = result['file_path']?.toString();
    if (filePath != null && filePath.isNotEmpty) {
      return _ux(
        '작업을 마쳤습니다. 앱 화면에서 저장 위치를 확인할 수 있습니다.',
        '作業が完了しました。アプリ画面で保存場所を確認できます。',
      );
    }

    return null;
  }

  bool _looksLikeWelfareSearch(String normalizedText) {
    const welfareKeywords = [
      '복지',
      '지원',
      '보조금',
      '월세',
      '청년',
      '고령자',
      '시니어',
      '돌봄',
      '연금',
      'benefit',
      'support',
      'welfare',
      'senior',
      'care',
      'subsidy',
      'rent support',
    ];
    return welfareKeywords.any(normalizedText.contains);
  }
  Future<void> _showExecutionPopup({
    required String title,
    required String message,
    required TaskbarPopupState state,
    required TaskbarPopupThemeMode themeMode,
  }) async {
    final shown = await TaskbarPopupService.instance.show(
      title: title,
      message: message,
      state: state,
      themeMode: themeMode,
      largeText: _userSettings.largeText,
      durationMs: state == TaskbarPopupState.error ? 7000 : 5200,
    );
    if (!shown && mounted) {
      _showSnackBar('$title\n$message');
    }
  }
  String _prettyJson(Object? value) {
    if (value == null) {
      return '{}';
    }
    const encoder = JsonEncoder.withIndent('  ');
    try {
      return encoder.convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  List<Map<String, dynamic>> _mapListFromDynamic(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }

  List<String> _stringListFromDynamic(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return raw.map((item) => item.toString()).toList();
  }

  List<Map<String, dynamic>> _plannedSteps(Map<String, dynamic>? result) {
    return _mapListFromDynamic(result?['planned_steps']);
  }

  List<Map<String, dynamic>> _executedSteps(Map<String, dynamic>? result) {
    return _mapListFromDynamic(result?['executed_steps']);
  }

  List<Map<String, dynamic>> _directoryEntries(Map<String, dynamic>? result) {
    return _mapListFromDynamic(result?['directory_entries']);
  }

  List<String> _planningNotes(Map<String, dynamic>? result) {
    return _stringListFromDynamic(result?['planning_notes']);
  }

  bool _isFailedResult(Map<String, dynamic>? result) {
    return result?['status']?.toString().toLowerCase() == 'failed';
  }

  String? _failureReason(Map<String, dynamic>? result) {
    final explicit = result?['failure_reason']?.toString();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    return _executionSummary(result)?['failure_reason']?.toString();
  }

  Map<String, dynamic>? _validationPayload(Map<String, dynamic>? result) {
    return _jsonMap(result?['validation']);
  }

  Map<String, dynamic>? _bridgeResultPayload(Map<String, dynamic>? result) {
    return _jsonMap(result?['bridge_result']);
  }

  Map<String, dynamic>? _jsonMap(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }
    return null;
  }

  Map<String, dynamic>? _debugTrace(Map<String, dynamic>? result) {
    return _jsonMap(result?['debug_trace']);
  }

  Map<String, dynamic>? _performanceSummary(Map<String, dynamic>? result) {
    return _jsonMap(result?['performance_summary']);
  }

  String? _requestedExecutionBackendForCommand([CanonicalCommand? command]) {
    final activeCommand = command ?? _command;
    if (activeCommand == null || _selectedExecutionChannel == 'auto') {
      return null;
    }

    if (_selectedExecutionChannel == 'internal') {
      if (activeCommand.taskDomain == 'web') {
        return 'internal_browser';
      }
      if (activeCommand.taskDomain == 'desktop') {
        return 'internal_desktop';
      }
      return null;
    }

    if (_selectedExecutionChannel == 'external') {
      if (activeCommand.taskDomain == 'web') {
        return 'external_browser_agent';
      }
      if (activeCommand.taskDomain == 'desktop') {
        return 'external_desktop_agent';
      }
    }
    return null;
  }

  String _selectedExecutionChannelLabel() {
    switch (_selectedExecutionChannel) {
      case 'internal':
        return 'Internal';
      case 'external':
        return 'External';
      default:
        return 'Auto';
    }
  }

  void _applyPresetCommand(String command) {
    setState(() {
      _controller.text = command;
    });
  }

  Future<void> _openSettingsDialog() async {
    final next = await showDialog<HomeUserSettings>(
      context: context,
      barrierDismissible: true,
      builder: (context) => HomeSettingsDialog(initialSettings: _userSettings),
    );
    if (!mounted || next == null) {
      return;
    }
    setState(() {
      _userSettings = next;
      _speechLocaleId = null;
    });
    await HomeSettingsStore.instance.save(next);
  }

  Future<void> _loadUserSettings() async {
    final loaded = await HomeSettingsStore.instance.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _userSettings = loaded;
    });
  }

  Future<void> _pickVoiceFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'audio',
          extensions: ['wav', 'mp3', 'm4a', 'aac', 'ogg', 'flac'],
        ),
      ],
    );
    if (!mounted || file == null) {
      return;
    }
    final stagedPath = await _stageVoiceFileForTranscription(file);
    if (!mounted || stagedPath == null) {
      return;
    }
    setState(() {
      _attachedVoiceFilePath = stagedPath;
      _speechMessage = _ux(
        '음성 파일을 첨부했습니다. 전사를 시작합니다.',
        '音声ファイルを添付しました。文字起こしを始めます。',
      );
    });
    await _transcribeAttachedVoiceFile(stagedPath);
  }

  Future<String?> _stageVoiceFileForTranscription(XFile file) async {
    try {
      final sourcePath = file.path;
      final sourceFile = sourcePath.isEmpty ? null : File(sourcePath);
      final cacheDir = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}visionnavi_audio_uploads',
      );
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final originalName = sourcePath.isNotEmpty
          ? sourcePath.split(Platform.pathSeparator).last
          : file.name;
      final extensionIndex = originalName.lastIndexOf('.');
      final extension = extensionIndex >= 0
          ? originalName.substring(extensionIndex)
          : '.wav';
      final targetPath =
          '${cacheDir.path}${Platform.pathSeparator}voice-${DateTime.now().millisecondsSinceEpoch}$extension';
      final targetFile = File(targetPath);

      if (sourceFile != null && await sourceFile.exists()) {
        await sourceFile.copy(targetPath);
      } else {
        final bytes = await file.readAsBytes();
        await targetFile.writeAsBytes(bytes, flush: true);
      }

      return targetFile.path;
    } catch (error) {
      if (!mounted) {
        return null;
      }
      setState(() {
        _speechMessage = _ux(
          '음성 파일을 준비하지 못했습니다: $error',
          '音声ファイルを準備できませんでした: $error',
        );
      });
      return null;
    }
  }

  Future<void> _transcribeAttachedVoiceFile(String filePath) async {
    if (_speechBusy || _isCanonicalizing || _isSubmitting) {
      return;
    }
    setState(() {
      _speechBusy = true;
      _speechMessage = _ux(
        '음성 파일을 글자로 바꾸는 중입니다.',
        '音声ファイルを文字に変換しています。',
      );
    });
    try {
      final response = await _client.transcribeAudioFile(
        filePath,
        languageHint: _userSettings.preferredLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _controller.text = response.text;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
        _command = null;
        final seconds = response.durationSeconds?.toStringAsFixed(1);
        _speechMessage = seconds == null
            ? _ux('음성 파일을 문장으로 바꿨습니다.', '音声ファイルを文章に変換しました。')
            : _ux(
                '음성 파일 전사가 끝났습니다. 길이: $seconds초',
                '音声ファイルの文字起こしが完了しました。長さ: $seconds秒',
              );
      });
      if (response.text.trim().isNotEmpty) {
        await _interpretCommand();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechMessage = _ux(
          '음성 파일 전사에 실패했습니다: $error',
          '音声ファイルの文字起こしに失敗しました: $error',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _speechBusy = false;
        });
      }
    }
  }

  bool get _isJapanese => _userSettings.preferredLanguage == '일본어';
  String _ux(String ko, String ja) => _isJapanese ? ja : ko;
  String _localizedPreferredLanguageLabel() {
    if (_userSettings.preferredLanguage == '일본어') {
      return _isJapanese ? '日本語' : '일본어';
    }
    return _isJapanese ? '韓国語' : '한국어';
  }
  String _localizedTextScaleLabel() {
    return _userSettings.largeText
        ? _ux('큰 글씨', '大きな文字')
        : _ux('기본 글씨', '표준 글씨');
  }
  String _localizedVoiceButtonLabel() {
    return _userSettings.voiceInputEnabled
        ? _ux('음성 버튼 표시', '音声ボタン表示')
        : _ux('음성 버튼 숨김', '音声ボタン非表示');
  }
  Future<void> _toggleVoiceInput() async {
    if (_speechBusy) {
      return;
    }
    if (_isListening) {
      setState(() {
        _speechBusy = true;
      });
      try {
        await _speechToText.stop();
      } finally {
        if (mounted) {
          setState(() {
            _speechBusy = false;
            _isListening = false;
          });
        }
      }
      return;
    }
    setState(() {
      _speechBusy = true;
      _speechMessage = _ux(
        '음성 입력을 준비하고 있어요.',
        '音声入力を準備しています。',
      );
    });
    try {
      if (!_speechAvailable) {
        final available = await _speechToText.initialize(
          onStatus: _handleSpeechStatus,
          onError: _handleSpeechError,
          debugLogging: false,
        );
        _speechAvailable = available;
        if (!available) {
          if (!mounted) {
            return;
          }
          setState(() {
            _speechMessage = _ux(
              '이 PC에서는 음성 인식을 사용할 수 없습니다.',
              'このPCでは音声認識を利用できません。',
            );
          });
          return;
        }
      }
      if (_speechLocaleId == null) {
        final locales = await _speechToText.locales();
        _speechLocaleId = _pickSpeechLocale(locales);
      }
      await _speechToText.listen(
        onResult: _handleSpeechResult,
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 20),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          cancelOnError: true,
          localeId: _speechLocaleId,
          listenMode: ListenMode.confirmation,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isListening = true;
        _speechMessage = _ux(
          '듣는 중입니다. 말씀을 마치면 텍스트로 채워집니다.',
          '聞き取っています。話し終えると文字で入力されます。',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _speechBusy = false;
        });
      }
    }
  }
  void _handleSpeechStatus(String status) {
    if (!mounted) {
      return;
    }
    final normalized = status.toLowerCase();
    setState(() {
      if (normalized.contains('listening')) {
        _isListening = true;
        _speechMessage = _ux('듣는 중입니다.', '聞き取っています。');
      } else if (normalized.contains('notlistening') ||
          normalized.contains('done')) {
        _isListening = false;
        _speechMessage = _ux('음성 입력이 끝났습니다.', '音声入力が終了しました。');
      }
    });
  }
  void _handleSpeechError(SpeechRecognitionError error) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isListening = false;
      _speechMessage = _ux(
        '음성 입력에 실패했습니다: ${error.errorMsg}',
        '音声入力に失敗しました: ${error.errorMsg}',
      );
    });
  }
  void _handleSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) {
      return;
    }
    setState(() {
      _controller.text = result.recognizedWords;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _command = null;
      _speechMessage = result.finalResult
          ? _ux('음성을 문장으로 바꿨습니다.', '音声を文章に変換しました。')
          : _ux('말한 내용을 받아 적는 중입니다.', '話した内容を書き起こしています。');
    });
    if (result.finalResult &&
        result.recognizedWords.trim().isNotEmpty &&
        !_isCanonicalizing &&
        !_isSubmitting) {
      unawaited(_interpretCommand());
    }
  }
  String? _pickSpeechLocale(List<LocaleName> locales) {
    final preferredPrefix = _isJapanese ? 'ja' : 'ko';
    for (final locale in locales) {
      if (locale.localeId.toLowerCase().startsWith(preferredPrefix)) {
        return locale.localeId;
      }
    }
    for (final locale in locales) {
      if (locale.localeId.toLowerCase().startsWith('en')) {
        return locale.localeId;
      }
    }
    return locales.isNotEmpty ? locales.first.localeId : null;
  }
  Future<void> _runPrimaryUserAction() async {
    if (_isSubmitting || _isCanonicalizing) {
      return;
    }
    if (_command == null) {
      await _interpretCommand();
      return;
    }
    if (_command?.requiresConfirmation == true) {
      await _approveAndRun();
      return;
    }
    await _runReviewedCommand();
  }
  String _userStatusTitle() {
    if (_isSubmitting) {
      return _ux('요청을 처리하고 있어요', 'リクエストを処理しています');
    }
    if (_isCanonicalizing) {
      return _ux('명령을 이해하고 있어요', '命令を理解しています');
    }
    if (_status == 'Completed') {
      return _ux('작업이 끝났어요', '作業が完了しました');
    }
    if (_status == 'Error') {
      return _ux('다시 확인이 필요해요', 'もう一度確認が必要です');
    }
    if (_command != null) {
      return _ux('실행할 준비가 되었어요', '実行する準備ができました');
    }
    return _ux('무엇을 도와드릴까요?', 'どのようにお手伝いしましょうか');
  }
  String _userStatusDetail() {
    if (_isSubmitting) {
      return _ux(
        '검색이나 입력 같은 작업을 차례대로 진행하고 있습니다. 잠시만 기다려 주세요.',
        '検索や入力などの作業を順番に進めています。少しお待ちください。',
      );
    }
    if (_isCanonicalizing) {
      return _ux(
        '입력하신 문장을 이해하기 쉬운 작업 형태로 정리하고 있습니다.',
        '入力された文章を分かりやすい作業の形に整えています。',
      );
    }
    if (_status == 'Completed') {
      return _ux(
        '결과를 확인하고 다시 시도하거나 다른 요청을 이어서 할 수 있습니다.',
        '結果を確認して、再実行したり別の依頼を続けて行えます。',
      );
    }
    if (_status == 'Error') {
      return _ux(
        '인터넷 상태나 요청 문장을 다시 확인해 주세요.',
        'インターネット状態や依頼文をもう一度確認してください。',
      );
    }
    if (_command != null) {
      return _ux('버튼을 누르면 바로 실행합니다.', 'ボタンを押すとすぐに実行します。');
    }
    return _ux(
      '말하거나 입력하면 VisionNavi가 검색과 간단한 작업을 도와드립니다.',
      '話すか入力すると VisionNavi が検索や簡単な作業をお手伝いします。',
    );
  }
  String? _userResultTitle() {
    final result = _result;
    if (result == null) {
      return null;
    }
    final title = result['top_result_title']?.toString();
    if (title != null && title.trim().isNotEmpty) {
      return title.trim();
    }
    final pageTitle = result['page_title']?.toString();
    if (pageTitle != null && pageTitle.trim().isNotEmpty) {
      return pageTitle.trim();
    }
    if (result['executor'] == 'desktop') {
      return _ux('메모 작업 결과', 'メモ作業の結果');
    }
    return _ux('실행 결과', '実行結果');
  }
  String _userResultSummary() {
    final result = _result;
    if (result == null) {
      return _ux(
        '아직 실행 결과가 없습니다. 아래 자주 하는 작업을 고르거나 문장을 직접 입력해 보세요.',
        'まだ実行結果がありません。下のよく使う作業を選ぶか、文章を直接入力してください。',
      );
    }
    final failureReason = _failureReason(result);
    if (_isFailedResult(result) && failureReason != null) {
      return _ux(
        '작업 중 예상과 다르게 흘러 다시 확인이 필요합니다. 다시 시도하거나 다른 표현으로 요청해 주세요.\n\n사유: $failureReason',
        '作業が想定どおりに進まず、再確認が必要です。もう一度試すか別の言い方で依頼してください。\n\n理由: $failureReason',
      );
    }
    final summaryCandidates = [
      result['page_summary'],
      result['summary'],
      result['top_result_snippet'],
      result['observed_text'],
      result['text'],
    ];
    for (final candidate in summaryCandidates) {
      final value = candidate?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    if (result['executor'] == 'desktop') {
      final filePath = result['file_path']?.toString();
      if (filePath != null && filePath.isNotEmpty) {
        return _ux(
          '메모를 저장했습니다.\n저장 위치: $filePath',
          'メモを保存しました。\n保存場所: $filePath',
        );
      }
    }
    return _ux(
      '요청은 끝났지만 바로 보여줄 요약이 충분하지 않습니다. 다시 실행하거나 디버그 모드에서 자세한 기록을 확인할 수 있습니다.',
      '依頼は完了しましたが、すぐに見せられる要約がまだ十分ではありません。再実行するか、デバッグモードで詳しい記録を確認できます。',
    );
  }
  String _headerSubtitle() {
    if (_debugMode) {
      return 'Interpret first, then execute.';
    }
    return _ux(
      '말이나 글로 요청하면 차근차근 도와드려요.',
      '音声や文字で依頼すると、順番にお手伝いします。',
    );
  }
  String _localizedStatusLabel() {
    return _debugMode ? 'Session Status' : _ux('지금 하고 있는 일', 'いま行っていること');
  }
  String _localizedPolicyLabel() {
    return _debugMode ? 'Policy Mode' : _ux('도움 방식', '支援モード');
  }
  String _localizedPolicyValue() {
    if (_debugMode) {
      return _command?.requiresConfirmation == true
          ? 'Approval Required'
          : 'Auto Run';
    }
    return _command?.requiresConfirmation == true
        ? _ux('확인 후 도움', '確認してから支援')
        : _ux('자동 도움', '自動支援');
  }
  String _userChannelBadgeValue() {
    switch (_selectedExecutionChannel) {
      case 'internal':
        return _ux('안정형', '安定型');
      case 'external':
        return _ux('확장형', '拡張型');
      default:
        return _ux('자동 선택', '自動選択');
    }
  }
  String? _attachedVoiceFileName() {
    final path = _attachedVoiceFilePath;
    if (path == null || path.isEmpty) {
      return null;
    }
    return path.split(Platform.pathSeparator).last;
  }

  ThemeData _buildUserScopedTheme(ThemeData baseTheme) {
    if (_debugMode) {
      return baseTheme;
    }

    final darkTheme = _userSettings.darkTheme;
    final highContrast = _userSettings.highContrast;
    final accent = highContrast ? const Color(0xFFFFB800) : AppColors.accent;
    final shellBackground = darkTheme
        ? const Color(0xFF0F1317)
        : (highContrast ? Colors.black : AppColors.shellBackground);
    final contentBackground = darkTheme
        ? const Color(0xFF151B21)
        : (highContrast ? const Color(0xFF0F0F0F) : AppColors.background);
    final surface = darkTheme
        ? const Color(0xFF1B232C)
        : (highContrast ? Colors.black : AppColors.surface);
    final textPrimary = darkTheme || highContrast
        ? Colors.white
        : AppColors.textPrimary;
    final textMuted = darkTheme
        ? const Color(0xFFC2CCD7)
        : (highContrast ? const Color(0xFFE5E5E5) : AppColors.textMuted);
    final border = darkTheme
        ? const Color(0xFF334150)
        : (highContrast ? Colors.white70 : AppColors.border);
    final colorScheme = ColorScheme(
      brightness: darkTheme ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: darkTheme ? Colors.black : Colors.white,
      secondary: accent,
      onSecondary: darkTheme ? Colors.black : Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
    );

    final textTheme = buildTextTheme(baseTheme.textTheme).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );

    return baseTheme.copyWith(
      scaffoldBackgroundColor: shellBackground,
      colorScheme: colorScheme,
      textTheme: textTheme,
      dividerColor: border,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border, width: highContrast ? 1.4 : 1.0),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: contentBackground,
        hintStyle: TextStyle(
          color: textMuted,
          fontSize: 13,
        ),
        labelStyle: TextStyle(
          color: textMuted,
          fontSize: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border, width: highContrast ? 1.4 : 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent, width: highContrast ? 2.0 : 1.4),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border, width: highContrast ? 1.4 : 1.0),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: darkTheme ? Colors.black : Colors.white,
          minimumSize: const Size(0, 56),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 56),
          backgroundColor: surface,
          side: BorderSide(color: border, width: highContrast ? 1.4 : 1.0),
          foregroundColor: textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        AppSurfaceTheme(
          shellBackground: shellBackground,
          contentBackground: contentBackground,
          surface: surface,
          textPrimary: textPrimary,
          textMuted: textMuted,
          border: border,
          accent: accent,
        ),
      ],
    );
  }

  String _executionChannelSummary() {
    final requestedBackend = _requestedExecutionBackendForCommand();
    if (_selectedExecutionChannel == 'auto') {
      return _debugMode
          ? 'Auto now follows the external-first policy. VisionNavi prefers external agent backends first and only falls back internally when that intent is not yet supported or execution recovery is needed.'
          : _ux(
              '자동 모드에서는 외부 에이전트를 우선 사용하고, 아직 지원되지 않는 작업만 내부 방식으로 보완합니다.',
              '自動モードでは外部エージェントを優先して使い、まだ対応していない作業だけ内部方式で補います。',
            );
    }
    if (requestedBackend == null) {
      return _debugMode
          ? 'Select or interpret a command first so VisionNavi can resolve the channel for this task.'
          : _ux(
              '명령을 먼저 확인하면 어떤 실행 방식을 쓸지 자동으로 정합니다.',
              '命令を先に確認すると、どの実行方式を使うか自動で決めます。',
            );
    }
    if (_selectedExecutionChannel == 'external') {
      return _debugMode
          ? 'External sends the task to BrowserUse/UI-TARS style agent backends when supported. Unsupported intents can still fall back internally.'
          : _ux(
              '외부 에이전트 중심으로 작업을 진행하며, 필요할 때만 내부 방식으로 보완합니다.',
              '外部エージェント中心で作業を進め、必要なときだけ内部方式で補います。',
            );
    }
    return _debugMode
        ? 'Internal keeps the task on VisionNavi deterministic or hybrid executors for higher stability.'
        : _ux(
            '내부 실행 방식으로 진행하여 비교적 안정적인 동작을 우선합니다.',
            '内部実行方式で進めて、比較的安定した動作を優先します。',
          );
  }
  String? _requestedExecutionBackend() {
    final requested =
        _sessionMetadata['requested_execution_backend']?.toString();
    if (requested != null && requested.isNotEmpty) {
      return requested;
    }
    return _requestedExecutionBackendForCommand();
  }

  String? _executionBackend(Map<String, dynamic>? result) {
    final explicit = result?['execution_backend']?.toString();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    return _requestedExecutionBackend();
  }

  Map<String, dynamic>? _executionSummary(Map<String, dynamic>? result) {
    return _jsonMap(result?['execution_summary']);
  }

  String? _fallbackBackend(Map<String, dynamic>? result) {
    final explicit = result?['fallback_backend']?.toString();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    return _executionSummary(result)?['fallback_backend']?.toString();
  }

  String? _backendResolutionReason(Map<String, dynamic>? result) {
    final explicit = result?['backend_resolution_reason']?.toString();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final metadataReason =
        _sessionMetadata['backend_resolution_reason']?.toString();
    if (metadataReason != null && metadataReason.isNotEmpty) {
      return metadataReason;
    }
    return _executionSummary(result)?['routing_reason']?.toString();
  }

  Map<String, dynamic> _canonicalReviewBundle() {
    return {
      'session_id': _sessionId,
      'status': _status,
      'phase': _phase,
      'latest_detail': _events.isEmpty ? null : _events.last.detail,
      'command': _command?.toJson(),
      'policy_summary': _command == null ? null : _policySummary(_command!),
      'canonicalization_trace': _sessionMetadata['canonicalization_trace'],
      'result': _result,
      'directory_entries': _directoryEntries(_result),
      'decision_trace': _debugTrace(_result),
      'selected_execution_channel': _selectedExecutionChannelLabel(),
      'requested_execution_backend': _requestedExecutionBackend(),
      'execution_backend': _executionBackend(_result),
      'fallback_backend': _fallbackBackend(_result),
      'backend_resolution_reason': _backendResolutionReason(_result),
      'failure_reason': _failureReason(_result),
      'validation': _validationPayload(_result),
      'error': _error,
    };
  }

  Map<String, dynamic> _agentTraceBundle() {
    return {
      'session_id': _sessionId,
      'planning_notes': _planningNotes(_result),
      'selected_execution_channel': _selectedExecutionChannelLabel(),
      'requested_execution_backend': _requestedExecutionBackend(),
      'execution_backend': _executionBackend(_result),
      'fallback_backend': _fallbackBackend(_result),
      'backend_resolution_reason': _backendResolutionReason(_result),
      'failure_reason': _failureReason(_result),
      'validation': _validationPayload(_result),
      'bridge_result': _bridgeResultPayload(_result),
      'planner_trace': _sessionMetadata['planner_trace'],
      'planned_steps': _plannedSteps(_result),
      'executed_steps': _executedSteps(_result),
      'performance_summary': _performanceSummary(_result),
      'raw_agent_trace': _result?['raw_agent_trace'],
      'normalized_agent_trace': _result?['normalized_agent_trace'],
      'decision_trace': _result?['decision_trace'],
      'runtime_trace': _result?['runtime_trace'],
      'runtime_observation': _result?['runtime_observation'],
      'result': _result,
    };
  }

  Map<String, dynamic> _eventTimelineBundle() {
    return {
      'session_id': _sessionId,
      'event_count': _events.length,
      'events': _events
          .map(
            (event) => {
              'sequence': event.sequence,
              'type': event.type,
              'phase': event.phase,
              'detail': event.detail,
              'status': event.status,
              'current_phase': event.currentPhase,
              'payload': event.payload,
            },
          )
          .toList(),
    };
  }

  Map<String, dynamic> _currentTraceBundle() {
    final serverBuildId = _sessionMetadata['server_build_id'];
    final serverStartedAtUtc = _sessionMetadata['server_started_at_utc'];
    final serverCodeSignature = _sessionMetadata['server_code_signature'];

    return {
      'session_id': _sessionId,
      'status': _status,
      'phase': _phase,
      'server_build_id': serverBuildId,
      'server_started_at_utc': serverStartedAtUtc,
      'server_code_signature': serverCodeSignature,
      'metadata': {
        'server_build_id': serverBuildId,
        'server_started_at_utc': serverStartedAtUtc,
        'server_code_signature': serverCodeSignature,
      },
      'canonical_review': _canonicalReviewBundle(),
      'agent_trace': _agentTraceBundle(),
      'event_timeline': _eventTimelineBundle(),
      'session_metadata': _sessionMetadata,
    };
  }

  Future<void> _copyTraceBundle() async {
    final traceJson = _prettyJson(_currentTraceBundle());
    await Clipboard.setData(ClipboardData(text: traceJson));
    if (!mounted) {
      return;
    }
    _showSnackBar('현재 세션 추적 정보를 클립보드에 복사했습니다.');
  }

  Future<void> _exportTraceBundle() async {
    final sessionId = _sessionId ?? 'draft';
    final suggestedName = 'visionnavi-trace-$sessionId.json';
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'JSON',
          extensions: ['json'],
        ),
      ],
    );
    if (location == null) {
      return;
    }

    final file = File(location.path);
    await file.writeAsString(
      _prettyJson(_currentTraceBundle()),
      encoding: utf8,
    );
    if (!mounted) {
      return;
    }
    _showSnackBar('추적 정보를 ${file.path} 에 저장했습니다.');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyCanonicalReview() async {
    await Clipboard.setData(
      ClipboardData(text: _prettyJson(_canonicalReviewBundle())),
    );
    if (!mounted) {
      return;
    }
    _showSnackBar('Canonical Review 내용을 클립보드에 복사했습니다.');
  }

  Future<void> _copyAgentTrace() async {
    await Clipboard.setData(
      ClipboardData(text: _prettyJson(_agentTraceBundle())),
    );
    if (!mounted) {
      return;
    }
    _showSnackBar('Agent Trace 내용을 클립보드에 복사했습니다.');
  }

  Future<void> _copyEventTimeline() async {
    await Clipboard.setData(
      ClipboardData(text: _prettyJson(_eventTimelineBundle())),
    );
    if (!mounted) {
      return;
    }
    _showSnackBar('Event Timeline 내용을 클립보드에 복사했습니다.');
  }


  Widget _buildJsonViewer(
    BuildContext context,
    String title,
    Object? value, {
    Color? textColor,
    double height = 220,
  }) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: height,
          decoration: BoxDecoration(
            color: surfaceTheme.contentBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: surfaceTheme.border),
          ),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _prettyJson(value),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'Consolas',
                  color: textColor ?? surfaceTheme.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventTile(BuildContext context, SessionEvent event) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceTheme.contentBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: surfaceTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${event.sequence}. ${event.phase}',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
          Text(
            event.detail,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: surfaceTheme.textMuted,
            ),
          ),
          if (event.payload != null) ...[
            const SizedBox(height: 12),
            _buildJsonViewer(
              context,
              'Payload',
              event.payload,
              height: 180,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlannedStepCard(
    BuildContext context,
    Map<String, dynamic> step,
    int index,
  ) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    final action = step['action']?.toString() ?? 'unknown';
    final target = step['target']?.toString();
    final reasoning = step['reasoning']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceTheme.contentBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: surfaceTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${index + 1}. $action', style: theme.textTheme.bodyLarge),
          if (target != null && target.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Target: $target',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: surfaceTheme.textMuted,
              ),
            ),
          ],
          if (reasoning != null && reasoning.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              reasoning,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: surfaceTheme.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExecutedSteps(
    BuildContext context,
    List<Map<String, dynamic>> executedSteps,
  ) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: executedSteps.map((step) {
        final action = step['action']?.toString() ?? 'unknown';
        final status = step['status']?.toString() ?? 'unknown';
        final success = status == 'success';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: success ? AppColors.successSoft : AppColors.warningSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$action · $status',
            style: theme.textTheme.bodySmall?.copyWith(
              color: success ? AppColors.success : AppColors.warning,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTraceBadge(
    BuildContext context,
    String label,
    String value, {
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor ?? surfaceTheme.contentBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: surfaceTheme.border),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.bodySmall?.copyWith(
          color: foregroundColor ?? surfaceTheme.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildScrollableTracePane(
    BuildContext context,
    List<Widget> children,
  ) {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(right: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _buildTraceWorkspace(
    BuildContext context, {
    required String latestDetail,
    required List<Map<String, dynamic>> plannedSteps,
    required List<Map<String, dynamic>> executedSteps,
    required List<String> planningNotes,
    required List<Map<String, dynamic>> directoryEntries,
    required Map<String, dynamic>? debugTrace,
    required Map<String, dynamic>? performanceSummary,
    required String? executionBackend,
    required Object? canonicalizationTrace,
    required Object? plannerTrace,
    required Object? rawAgentTrace,
    required Object? normalizedAgentTrace,
  }) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    final failureReason = _failureReason(_result);
    final requestedBackend = _requestedExecutionBackend();
    final fallbackBackend = _fallbackBackend(_result);
    final routingReason = _backendResolutionReason(_result);

    return DefaultTabController(
      length: 3,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Trace Workspace', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Read one trace area at full size instead of splitting the same height across multiple cards.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: surfaceTheme.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (requestedBackend != null)
                    _buildTraceBadge(context, 'Requested', requestedBackend),
                  if (executionBackend != null)
                    _buildTraceBadge(context, 'Effective', executionBackend),
                  if (fallbackBackend != null)
                    _buildTraceBadge(context, 'Fallback', fallbackBackend),
                  if (failureReason != null)
                    _buildTraceBadge(
                      context,
                      'Failure',
                      failureReason,
                      backgroundColor: _isFailedResult(_result)
                          ? theme.colorScheme.errorContainer
                          : AppColors.warningSoft,
                      foregroundColor: _isFailedResult(_result)
                          ? theme.colorScheme.onErrorContainer
                          : AppColors.warning,
                    ),
                ],
              ),
              if (routingReason != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Routing / Fallback Reason: $routingReason',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: surfaceTheme.textMuted,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Canonical Review'),
                  Tab(text: 'Agent Trace'),
                  Tab(text: 'Event Timeline'),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildScrollableTracePane(
                      context,
                      [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _copyCanonicalReview,
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copy Review'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _copyTraceBundle,
                              icon: const Icon(Icons.copy_all_rounded, size: 16),
                              label: const Text('Copy All'),
                            ),
                            ElevatedButton.icon(
                              onPressed: _exportTraceBundle,
                              icon: const Icon(Icons.download_rounded, size: 16),
                              label: const Text('Export All'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SelectableText('Phase: $_phase'),
                        if (_sessionId != null)
                          SelectableText('Session: $_sessionId'),
                        const SizedBox(height: 8),
                        SelectableText(latestDetail),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          SelectableText(
                            _error!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                        if (_command != null) ...[
                          const SizedBox(height: 16),
                          SelectableText('Raw: ${_command!.rawText}'),
                          SelectableText(
                            'Normalized: ${_command!.normalizedText}',
                          ),
                          SelectableText('Intent: ${_command!.intent}'),
                          SelectableText('Domain: ${_command!.taskDomain}'),
                          SelectableText('Risk: ${_command!.riskLevel}'),
                          if (_command!.targetApp != null)
                            SelectableText('Target: ${_command!.targetApp}'),
                          if (_command!.notes.isNotEmpty)
                            SelectableText(
                              'Notes: ${_command!.notes.join(', ')}',
                            ),
                          SelectableText(
                            _command!.requiresConfirmation
                                ? 'Requires confirmation: yes'
                                : 'Requires confirmation: no',
                          ),
                          const SizedBox(height: 8),
                          SelectableText(_policySummary(_command!)),
                        ],
                        if (canonicalizationTrace != null) ...[
                          const SizedBox(height: 16),
                          _buildJsonViewer(
                            context,
                            'Canonicalization Trace',
                            canonicalizationTrace,
                            height: 320,
                          ),
                        ],
                        if (directoryEntries.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildJsonViewer(
                            context,
                            'Directory Entries',
                            directoryEntries,
                            height: 260,
                          ),
                        ],
                        if (debugTrace != null) ...[
                          const SizedBox(height: 16),
                          _buildJsonViewer(
                            context,
                            'Debug Trace',
                            debugTrace,
                            height: 320,
                          ),
                        ],
                        if (_result != null) ...[
                          const SizedBox(height: 16),
                          _buildJsonViewer(
                            context,
                            'Execution Result',
                            _result,
                            height: 360,
                          ),
                        ],
                      ],
                    ),
                    _buildScrollableTracePane(
                      context,
                      [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _copyAgentTrace,
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copy Agent'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Planner inputs, normalized action steps, backend traces, and validations are grouped here for debugging.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: surfaceTheme.textMuted,
                          ),
                        ),
                        if (planningNotes.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Planning Notes',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          ...planningNotes.map(
                            (note) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: SelectableText('• $note'),
                            ),
                          ),
                        ],
                        if (plannerTrace != null) ...[
                          const SizedBox(height: 16),
                          _buildJsonViewer(
                            context,
                            'Planner Trace',
                            plannerTrace,
                            height: 300,
                          ),
                        ],
                        if (performanceSummary != null) ...[
                          const SizedBox(height: 16),
                          _buildJsonViewer(
                            context,
                            'Performance Summary',
                            performanceSummary,
                            height: 240,
                          ),
                        ],
                        if (_validationPayload(_result) != null) ...[
                          const SizedBox(height: 16),
                          _buildJsonViewer(
                            context,
                            'Validation',
                            _validationPayload(_result),
                            height: 260,
                          ),
                        ],
                        if (normalizedAgentTrace != null) ...[
                          const SizedBox(height: 16),
                          _buildJsonViewer(
                            context,
                            'Normalized Agent Trace',
                            normalizedAgentTrace,
                            height: 340,
                          ),
                        ],
                        if (rawAgentTrace != null) ...[
                          const SizedBox(height: 16),
                          _buildJsonViewer(
                            context,
                            'Raw Agent Trace',
                            rawAgentTrace,
                            height: 360,
                          ),
                        ],
                        if (plannedSteps.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Planned Steps',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          ...List.generate(
                            plannedSteps.length,
                            (index) => _buildPlannedStepCard(
                              context,
                              plannedSteps[index],
                              index,
                            ),
                          ),
                        ],
                        if (executedSteps.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Executed Steps',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          _buildExecutedSteps(context, executedSteps),
                        ],
                      ],
                    ),
                    _buildScrollableTracePane(
                      context,
                      [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _copyEventTimeline,
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copy Events'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Each event keeps its own payload so you can inspect what was observed, planned, executed, and recovered.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: surfaceTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_events.isEmpty)
                          Text(
                            'Execution events will appear here after a command starts.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: surfaceTheme.textMuted,
                            ),
                          )
                        else
                          ..._events.map(
                            (event) => _buildEventTile(context, event),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudienceModeToggle(BuildContext context) {
    final surfaceTheme = Theme.of(context).extension<AppSurfaceTheme>()!;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: surfaceTheme.contentBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: surfaceTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChoiceChip(
            label: Text(_ux('사용자 모드', '利用者モード')),
            selected: !_debugMode,
            onSelected: (_) => setState(() => _debugMode = false),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(_ux('디버그 모드', 'デバッグモード')),
            selected: _debugMode,
            onSelected: (_) => setState(() => _debugMode = true),
          ),
        ],
      ),
    );
  }

  Widget _buildSeniorQuickActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required String command,
  }) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    return InkWell(
      onTap: () => _applyPresetCommand(command),
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: surfaceTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: surfaceTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: AppColors.accent, size: 28),
            ),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: surfaceTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeniorModeBody(
    BuildContext context, {
    required String latestDetail,
  }) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    final resultTitle = _userResultTitle();
    final resultSummary = _userResultSummary();
    final failureReason = _failureReason(_result);
    final attachedVoiceFileName = _attachedVoiceFileName();

    return Container(
      color: surfaceTheme.contentBackground,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _ux('무엇을 도와드릴까요?', 'どのようにお手伝いしましょうか'),
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _ux(
                        '복지 정보 찾기, 인터넷 검색, 메모 작성처럼 하고 싶은 일을 말하거나 입력해 주세요.',
                        '福祉情報の検索、インターネット検索、メモ作成など、したいことを話すか入力してください。',
                      ),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: surfaceTheme.textMuted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              Icons.mic_rounded,
                              color: theme.colorScheme.primary,
                              size: 34,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _ux('음성으로 요청하기', '音声で依頼する'),
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  !_userSettings.voiceInputEnabled
                                      ? _ux(
                                          '설정에서 음성 입력 표시를 켜면 이 자리에서 말로 요청할 수 있습니다.',
                                          '設定で音声入力表示を有効にすると、ここで音声依頼ができます。',
                                        )
                                      : (_speechMessage ??
                                          _ux(
                                            '버튼을 누르고 말씀하시면, 내용을 글자로 바꿔 입력창에 넣어드립니다.',
                                            'ボタンを押して話すと、内容を文字に変えて入力欄に入れます。',
                                          )),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: surfaceTheme.textMuted,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.tonalIcon(
                            onPressed: _userSettings.voiceInputEnabled
                                ? _toggleVoiceInput
                                : null,
                            icon: Icon(
                              _isListening
                                  ? Icons.stop_circle_outlined
                                  : Icons.graphic_eq_rounded,
                            ),
                            label: Text(
                              !_userSettings.voiceInputEnabled
                                  ? _ux('사용 안 함', '未使用')
                                  : (_speechBusy
                                      ? _ux('준비 중', '準備中')
                                      : (_isListening
                                          ? _ux('듣기 종료', '音声停止')
                                          : _ux('말하기 시작', '話し始める'))),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _pickVoiceFile,
                            icon: const Icon(Icons.attach_file_rounded),
                            label: Text(_ux('음성 파일 첨부', '音声ファイル添付')),
                          ),
                        ],
                      ),
                    ),
                    if (attachedVoiceFileName != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: surfaceTheme.contentBackground,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: surfaceTheme.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.audiotrack_rounded, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _ux(
                                  '첨부된 음성 파일: $attachedVoiceFileName',
                                  '添付した音声ファイル: $attachedVoiceFileName',
                                ),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    TextField(
                      controller: _controller,
                      minLines: 4,
                      maxLines: 6,
                      style: theme.textTheme.titleMedium,
                      decoration: InputDecoration(
                        hintText: _ux(
                          '예: 네이버에서 경기 청년 월세 지원 조건 알려줘',
                          '例: ネイバーで京畿道の青年家賃支援条件を教えて',
                        ),
                        hintStyle: theme.textTheme.titleSmall?.copyWith(
                          color: surfaceTheme.textMuted,
                        ),
                        contentPadding: const EdgeInsets.all(20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ElevatedButton.icon(
                          onPressed: (_isSubmitting || _isCanonicalizing)
                              ? null
                              : _runPrimaryUserAction,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            _isSubmitting
                                ? _ux('진행 중...', '進行中...')
                                : _ux('바로 실행', 'すぐ実行'),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 18,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: (_isSubmitting || _isCanonicalizing)
                              ? null
                              : _interpretCommand,
                          icon: const Icon(Icons.psychology_alt_rounded),
                          label: Text(
                            _isCanonicalizing
                                ? _ux('이해 중...', '理解中...')
                                : _ux('명령 먼저 확인', '命令を先に確認'),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 18,
                            ),
                          ),
                        ),
                        if (_isSubmitting)
                          OutlinedButton.icon(
                            onPressed: _stopSession,
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: Text(_ux('중지', '停止')),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 18,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _executionChannelSummary(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: surfaceTheme.textMuted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _ux(
                        '현재 설정: ${_localizedPreferredLanguageLabel()} · ${_localizedTextScaleLabel()} · ${_localizedVoiceButtonLabel()}',
                        '現在の設定: ${_localizedPreferredLanguageLabel()} · ${_localizedTextScaleLabel()} · ${_localizedVoiceButtonLabel()}',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: surfaceTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(_ux('자주 하는 작업', 'よく使う作業'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isSingleColumn = constraints.maxWidth < 900;
                final cards = [
                  _buildSeniorQuickActionCard(
                    context,
                    icon: Icons.volunteer_activism_rounded,
                    title: _ux('복지 정보 찾기', '福祉情報を探す'),
                    description: _ux(
                      '청년 월세 지원, 생활 지원 같은 정보를 쉽게 찾아드립니다.',
                      '青年家賃支援や生活支援などの情報を分かりやすく探します。',
                    ),
                    command: '네이버에서 경기 청년 월세 지원 정보 찾아줘',
                  ),
                  _buildSeniorQuickActionCard(
                    context,
                    icon: Icons.travel_explore_rounded,
                    title: _ux('인터넷에서 알아보기', 'インターネットで調べる'),
                    description: _ux(
                      '궁금한 내용을 검색하고 중요한 부분만 짧게 정리합니다.',
                      '気になる内容を検索して大事な部分だけ短くまとめます。',
                    ),
                    command: '네이버에서 인천 청년 월세 지원 조건 찾아줘',
                  ),
                  _buildSeniorQuickActionCard(
                    context,
                    icon: Icons.note_alt_rounded,
                    title: _ux('메모 작성', 'メモ作成'),
                    description: _ux(
                      '간단한 문장을 메모장에 적고 저장하는 일을 도와드립니다.',
                      '簡単な文章をメモ帳に書いて保存する作業をお手伝いします。',
                    ),
                    command: 'Open Notepad and type exactly VisionNavi external desktop verification, then save the file.',
                  ),
                  _buildSeniorQuickActionCard(
                    context,
                    icon: Icons.folder_open_rounded,
                    title: _ux('파일 보기', 'ファイルを見る'),
                    description: _ux(
                      '작업 폴더를 열고 파일을 확인하는 일을 도와드립니다.',
                      '作業フォルダを開いてファイルを確認する作業をお手伝いします。',
                    ),
                    command: 'Open file explorer for the VisionNavi workspace and list files.',
                  ),
                ];
                if (isSingleColumn) {
                  return Column(
                    children: cards
                        .map(
                          (card) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: card,
                          ),
                        )
                        .toList(),
                  );
                }
                return GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.65,
                  physics: const NeverScrollableScrollPhysics(),
                  children: cards,
                );
              },
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userStatusTitle(),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _userStatusDetail(),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: surfaceTheme.textMuted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildTraceBadge(context, _ux('상태', '状態'), _status),
                        _buildTraceBadge(context, _ux('단계', '段階'), _phase),
                        _buildTraceBadge(
                          context,
                          _ux('도움 방식', '支援方式'),
                          _userChannelBadgeValue(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _ux('현재 안내', '現在の案内'),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: surfaceTheme.contentBackground,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: surfaceTheme.border),
                      ),
                      child: Text(
                        latestDetail,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_ux('결과 요약', '結果要約'), style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      _ux(
                        '디버그 정보 대신 사용자에게 바로 필요한 결과만 먼저 보여드립니다.',
                        'デバッグ情報ではなく、利用者に必要な結果を先に表示します。',
                      ),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: surfaceTheme.textMuted,
                        height: 1.5,
                      ),
                    ),
                    if (resultTitle != null) ...[
                      const SizedBox(height: 16),
                      Text(resultTitle, style: theme.textTheme.titleMedium),
                    ],
                    const SizedBox(height: 12),
                    SelectableText(
                      resultSummary,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                    ),
                    if (failureReason != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          _ux(
                            '다시 확인이 필요한 이유: $failureReason',
                            '再確認が必要な理由: $failureReason',
                          ),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w700,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugModeBody(
    BuildContext context, {
    required String latestDetail,
    required List<Map<String, dynamic>> plannedSteps,
    required List<Map<String, dynamic>> executedSteps,
    required List<String> planningNotes,
    required List<Map<String, dynamic>> directoryEntries,
    required Map<String, dynamic>? debugTrace,
    required Map<String, dynamic>? performanceSummary,
    required String? executionBackend,
    required Object? canonicalizationTrace,
    required Object? plannerTrace,
    required Object? rawAgentTrace,
    required Object? normalizedAgentTrace,
  }) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 290,
          child: ActionPanel(
            isRunning: _isSubmitting || _isCanonicalizing,
            onStop: _events.isEmpty ? null : _stopSession,
            onSelectSearchDemo: () => _applyPresetCommand(
              'Search Naver for Incheon youth monthly rent support and read the conditions.',
            ),
            onSelectNotepadDemo: () => _applyPresetCommand(
              'Open Notepad and type my presentation notes for today.',
            ),
            onSelectWorkspaceDemo: () => _applyPresetCommand(
              'Open file explorer for the VisionNavi workspace and list files.',
            ),
            onSelectDarkModeDemo: () =>
                _applyPresetCommand('Change Windows to dark mode'),
          ),
        ),
        Expanded(
          child: Container(
            color: surfaceTheme.contentBackground,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Command Workspace',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Step 1: interpret the command with the LLM. Step 2: review the canonical command. Step 3: execute.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: surfaceTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextCommandComposer(
                          controller: _controller,
                          onSubmit: _interpretCommand,
                          isBusy: _isSubmitting || _isCanonicalizing,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Execution Channel',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: surfaceTheme.textMuted,
                              ),
                            ),
                            DropdownButton<String>(
                              value: _selectedExecutionChannel,
                              onChanged:
                                  (_isSubmitting || _isCanonicalizing)
                                      ? null
                                      : (value) {
                                        if (value == null) {
                                          return;
                                        }
                                        setState(() {
                                          _selectedExecutionChannel = value;
                                        });
                                      },
                              items: const [
                                DropdownMenuItem(
                                  value: 'auto',
                                  child: Text('Auto'),
                                ),
                                DropdownMenuItem(
                                  value: 'internal',
                                  child: Text('Internal'),
                                ),
                                DropdownMenuItem(
                                  value: 'external',
                                  child: Text('External'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _executionChannelSummary(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: surfaceTheme.textMuted,
                          ),
                        ),
                        if (_requestedExecutionBackendForCommand() != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Requested backend: ${_requestedExecutionBackendForCommand()}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: surfaceTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton(
                              onPressed:
                                  (_isSubmitting || _isCanonicalizing)
                                      ? null
                                      : _interpretCommand,
                              child: Text(
                                _isCanonicalizing
                                    ? 'Interpreting...'
                                    : 'Interpret Command',
                              ),
                            ),
                            ElevatedButton(
                              onPressed:
                                  (_command == null ||
                                          _isSubmitting ||
                                          _isCanonicalizing)
                                      ? null
                                      : (_command?.requiresConfirmation == true
                                          ? _approveAndRun
                                          : _runReviewedCommand),
                              child: Text(
                                _isSubmitting
                                    ? 'Running...'
                                    : (_command?.requiresConfirmation == true
                                        ? 'Approve and Run'
                                        : 'Run Reviewed Command'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _buildTraceWorkspace(
                    context,
                    latestDetail: latestDetail,
                    plannedSteps: plannedSteps,
                    executedSteps: executedSteps,
                    planningNotes: planningNotes,
                    directoryEntries: directoryEntries,
                    debugTrace: debugTrace,
                    performanceSummary: performanceSummary,
                    executionBackend: executionBackend,
                    canonicalizationTrace: canonicalizationTrace,
                    plannerTrace: plannerTrace,
                    rawAgentTrace: rawAgentTrace,
                    normalizedAgentTrace: normalizedAgentTrace,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final textScale = (!_debugMode && _userSettings.largeText) ? 1.16 : 1.0;
    final scopedTheme = _buildUserScopedTheme(baseTheme);
    final surfaceTheme = scopedTheme.extension<AppSurfaceTheme>()!;
    final theme = scopedTheme;
    final latestDetail =
        _events.isEmpty ? 'No execution events yet.' : _events.last.detail;
    final result = _result;
    final plannedSteps = _plannedSteps(result);
    final executedSteps = _executedSteps(result);
    final planningNotes = _planningNotes(result);
    final directoryEntries = _directoryEntries(result);
    final debugTrace = _debugTrace(result);
    final performanceSummary = _performanceSummary(result);
    final executionBackend = _executionBackend(result);
    final canonicalizationTrace = _sessionMetadata['canonicalization_trace'];
    final plannerTrace = _sessionMetadata['planner_trace'];
    final rawAgentTrace = _result?['raw_agent_trace'];
    final normalizedAgentTrace = _result?['normalized_agent_trace'];

    return Theme(
      data: scopedTheme,
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          backgroundColor: surfaceTheme.shellBackground,
          body: SafeArea(
            child: Column(
              children: [
            Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: surfaceTheme.surface,
                border: Border(bottom: BorderSide(color: surfaceTheme.border)),
              ),
              child: Row(
                children: [
                  Text('VisionNavi', style: theme.textTheme.titleLarge),
                  const SizedBox(width: 12),
                  Text(
                    _headerSubtitle(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: surfaceTheme.textMuted,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _openSettingsDialog,
                    icon: const Icon(Icons.settings_rounded, size: 18),
                    label: Text(_ux('설정', '設定')),
                  ),
                  const SizedBox(width: 12),
                  _buildAudienceModeToggle(context),
                ],
              ),
            ),
            Container(
              height: 92,
              decoration: BoxDecoration(
                color: surfaceTheme.surface,
                border: Border(bottom: BorderSide(color: surfaceTheme.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: StatusCard(
                      label: _localizedStatusLabel(),
                      value: _debugMode ? _status : _userStatusTitle(),
                      icon: Icons.mic_none_rounded,
                      iconBackground: (_isSubmitting || _isCanonicalizing)
                          ? AppColors.successSoft
                          : surfaceTheme.contentBackground,
                      iconColor: (_isSubmitting || _isCanonicalizing)
                          ? AppColors.success
                          : surfaceTheme.textMuted,
                      showWave: true,
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: surfaceTheme.border,
                  ),
                  Expanded(
                    child: StatusCard(
                      label: _localizedPolicyLabel(),
                      value: _localizedPolicyValue(),
                      icon: _command?.requiresConfirmation == true
                          ? Icons.lock_outline_rounded
                          : Icons.bolt_rounded,
                      iconBackground: _command?.requiresConfirmation == true
                          ? AppColors.warningSoft
                          : surfaceTheme.contentBackground,
                      iconColor: _command?.requiresConfirmation == true
                          ? AppColors.warning
                          : surfaceTheme.textMuted,
                      showDot: true,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _debugMode
                  ? _buildDebugModeBody(
                      context,
                      latestDetail: latestDetail,
                      plannedSteps: plannedSteps,
                      executedSteps: executedSteps,
                      planningNotes: planningNotes,
                      directoryEntries: directoryEntries,
                      debugTrace: debugTrace,
                      performanceSummary: performanceSummary,
                      executionBackend: executionBackend,
                      canonicalizationTrace: canonicalizationTrace,
                      plannerTrace: plannerTrace,
                      rawAgentTrace: rawAgentTrace,
                      normalizedAgentTrace: normalizedAgentTrace,
                    )
                  : _buildSeniorModeBody(
                      context,
                      latestDetail: latestDetail,
                    ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

