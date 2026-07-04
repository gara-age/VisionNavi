import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:window_manager/window_manager.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/colors.dart';
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
  final TextEditingController _controller = TextEditingController();
  final OrchestratorClient _client = OrchestratorClient();
  final SpeechToText _speechToText = SpeechToText();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioRecorder _wakeWordLevelRecorder = AudioRecorder();

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
  bool _showTextComposer = false;
  HomeUserSettings _userSettings = const HomeUserSettings();
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _speechBusy = false;
  bool _isRecordingFallback = false;
  bool _isWakeWordMonitoring = false;
  bool _isWakeWordLevelMonitoring = false;
  String? _speechMessage;
  String? _speechLocaleId;
  String? _attachedVoiceFilePath;
  String? _lastExecutionPopupKey;
  StreamSubscription<Uint8List>? _liveAudioSubscription;
  StreamSubscription<Uint8List>? _wakeWordLevelSubscription;
  Timer? _liveTranscriptionTimer;
  Timer? _liveSilenceTimer;
  BytesBuilder? _liveAudioBytes;
  bool _liveTranscriptionInFlight = false;
  Completer<void>? _liveTranscriptionCompleter;
  int _liveTranscriptionGeneration = 0;
  String _liveTranscriptionText = '';
  double _liveAudioPeakLevel = 0;
  bool _liveAudioSignalDetected = false;
  DateTime? _liveRecordingStartedAt;
  DateTime? _lastLiveSpeechDetectedAt;
  bool _isAutoStoppingRecordedVoice = false;
  double _wakeWordAudioPeakLevel = 0;
  Timer? _wakeWordStatusPollTimer;
  Timer? _wakeWordRearmTimer;
  Timer? _audioDiagnosticsPollTimer;
  @override
  void initState() {
    super.initState();
    unawaited(_loadUserSettings());
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _speechToText.cancel();
    _liveAudioSubscription?.cancel();
    _wakeWordLevelSubscription?.cancel();
    _liveTranscriptionTimer?.cancel();
    _liveSilenceTimer?.cancel();
    _wakeWordStatusPollTimer?.cancel();
    _wakeWordRearmTimer?.cancel();
    _audioDiagnosticsPollTimer?.cancel();
    _audioRecorder.dispose();
    _wakeWordLevelRecorder.dispose();
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
      _speechMessage = _commandProgressMessage(text);
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
        _speechMessage = _commandProgressMessage(
          command.normalizedText.trim().isNotEmpty
              ? command.normalizedText
              : command.rawText,
        );
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
      _queueWakeWordRearm();
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
      _queueWakeWordRearm();
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
      _queueWakeWordRearm();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
      });
      _queueWakeWordRearm();
    }
  }

  bool _canRearmWakeWord() {
    return mounted &&
        _userSettings.wakeWordEnabled &&
        !_isWakeWordMonitoring &&
        !_isRecordingFallback &&
        !_isListening &&
        !_speechBusy &&
        !_isSubmitting &&
        !_isCanonicalizing;
  }

  void _queueWakeWordRearm([Duration delay = const Duration(seconds: 1)]) {
    _wakeWordRearmTimer?.cancel();
    if (!_userSettings.wakeWordEnabled) {
      return;
    }
    _wakeWordRearmTimer = Timer(delay, () async {
      if (!_canRearmWakeWord()) {
        return;
      }
      await _startWakeWordMonitoring(autoStarted: true);
    });
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

    final isFailed =
        _isFailedResult(result) || status == 'error' || status == 'canceled';
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
          language: _preferredLanguageCode(),
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

  TaskbarPopupThemeMode _currentPopupThemeMode() {
    if (_userSettings.highContrast) {
      return TaskbarPopupThemeMode.contrast;
    }
    if (_userSettings.darkTheme) {
      return TaskbarPopupThemeMode.dark;
    }
    return TaskbarPopupThemeMode.light;
  }

  Future<void> _showWakeWordListeningPopup() async {
    await _showExecutionPopup(
      title: _ux('말씀을 듣고있어요', 'お話を聞いています'),
      message: _ux(
        '이제 하시고 싶은 일을 말씀해 주세요.',
        '続けて、してほしいことを話してください。',
      ),
      state: TaskbarPopupState.processing,
      themeMode: _currentPopupThemeMode(),
    );
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
      _showTextComposer = true;
    });
  }

  void _toggleTextComposer() {
    setState(() {
      _showTextComposer = !_showTextComposer;
    });
  }

  Future<void> _minimizeWindow() async {
    await windowManager.minimize();
  }

  Future<void> _toggleMaximizeWindow() async {
    return;
  }

  Future<void> _closeWindow() async {
    await windowManager.close();
  }

  Future<void> _openSettingsDialog() async {
    final wasWakeWordEnabled = _userSettings.wakeWordEnabled;
    final scopedTheme = Theme.of(context);
    final next = await showDialog<HomeUserSettings>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Theme(
        data: scopedTheme,
        child: HomeSettingsDialog(initialSettings: _userSettings),
      ),
    );
    if (!mounted || next == null) {
      return;
    }
    final enforced = _normalizeVoiceSettings(next);
    setState(() {
      _userSettings = enforced;
      _speechLocaleId = null;
    });
    await HomeSettingsStore.instance.save(enforced);
    await _primeSpeechRecognizer();
    await _syncWakeWordMonitoring(
      previousEnabled: wasWakeWordEnabled,
      currentEnabled: enforced.wakeWordEnabled,
    );
  }

  Future<void> _openHelpDialog() async {
    final scopedTheme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = scopedTheme;
        final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
        return Theme(
          data: scopedTheme,
          child: AlertDialog(
            backgroundColor: surfaceTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(_ux('도움말', 'ヘルプ')),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ux(
                      'VisionNavi는 말하거나 입력한 요청을 대신 도와드리는 앱입니다.',
                      'VisionNavi は話したり入力したお願いを代わりに手伝うアプリです。',
                    ),
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _ux('이렇게 시작해 보세요', 'このように始めてみてください'),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  ...[
                    _ux('말하기 시작 버튼을 누르고 말씀해 주세요.', '話し始めるボタンを押して話してください。'),
                    _ux('글자로 입력하기를 눌러 직접 입력할 수도 있어요.',
                        '文字で入力するを押して直接入力することもできます。'),
                    _ux('예시 문장을 눌러서 바로 시작할 수도 있어요.', '例文を押してすぐ始めることもできます。'),
                  ].map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '• $line',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: surfaceTheme.textMuted,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(_ux('확인', '確認')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _loadUserSettings() async {
    final loaded = _normalizeVoiceSettings(
      await HomeSettingsStore.instance.load(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _userSettings = loaded;
    });
    await HomeSettingsStore.instance.save(loaded);
    _ensureAudioDiagnosticsPolling();
    await _primeSpeechRecognizer();
    await _syncWakeWordMonitoring(
      previousEnabled: false,
      currentEnabled: loaded.wakeWordEnabled,
    );
  }

  HomeUserSettings _normalizeVoiceSettings(HomeUserSettings settings) {
    if (!settings.voiceInputEnabled) {
      return settings.copyWith(wakeWordEnabled: false);
    }
    return settings;
  }

  bool get _isJapanese => _preferredLanguageCode() == 'ja';
  String _preferredLanguageCode() {
    return _normalizePreferredLanguage(_userSettings.preferredLanguage);
  }

  String _normalizePreferredLanguage(String value) {
    final normalized = value.trim().toLowerCase();
    const japaneseAliases = <String>{
      'ja',
      'ja-jp',
      'jp',
      'japanese',
      '\u65e5\u672c\u8a9e',
      '\uc77c\ubcf8\uc5b4',
    };
    const koreanAliases = <String>{
      'ko',
      'ko-kr',
      'korean',
      '\ud55c\uad6d\uc5b4',
    };
    if (japaneseAliases.contains(normalized) ||
        normalized.startsWith('ja') ||
        normalized.startsWith('jp')) {
      return 'ja';
    }
    if (koreanAliases.contains(normalized) || normalized.startsWith('ko')) {
      return 'ko';
    }
    return 'ko';
  }

  String _wakeWordProfileIdForCurrentSettings() {
    final language = _preferredLanguageCode();
    final phrase = _resolvedWakeWordPhraseForCurrentLanguage();
    if (language == 'ja') {
      switch (phrase) {
        case 'ねえ、ナビ':
        case 'ねえナビ':
          return 'ja_nee_navi';
        case 'ナビさん':
          return 'ja_navisan';
        default:
          return 'ja_nee_navi';
      }
    }

    switch (phrase) {
      case '헤이 나비':
        return 'ko_hey_nabi';
      case '나비야':
      default:
        return 'ko_nabiya';
    }
  }

  String _resolvedWakeWordPhraseForCurrentLanguage() {
    final language = _preferredLanguageCode();
    final phrase = _userSettings.wakeWordPhrase.trim();
    if (language == 'ja') {
      if (phrase == 'ねえ、ナビ' || phrase == 'ナビさん') {
        return phrase;
      }
      return 'ねえ、ナビ';
    }
    if (phrase == '헤이 나비' || phrase == '나비야') {
      return phrase;
    }
    return '나비야';
  }

  String _ux(String ko, String ja) => _isJapanese ? ja : ko;

  bool _isUnderstandingInProgress() =>
      _isCanonicalizing ||
      _status == 'Interpreting' ||
      _phase == 'canonicalize';

  bool _isExecutionInProgress() =>
      _isSubmitting ||
      _phase == 'queued' ||
      _phase == 'observe' ||
      _phase == 'plan' ||
      _phase == 'act' ||
      _phase == 'verify' ||
      _phase == 'recover';

  bool _isVoiceCaptureInProgress() =>
      _speechBusy || _isListening || _isRecordingFallback;

  bool _canShowWakeWordIdleMessage() =>
      !_isUnderstandingInProgress() &&
      !_isExecutionInProgress() &&
      !_isVoiceCaptureInProgress();

  String _voiceActionButtonLabel() {
    if (_isUnderstandingInProgress() || _isExecutionInProgress()) {
      return _ux('처리 중', '処理中');
    }
    if (!_userSettings.voiceInputEnabled) {
      return _ux('사용 안 함', '未使用');
    }
    if (_speechBusy) {
      return _ux('전사 중', '変換中');
    }
    if (_isRecordingFallback) {
      return _ux('녹음 종료', '録音終了');
    }
    if (_isListening) {
      return _ux('듣기 종료', '音声停止');
    }
    return _ux('말하기 시작', '話し始める');
  }

  Future<void> _primeSpeechRecognizer() async {
    if (!_userSettings.voiceInputEnabled || _speechAvailable || _speechBusy) {
      return;
    }
    try {
      final available = await _speechToText.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
        debugLogging: false,
      );
      _speechAvailable = available;
      if (available && _speechLocaleId == null) {
        final locales = await _speechToText.locales();
        _speechLocaleId = _pickSpeechLocale(locales);
      }
    } catch (_) {
      _speechAvailable = false;
    }
  }

  bool get _shouldAutoInterpretVoice => _userSettings.voiceAutoInterpret;

  int _minimumLiveAudioBytes({required bool isFinal}) {
    const bytesPerSecond = 16000 * 2;
    final sensitivity = _userSettings.microphoneSensitivity.clamp(0.0, 1.0);
    final seconds = isFinal
        ? (0.45 - (sensitivity * 0.15)).clamp(0.25, 0.45)
        : (1.6 - (sensitivity * 0.8)).clamp(0.8, 1.6);
    return (bytesPerSecond * seconds).round();
  }

  Future<void> _syncWakeWordMonitoring({
    required bool previousEnabled,
    required bool currentEnabled,
  }) async {
    if (!currentEnabled) {
      if (_isWakeWordMonitoring) {
        await _stopWakeWordMonitoring(manual: false);
      }
      return;
    }
    if (!_userSettings.voiceInputEnabled) {
      return;
    }
    if (!_isWakeWordMonitoring &&
        !_isRecordingFallback &&
        !_isListening &&
        !_speechBusy &&
        (!previousEnabled || currentEnabled)) {
      await _startWakeWordMonitoring(autoStarted: true);
    }
  }

  Future<void> _toggleVoiceInput() async {
    if (_speechBusy) {
      return;
    }
    if (_isWakeWordMonitoring) {
      await _stopWakeWordMonitoring(manual: false);
    }
    if (_isRecordingFallback) {
      await _stopRecordedVoiceFallback();
      return;
    }
    if (_shouldUseLocalLiveTranscription()) {
      await _startRecordedVoiceFallback();
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
          await _startRecordedVoiceFallback();
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
    } catch (_) {
      await _startRecordedVoiceFallback();
    } finally {
      if (mounted) {
        setState(() {
          _speechBusy = false;
        });
      }
    }
  }

  Future<void> _startRecordedVoiceFallback() async {
    if (_isWakeWordMonitoring) {
      await _stopWakeWordMonitoring(manual: false);
    }
    final hasPermission = await _audioRecorder.hasPermission();
    if (!mounted) {
      return;
    }
    if (!hasPermission) {
      setState(() {
        _speechMessage = _ux(
          '마이크 권한이 없어 음성 녹음을 시작할 수 없습니다.',
          'マイク権限がないため、音声録音を開始できません。',
        );
      });
      return;
    }

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      bitRate: 128000,
      streamBufferSize: 4096,
    );

    _liveAudioBytes = BytesBuilder(copy: false);
    _liveTranscriptionText = '';
    _liveAudioPeakLevel = 0;
    _liveAudioSignalDetected = false;
    _liveRecordingStartedAt = DateTime.now();
    _lastLiveSpeechDetectedAt = null;
    _isAutoStoppingRecordedVoice = false;
    _liveTranscriptionGeneration += 1;
    final generation = _liveTranscriptionGeneration;

    final stream = await _audioRecorder.startStream(config);
    await _liveAudioSubscription?.cancel();
    _liveAudioSubscription = stream.listen((chunk) {
      if (generation != _liveTranscriptionGeneration) {
        return;
      }
      _liveAudioBytes?.add(chunk);
      final peak = _estimatePcm16PeakLevel(chunk);
      if (peak > _liveAudioPeakLevel) {
        _liveAudioPeakLevel = peak;
      }
      if (peak >= 0.015) {
        _liveAudioSignalDetected = true;
        _lastLiveSpeechDetectedAt = DateTime.now();
      }
    });
    _liveTranscriptionTimer?.cancel();
    _liveTranscriptionTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_transcribeLiveAudioBuffer(isFinal: false)),
    );
    _liveSilenceTimer?.cancel();
    _liveSilenceTimer = Timer.periodic(
      const Duration(milliseconds: 350),
      (_) => unawaited(_maybeAutoStopRecordedVoice()),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isRecordingFallback = true;
      _attachedVoiceFilePath = null;
      _speechMessage = _ux(
        '실시간으로 듣고 있어요. 다시 누르면 녹음을 끝내고 글자로 바꿉니다.',
        'リアルタイムで聞いています。もう一度押すと録音を終えて文字に変えます。',
      );
    });
  }

  Future<void> _stopRecordedVoiceFallback() async {
    setState(() {
      _speechBusy = true;
    });
    try {
      _liveTranscriptionTimer?.cancel();
      _liveTranscriptionTimer = null;
      _liveSilenceTimer?.cancel();
      _liveSilenceTimer = null;
      await _audioRecorder.stop();
      await _liveAudioSubscription?.cancel();
      _liveAudioSubscription = null;
      await _waitForLiveTranscriptionToFinish();
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecordingFallback = false;
      });
      final hadSignal =
          _liveAudioSignalDetected || _liveAudioPeakLevel >= 0.015;
      if (!hadSignal) {
        setState(() {
          _speechMessage = _ux(
            '마이크 입력이 감지되지 않았습니다. Windows 입력 장치나 블루투스 헤드셋의 마이크 연결 상태를 확인해 주세요.',
            'マイク入力が検出されませんでした。Windows の入力デバイスや Bluetooth ヘッドセットのマイク接続状態を確認してください。',
          );
        });
        if (_userSettings.wakeWordEnabled) {
          await _startWakeWordMonitoring(autoStarted: true);
        }
        return;
      }
      final finalText = await _transcribeLiveAudioBuffer(isFinal: true);
      if (!mounted) {
        return;
      }
      final resolvedText = (finalText ?? _liveTranscriptionText).trim();
      if (resolvedText.isEmpty) {
        setState(() {
          _speechMessage = _ux(
            '녹음은 되었지만 알아들을 수 있는 음성이 충분하지 않았습니다. 마이크 위치나 입력 장치를 확인한 뒤 다시 시도해 주세요.',
            '録音はできましたが、聞き取れる音声が十分ではありませんでした。マイク位置や入力デバイスを確認してからもう一度お試しください。',
          );
        });
        if (_userSettings.wakeWordEnabled) {
          await _startWakeWordMonitoring(autoStarted: true);
        }
        return;
      }
    } finally {
      _liveAudioBytes = null;
      _liveAudioPeakLevel = 0;
      _liveAudioSignalDetected = false;
      _liveRecordingStartedAt = null;
      _lastLiveSpeechDetectedAt = null;
      _isAutoStoppingRecordedVoice = false;
      if (mounted) {
        setState(() {
          _speechBusy = false;
        });
      }
      if (_userSettings.wakeWordEnabled &&
          mounted &&
          !_isWakeWordMonitoring &&
          !_isRecordingFallback &&
          !_speechBusy) {
        await _startWakeWordMonitoring(autoStarted: true);
      }
    }
  }

  Future<void> _maybeAutoStopRecordedVoice() async {
    if (!_isRecordingFallback || _speechBusy || _isAutoStoppingRecordedVoice) {
      return;
    }

    final now = DateTime.now();
    final lastSpeechDetectedAt = _lastLiveSpeechDetectedAt;
    if (lastSpeechDetectedAt != null) {
      if (now.difference(lastSpeechDetectedAt) <
          const Duration(milliseconds: 2000)) {
        return;
      }
    } else {
      final recordingStartedAt = _liveRecordingStartedAt;
      if (recordingStartedAt == null ||
          now.difference(recordingStartedAt) < const Duration(seconds: 4)) {
        return;
      }
    }

    _isAutoStoppingRecordedVoice = true;
    try {
      await _stopRecordedVoiceFallback();
    } finally {
      _isAutoStoppingRecordedVoice = false;
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
    if (normalized.contains('notlistening') || normalized.contains('done')) {
      _queueWakeWordRearm(const Duration(seconds: 2));
    }
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    if (!mounted) {
      return;
    }
    final fallbackNeeded = _shouldFallbackToRecordedVoice(error.errorMsg);
    setState(() {
      _isListening = false;
      _speechMessage = _ux(
        '음성 입력에 실패했습니다: ${error.errorMsg}',
        '音声入力に失敗しました: ${error.errorMsg}',
      );
    });
    if (fallbackNeeded && !_isRecordingFallback && !_speechBusy) {
      unawaited(_startRecordedVoiceFallback());
      return;
    }
    _queueWakeWordRearm(const Duration(seconds: 2));
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
        _shouldAutoInterpretVoice &&
        !_isCanonicalizing &&
        !_isSubmitting) {
      unawaited(_submitTextComposerRequest());
    }
  }

  String? _pickSpeechLocale(List<LocaleName> locales) {
    final preferredPrefix = _preferredLanguageCode();
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

  bool _shouldFallbackToRecordedVoice(String errorMessage) {
    final normalized = errorMessage.toLowerCase();
    return normalized.contains('음성인식을 사용할 수 없습니다') ||
        normalized.contains('speech recognition not available') ||
        normalized.contains('not available on this device') ||
        normalized
            .contains('this device does not support speech recognition') ||
        normalized.contains('recognizer_unavailable') ||
        normalized.contains('recognizer unavailable');
  }

  bool _shouldUseLocalLiveTranscription() {
    if (!Platform.isWindows) {
      return false;
    }
    return {'ko', 'ja'}.contains(_preferredLanguageCode());
  }

  Future<void> _startWakeWordLevelMonitoring() async {
    if (_isWakeWordLevelMonitoring || _isRecordingFallback) {
      return;
    }
    final hasPermission = await _wakeWordLevelRecorder.hasPermission();
    if (!hasPermission) {
      return;
    }

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      bitRate: 128000,
      streamBufferSize: 4096,
    );

    try {
      final stream = await _wakeWordLevelRecorder.startStream(config);
      await _wakeWordLevelSubscription?.cancel();
      _wakeWordAudioPeakLevel = 0;
      _wakeWordLevelSubscription = stream.listen((chunk) {
        final peak = _estimatePcm16PeakLevel(chunk);
        if (peak > _wakeWordAudioPeakLevel) {
          _wakeWordAudioPeakLevel = peak;
        }
        if (mounted) {
          setState(() {});
        }
      });
      if (mounted) {
        setState(() {
          _isWakeWordLevelMonitoring = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isWakeWordLevelMonitoring = false;
          _wakeWordAudioPeakLevel = 0;
        });
      }
    }
  }

  Future<void> _stopWakeWordLevelMonitoring() async {
    await _wakeWordLevelSubscription?.cancel();
    _wakeWordLevelSubscription = null;
    try {
      await _wakeWordLevelRecorder.stop();
    } catch (_) {
      // Ignore stop failures for the passive level monitor.
    }
    if (mounted) {
      setState(() {
        _isWakeWordLevelMonitoring = false;
        _wakeWordAudioPeakLevel = 0;
      });
    } else {
      _isWakeWordLevelMonitoring = false;
      _wakeWordAudioPeakLevel = 0;
    }
  }

  Future<void> _startWakeWordMonitoring({required bool autoStarted}) async {
    if (_isWakeWordMonitoring ||
        _isRecordingFallback ||
        _isListening ||
        _speechBusy) {
      return;
    }
    try {
      final status = await _client.startWakeWord(
        language: _preferredLanguageCode(),
        profileId: _wakeWordProfileIdForCurrentSettings(),
        threshold: _userSettings.wakeWordThreshold,
      );
      _applyWakeWordStatus(
        status,
        preferredMessage: autoStarted
            ? _ux(
                '호출어 대기 중입니다. "${_resolvedWakeWordPhraseForCurrentLanguage()}"라고 말하면 바로 듣기 시작합니다.',
                '呼びかけ待機中です。「${_resolvedWakeWordPhraseForCurrentLanguage()}」と言うとすぐ聞き取りを始めます。',
              )
            : _ux(
                '호출어 대기를 시작했습니다. "${_resolvedWakeWordPhraseForCurrentLanguage()}"라고 불러 주세요.',
                '呼びかけ待機を始めました。「${_resolvedWakeWordPhraseForCurrentLanguage()}」と呼びかけてください。',
              ),
      );
      await _startWakeWordLevelMonitoring();
      _ensureWakeWordPolling();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechMessage = _ux(
          '호출어 대기를 시작하지 못했습니다: $error',
          '呼びかけ待機を開始できませんでした: $error',
        );
      });
    }
  }

  Future<void> _stopWakeWordMonitoring({required bool manual}) async {
    _wakeWordStatusPollTimer?.cancel();
    _wakeWordStatusPollTimer = null;
    await _stopWakeWordLevelMonitoring();
    try {
      final status = await _client.stopWakeWord();
      _applyWakeWordStatus(
        status,
        preferredMessage: manual
            ? _ux(
                '호출어 대기를 종료했습니다.',
                '呼びかけ待機を終了しました。',
              )
            : _ux(
                '호출어 대기를 잠시 멈췄습니다.',
                '呼びかけ待機を一時停止しました。',
              ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isWakeWordMonitoring = false;
        _speechMessage = _ux(
          '호출어 대기를 종료하는 중 문제가 생겼습니다: $error',
          '呼びかけ待機の終了中に問題が発生しました: $error',
        );
      });
    }
  }

  void _ensureWakeWordPolling() {
    _wakeWordStatusPollTimer?.cancel();
    _wakeWordStatusPollTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_pollWakeWordStatus()),
    );
    unawaited(_pollWakeWordStatus());
  }

  void _ensureAudioDiagnosticsPolling() {
    _audioDiagnosticsPollTimer?.cancel();
    _audioDiagnosticsPollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_pollAudioDiagnostics()),
    );
    unawaited(_pollAudioDiagnostics());
  }

  Future<void> _pollAudioDiagnostics() async {
    try {
      await _client.fetchAudioDiagnostics();
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {
      // Keep the last known diagnostics in the UI if polling fails.
    }
  }

  Future<void> _pollWakeWordStatus() async {
    if (!_userSettings.wakeWordEnabled && !_isWakeWordMonitoring) {
      return;
    }
    try {
      final status = await _client.fetchWakeWordStatus();
      _applyWakeWordStatus(status);
      if (status.pendingDetection &&
          !_speechBusy &&
          !_isSubmitting &&
          !_isCanonicalizing &&
          !_isRecordingFallback) {
        await _client.acknowledgeWakeWord();
        await _stopWakeWordMonitoring(manual: false);
        if (!mounted) {
          return;
        }
        setState(() {
          _speechMessage = _ux(
            '호출어를 들었어요. 이제 말씀해 주세요.',
            '呼びかけを聞き取りました。続けて話してください。',
          );
        });
        unawaited(_showWakeWordListeningPopup());
        await _startRecordedVoiceFallback();
      }
      if (!status.running) {
        _wakeWordStatusPollTimer?.cancel();
        _wakeWordStatusPollTimer = null;
        _queueWakeWordRearm(const Duration(seconds: 2));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechMessage = _ux(
          '호출어 상태를 확인하지 못했습니다: $error',
          '呼びかけ状態を確認できませんでした: $error',
        );
      });
    }
  }

  void _applyWakeWordStatus(
    WakeWordStatusResponse status, {
    String? preferredMessage,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isWakeWordMonitoring = status.running;
      if (preferredMessage != null) {
        _speechMessage = preferredMessage;
      } else if (status.lastError != null && status.lastError!.isNotEmpty) {
        _speechMessage = _ux(
          '호출어 엔진 상태: ${status.lastError}',
          '呼びかけエンジン状態: ${status.lastError}',
        );
      } else if (status.running && _canShowWakeWordIdleMessage()) {
        _speechMessage = _ux(
          '호출어 대기 중입니다. 반응이 없으면 Windows 기본 입력 장치를 확인해 주세요.',
          '呼びかけ待機中です。反応がない場合は Windows の既定の入力デバイスを確認してください。',
        );
      }
    });
  }

  double _estimatePcm16PeakLevel(Uint8List chunk) {
    if (chunk.length < 2) {
      return 0;
    }
    final view = ByteData.sublistView(chunk);
    var peak = 0.0;
    for (var offset = 0; offset + 1 < chunk.length; offset += 2) {
      final sample = view.getInt16(offset, Endian.little).abs() / 32768.0;
      if (sample > peak) {
        peak = sample;
      }
    }
    return peak.clamp(0.0, 1.0);
  }

  Future<String?> _transcribeLiveAudioBuffer({required bool isFinal}) async {
    final bytes = _liveAudioBytes?.toBytes() ?? Uint8List(0);
    if (bytes.length < _minimumLiveAudioBytes(isFinal: isFinal) ||
        _liveTranscriptionInFlight) {
      return isFinal ? _liveTranscriptionText : null;
    }

    _liveTranscriptionInFlight = true;
    _liveTranscriptionCompleter = Completer<void>();
    final wavPath = await _writeLiveWavFile(bytes);
    try {
      final response = await _client.transcribeAudioFile(
        wavPath,
        languageHint: _preferredLanguageCode(),
      );
      if (!mounted) {
        return response.text;
      }
      final trimmed = response.text.trim();
      if (trimmed.isEmpty) {
        return _liveTranscriptionText;
      }
      setState(() {
        _liveTranscriptionText = trimmed;
        _controller.text = trimmed;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
        _command = null;
        _speechMessage = isFinal
            ? _ux(
                '음성 전사가 끝났습니다. 내용을 확인해 주세요.',
                '音声の文字起こしが終わりました。内容をご確認ください。',
              )
            : _ux(
                '듣는 내용을 실시간으로 글자로 바꾸는 중입니다.',
                '聞き取った内容をリアルタイムで文字に変換しています。',
              );
      });
      if (isFinal &&
          trimmed.isNotEmpty &&
          _shouldAutoInterpretVoice &&
          !_isCanonicalizing &&
          !_isSubmitting) {
        await _submitTextComposerRequest();
      }
      return trimmed;
    } catch (_) {
      return _liveTranscriptionText;
    } finally {
      _liveTranscriptionInFlight = false;
      _liveTranscriptionCompleter?.complete();
      _liveTranscriptionCompleter = null;
      try {
        final tempFile = File(wavPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {
        // Ignore temporary cleanup failures.
      }
    }
  }

  Future<void> _waitForLiveTranscriptionToFinish() async {
    final completer = _liveTranscriptionCompleter;
    if (completer == null) {
      return;
    }
    try {
      await completer.future.timeout(const Duration(seconds: 8));
    } catch (_) {
      // Keep stop flow moving even if a partial transcription stalls.
    }
  }

  Future<String> _writeLiveWavFile(Uint8List pcmBytes) async {
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}visionnavi-live-transcribe-${DateTime.now().millisecondsSinceEpoch}.wav';
    final wavBytes = _buildPcm16WavBytes(
      pcmBytes,
      sampleRate: 16000,
      channels: 1,
      bitsPerSample: 16,
    );
    await File(path).writeAsBytes(wavBytes, flush: true);
    return path;
  }

  Uint8List _buildPcm16WavBytes(
    Uint8List pcmBytes, {
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
  }) {
    final header = ByteData(44);
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataLength = pcmBytes.length;

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i += 1) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + dataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, dataLength, Endian.little);

    return Uint8List.fromList([...header.buffer.asUint8List(), ...pcmBytes]);
  }

  bool _hasCompletedTranscriptionMessage() {
    final message = _speechMessage?.trim();
    if (message == null || message.isEmpty) {
      return false;
    }
    return message.contains('전사가 끝났습니다') ||
        message.contains('내용을 확인해 주세요') ||
        message.contains('文字起こしが終わりました') ||
        message.contains('内容をご確認ください');
  }

  Future<void> _submitTextComposerRequest() async {
    if (_isSubmitting || _isCanonicalizing) {
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    await _interpretCommand();
    if (!mounted) {
      return;
    }
    final command = _command;
    if (command == null) {
      return;
    }
    if (command.requiresConfirmation) {
      await _approveAndRun();
      return;
    }
    await _runReviewedCommand();
  }

  String _commandProgressMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return _ux(
        '요청 내용을 확인하고 있어요.',
        'お願いの内容を確認しています。',
      );
    }

    if (_preferredLanguageCode() == 'ja') {
      return _buildJapaneseProgressMessage(trimmed);
    }
    return _buildKoreanProgressMessage(trimmed);
  }

  String _buildKoreanProgressMessage(String text) {
    var message = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    message = message.replaceAll(RegExp(r'[.!?]+$'), '');

    final replacements = <MapEntry<RegExp, String>>[
      MapEntry(RegExp(r'검색해줘$'), '검색해볼게요'),
      MapEntry(RegExp(r'찾아줘$'), '찾아볼게요'),
      MapEntry(RegExp(r'알려줘$'), '알아볼게요'),
      MapEntry(RegExp(r'열어줘$'), '열어볼게요'),
      MapEntry(RegExp(r'보여줘$'), '보여드릴게요'),
      MapEntry(RegExp(r'정리해줘$'), '정리해볼게요'),
      MapEntry(RegExp(r'요약해줘$'), '요약해볼게요'),
      MapEntry(RegExp(r'적어줘$'), '적어볼게요'),
      MapEntry(RegExp(r'작성해줘$'), '작성해볼게요'),
      MapEntry(RegExp(r'실행해줘$'), '실행해볼게요'),
      MapEntry(RegExp(r'켜줘$'), '켜볼게요'),
      MapEntry(RegExp(r'찾아봐줘$'), '찾아볼게요'),
      MapEntry(RegExp(r'해줘$'), '해볼게요'),
    ];

    for (final replacement in replacements) {
      if (replacement.key.hasMatch(message)) {
        return message.replaceFirst(replacement.key, replacement.value);
      }
    }

    if (message.endsWith('줘')) {
      return '${message.substring(0, message.length - 1)}볼게요';
    }

    if (message.endsWith('하기')) {
      return '$message 도와드릴게요';
    }

    return '$message 진행해볼게요';
  }

  String _buildJapaneseProgressMessage(String text) {
    var message = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    message = message.replaceAll(RegExp(r'[。.!?]+$'), '');

    final replacements = <MapEntry<RegExp, String>>[
      MapEntry(RegExp(r'探して$'), '探してみます。'),
      MapEntry(RegExp(r'検索して$'), '検索してみます。'),
      MapEntry(RegExp(r'教えて$'), '調べてご案内します。'),
      MapEntry(RegExp(r'開いて$'), '開いてみます。'),
      MapEntry(RegExp(r'見せて$'), '表示してみます。'),
      MapEntry(RegExp(r'まとめて$'), 'まとめてみます。'),
      MapEntry(RegExp(r'入力して$'), '入力してみます。'),
    ];

    for (final replacement in replacements) {
      if (replacement.key.hasMatch(message)) {
        return message.replaceFirst(replacement.key, replacement.value);
      }
    }

    return '$message を進めます。';
  }

  String _heroTitle() {
    if (_isUnderstandingInProgress()) {
      return _ux('명령을 이해하고 있어요', '命令を理解しています');
    }
    if (_isExecutionInProgress()) {
      return _ux('화면을 이동하고 있어요', '画面を移動しています');
    }
    if (_hasCompletedTranscriptionMessage()) {
      return _ux('내용을 확인해 주세요', '内容を確認してください');
    }
    if (_speechBusy) {
      return _ux('음성을 글자로 바꾸고 있어요', '音声を文字に変えています');
    }
    if (_isListening || _isRecordingFallback) {
      return _ux('음성을 듣고 있어요', '音声を聞いています');
    }
    if (_status == 'Completed') {
      return _ux('도움을 마쳤어요', 'お手伝いが完了しました');
    }
    if (_status == 'Error') {
      return _ux('다시 확인해 볼게요', 'もう一度確認します');
    }
    return _ux('무엇을 도와드릴까요?', 'どのようにお手伝いしましょうか');
  }

  String _heroSubtitle() {
    if (_isUnderstandingInProgress()) {
      return _ux(
        '요청 내용을 이해하고 있어요. 잠시만 기다려 주세요.',
        'お願いの内容を理解しています。少々お待ちください。',
      );
    }
    if (_isExecutionInProgress()) {
      return _ux(
        '처리가 진행될 때까지 잠시만 기다려 주세요.',
        '処理が終わるまで少々お待ちください。',
      );
    }
    if (_speechBusy) {
      return _ux(
        '음성을 글자로 바꾸고 있어요. 잠시만 기다려 주세요.',
        '音声を文字に変えています。少々お待ちください。',
      );
    }
    return _ux(
      '말하기 버튼을 누르고 말씀해 주세요.',
      '話し始めるボタンを押して話してください。',
    );
  }

  String _headerSubtitle() {
    if (_debugMode) {
      return 'Interpret first, then execute.';
    }
    return _ux(
      '말로 요청하면 도와드려요',
      '話しかけるとお手伝いします',
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

    final highContrast = _userSettings.highContrast;
    final darkTheme = _userSettings.darkTheme && !highContrast;
    final theme = buildAppTheme(
      darkTheme: darkTheme,
      highContrast: highContrast,
      largeText: _userSettings.largeText,
    );
    return theme;
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
                              icon:
                                  const Icon(Icons.copy_all_rounded, size: 16),
                              label: const Text('Copy All'),
                            ),
                            ElevatedButton.icon(
                              onPressed: _exportTraceBundle,
                              icon:
                                  const Icon(Icons.download_rounded, size: 16),
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

  Widget _buildSeniorQuickActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required String command,
    required Color iconColor,
    required Color iconBackground,
  }) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    return InkWell(
      onTap: () => _applyPresetCommand(command),
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: iconColor, size: 26),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          color: surfaceTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: surfaceTheme.textMuted,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeniorSectionCard(
    BuildContext context, {
    required String title,
    Widget? trailing,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
    double titleSpacing = 12,
  }) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: surfaceTheme.textPrimary,
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            SizedBox(height: titleSpacing),
            child,
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
    final failureReason = _failureReason(_result);
    final attachedVoiceFileName = _attachedVoiceFileName();
    final showComposer = _showTextComposer || attachedVoiceFileName != null;
    final examples = [
      (
        label: _ux('기초연금 신청 방법 알려줘', '基礎年金の申請方法を教えて'),
        command: _ux('기초연금 신청 방법 알려줘', '基礎年金の申請方法を教えて'),
      ),
      (
        label: _ux('오늘 날씨 알려줘', '今日の天気を教えて'),
        command: _ux('오늘 날씨 알려줘', '今日の天気を教えて'),
      ),
      (
        label: _ux('가까운 병원 찾아줘', '近い病院を探して'),
        command: _ux('인천에서 가까운 병원 찾아줘', '仁川から近い病院を探して'),
      ),
      (
        label: _ux('약 먹는 시간 적어줘', '薬を飲む時間を書いて'),
        command: _ux('메모장에 약 먹는 시간 적어줘', 'メモ帳に薬を飲む時間を書いて'),
      ),
    ];
    final cards = [
      _buildSeniorQuickActionCard(
        context,
        icon: Icons.volunteer_activism_rounded,
        title: _ux('복지 정보 찾기', '福祉情報を探す'),
        description: _ux(
          '연금과 지원금을 찾아드려요.',
          '年金や支援金を探します。',
        ),
        command: _ux('기초연금 신청 방법 알려줘', '基礎年金の申請方法を教えて'),
        iconColor: const Color(0xFFE25563),
        iconBackground: const Color(0xFFFDEBEC),
      ),
      _buildSeniorQuickActionCard(
        context,
        icon: Icons.map_outlined,
        title: _ux('길찾기', '道案内'),
        description: _ux(
          '가는 길을 안내해 드려요.',
          '行き方を案内します。',
        ),
        command: _ux(
          '네이버 지도에서 서울역에서 송내역 가는 길 찾아줘',
          'NAVER地図でソウル駅からソンネ駅までの道を探して',
        ),
        iconColor: const Color(0xFF68B84C),
        iconBackground: const Color(0xFFEAF8E4),
      ),
      _buildSeniorQuickActionCard(
        context,
        icon: Icons.note_alt_rounded,
        title: _ux('메모 작성', 'メモ作成'),
        description: _ux(
          '말한 내용을 적어드려요.',
          '話した内容を書きます。',
        ),
        command: _ux('메모장에 약 먹는 시간 적어줘', 'メモ帳に薬を飲む時間を書いて'),
        iconColor: const Color(0xFFF39A2E),
        iconBackground: const Color(0xFFFFF1E2),
      ),
      _buildSeniorQuickActionCard(
        context,
        icon: Icons.search_rounded,
        title: _ux('인터넷 검색', 'インターネット検索'),
        description: _ux(
          '궁금한 내용을 찾아드려요.',
          '気になる内容を探します。',
        ),
        command: _ux('오늘 날씨 알려줘', '今日の天気を教えて'),
        iconColor: const Color(0xFF8C4DFF),
        iconBackground: const Color(0xFFF2EBFF),
      ),
    ];
    Widget buildHeroCard() {
      final screenWidth = MediaQuery.sizeOf(context).width;
      final compactHero = screenWidth < 760;
      final heroHeight = showComposer ? null : (compactHero ? 300.0 : 236.0);
      return SizedBox(
        height: heroHeight,
        child: SizedBox(
          width: double.infinity,
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktopHero = constraints.maxWidth >= 760;
                  final isNarrowHero = constraints.maxWidth < 760;
                  final heroButtonSize = constraints.maxWidth >= 1100
                      ? 172.0
                      : (constraints.maxWidth >= 760 ? 136.0 : 120.0);
                  final heroIconSize =
                      constraints.maxWidth >= 760 ? 50.0 : 38.0;
                  final heroButtonLabelStyle = (isNarrowHero
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.titleMedium)
                      ?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  );
                  final textInputButton = isNarrowHero
                      ? OutlinedButton(
                          onPressed: _toggleTextComposer,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(
                            showComposer
                                ? _ux('글자 입력 닫기', '文字入力を閉じる')
                                : _ux('글자로 입력하기', '文字で入力する'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: surfaceTheme.textPrimary,
                            ),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: _toggleTextComposer,
                          icon: Icon(
                            showComposer
                                ? Icons.keyboard_hide_rounded
                                : Icons.keyboard_alt_outlined,
                            size: 18,
                          ),
                          label: Text(
                            showComposer
                                ? _ux('글자 입력 닫기', '文字入力を閉じる')
                                : _ux('글자로 입력하기', '文字で入力する'),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                        );
                  final heroButton = SizedBox(
                    width: heroButtonSize,
                    height: heroButtonSize,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF5A8CFF), Color(0xFF2158E8)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.22),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _userSettings.voiceInputEnabled
                              ? _toggleVoiceInput
                              : null,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isListening || _isRecordingFallback
                                    ? Icons.stop_circle_outlined
                                    : Icons.mic_rounded,
                                size: heroIconSize,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _voiceActionButtonLabel(),
                                style: heroButtonLabelStyle,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                  final heroInfo = Column(
                    crossAxisAlignment: isDesktopHero
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _heroTitle(),
                        textAlign: TextAlign.center,
                        style: (isNarrowHero
                                ? theme.textTheme.headlineSmall
                                : theme.textTheme.headlineLarge)
                            ?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: surfaceTheme.textPrimary,
                        ),
                      ),
                      SizedBox(height: isNarrowHero ? 6 : 10),
                      Text(
                        _heroSubtitle(),
                        textAlign: TextAlign.center,
                        style: (isNarrowHero
                                ? theme.textTheme.bodyMedium
                                : theme.textTheme.titleMedium)
                            ?.copyWith(
                          color: surfaceTheme.textMuted,
                        ),
                      ),
                      if (_speechMessage != null &&
                          (showComposer ||
                              _isCanonicalizing ||
                              _isSubmitting ||
                              _speechBusy ||
                              _hasCompletedTranscriptionMessage())) ...[
                        const SizedBox(height: 12),
                        Text(
                          _speechMessage!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: surfaceTheme.textMuted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  );

                  final heroActions = Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      heroButton,
                      SizedBox(height: isNarrowHero ? 6 : 8),
                      textInputButton,
                    ],
                  );

                  return Column(
                    children: [
                      Expanded(
                        child: isDesktopHero
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(flex: 3, child: heroInfo),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.center,
                                      child: heroActions,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  heroInfo,
                                  const SizedBox(height: 10),
                                  heroButton,
                                  const SizedBox(height: 10),
                                  textInputButton,
                                ],
                              ),
                      ),
                      if (showComposer) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.14),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _controller,
                                minLines: 2,
                                maxLines: 4,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) =>
                                    _submitTextComposerRequest(),
                                style: theme.textTheme.titleMedium,
                                decoration: InputDecoration(
                                  hintText: _ux(
                                    '어떤 도움이 필요한지 입력해보세요',
                                    'どのようなお手伝いが必要か入力してみてください',
                                  ),
                                  hintStyle:
                                      theme.textTheme.titleSmall?.copyWith(
                                    color: surfaceTheme.textMuted,
                                  ),
                                  contentPadding: const EdgeInsets.all(16),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Align(
                                alignment: Alignment.centerRight,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      (_isSubmitting || _isCanonicalizing)
                                          ? null
                                          : _submitTextComposerRequest,
                                  icon: const Icon(Icons.send_rounded),
                                  label: Text(
                                    _isSubmitting || _isCanonicalizing
                                        ? _ux('처리 중', '処理中')
                                        : _ux('요청하기', '依頼する'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    Widget buildExamplesCard() {
      return SizedBox(
        height: showComposer ? null : 104,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: SizedBox(
            width: double.infinity,
            child: _buildSeniorSectionCard(
              context,
              title: _ux('이렇게 말해보세요', 'このように話してみてください'),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              titleSpacing: 8,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: examples
                    .map(
                      (example) => ActionChip(
                        backgroundColor:
                            Theme.of(context).chipTheme.backgroundColor,
                        label: Text(example.label),
                        onPressed: () => _applyPresetCommand(example.command),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        labelStyle: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: surfaceTheme.textPrimary,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      );
    }

    Widget buildQuickActionsCard() {
      final isWideLayout = MediaQuery.sizeOf(context).width >= 1100;
      return SizedBox(
        height: showComposer ? null : (isWideLayout ? 164 : 280),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: SizedBox(
            width: double.infinity,
            child: _buildSeniorSectionCard(
              context,
              title: _ux('자주 하는 작업', 'よく使う作業'),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              titleSpacing: 10,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 12.0;
                  final cardHeight = isWideLayout ? 96.0 : 100.0;

                  if (isWideLayout) {
                    final itemWidth =
                        (constraints.maxWidth - (spacing * 3)) / 4;
                    return Row(
                      children: [
                        for (var index = 0; index < cards.length; index++) ...[
                          SizedBox(
                            width: itemWidth,
                            height: cardHeight,
                            child: cards[index],
                          ),
                          if (index != cards.length - 1)
                            const SizedBox(width: spacing),
                        ],
                      ],
                    );
                  }

                  final itemWidth = (constraints.maxWidth - spacing) / 2;
                  return Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: itemWidth,
                            height: cardHeight,
                            child: cards[0],
                          ),
                          const SizedBox(width: spacing),
                          SizedBox(
                            width: itemWidth,
                            height: cardHeight,
                            child: cards[1],
                          ),
                        ],
                      ),
                      const SizedBox(height: spacing),
                      Row(
                        children: [
                          SizedBox(
                            width: itemWidth,
                            height: cardHeight,
                            child: cards[2],
                          ),
                          const SizedBox(width: spacing),
                          SizedBox(
                            width: itemWidth,
                            height: cardHeight,
                            child: cards[3],
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    final bodyContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildHeroCard(),
        const SizedBox(height: 12),
        buildExamplesCard(),
        const SizedBox(height: 12),
        buildQuickActionsCard(),
        if (failureReason != null && showComposer) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _ux(
                  '다시 확인이 필요한 이유: $failureReason',
                  '再確認が必要な理由: $failureReason',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ],
    );

    return Container(
      color: surfaceTheme.contentBackground,
      padding: const EdgeInsets.all(16),
      child: showComposer
          ? SingleChildScrollView(child: bodyContent)
          : LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  height: constraints.maxHeight,
                  child: bodyContent,
                );
              },
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
                              onChanged: (_isSubmitting || _isCanonicalizing)
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
                              onPressed: (_isSubmitting || _isCanonicalizing)
                                  ? null
                                  : _interpretCommand,
                              child: Text(
                                _isCanonicalizing
                                    ? 'Interpreting...'
                                    : 'Interpret Command',
                              ),
                            ),
                            ElevatedButton(
                              onPressed: (_command == null ||
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

  Widget _buildCustomTitleBar(
    BuildContext context, {
    required ThemeData theme,
    required AppSurfaceTheme surfaceTheme,
  }) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: surfaceTheme.surface,
        border: Border(bottom: BorderSide(color: surfaceTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onDoubleTap: _toggleMaximizeWindow,
              child: DragToMoveArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF66B8FF), Color(0xFF2158E8)],
                          ),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'VisionNavi',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          _headerSubtitle(),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: surfaceTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _openSettingsDialog,
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: Text(_ux('설정', '設定')),
                ),
                const SizedBox(width: 2),
                TextButton.icon(
                  onPressed: _openHelpDialog,
                  icon: const Icon(Icons.help_outline_rounded, size: 18),
                  label: Text(_ux('도움말', 'ヘルプ')),
                ),
                const SizedBox(width: 6),
                _WindowControlButton(
                  icon: Icons.remove_rounded,
                  tooltip: _ux('최소화', '最小化'),
                  onPressed: _minimizeWindow,
                ),
                _WindowControlButton(
                  icon: Icons.close_rounded,
                  tooltip: _ux('닫기', '閉じる'),
                  onPressed: _closeWindow,
                  isClose: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final textScale = !_debugMode
        ? (_userSettings.largeText
            ? (_userSettings.screenScaleEnabled ? 1.22 : 1.16)
            : (_userSettings.screenScaleEnabled ? 1.06 : 1.0))
        : 1.0;
    final scopedTheme = _buildUserScopedTheme(baseTheme);
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
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(
              LogicalKeyboardKey.keyD,
              control: true,
              shift: true,
            ): () {
              setState(() {
                _debugMode = !_debugMode;
              });
            },
          },
          child: Builder(
            builder: (themedContext) {
              final themedTheme = Theme.of(themedContext);
              final themedSurfaceTheme =
                  themedTheme.extension<AppSurfaceTheme>()!;

              return Scaffold(
                backgroundColor: themedSurfaceTheme.shellBackground,
                body: SafeArea(
                  child: Column(
                    children: [
                      _buildCustomTitleBar(
                        themedContext,
                        theme: themedTheme,
                        surfaceTheme: themedSurfaceTheme,
                      ),
                      if (_debugMode)
                        Container(
                          height: 92,
                          decoration: BoxDecoration(
                            color: themedSurfaceTheme.surface,
                            border: Border(
                              bottom:
                                  BorderSide(color: themedSurfaceTheme.border),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: StatusCard(
                                  label: _localizedStatusLabel(),
                                  value: _status,
                                  icon: Icons.mic_none_rounded,
                                  iconBackground: (_isSubmitting ||
                                          _isCanonicalizing)
                                      ? AppColors.successSoft
                                      : themedSurfaceTheme.contentBackground,
                                  iconColor:
                                      (_isSubmitting || _isCanonicalizing)
                                          ? AppColors.success
                                          : themedSurfaceTheme.textMuted,
                                  showWave: true,
                                ),
                              ),
                              VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: themedSurfaceTheme.border,
                              ),
                              Expanded(
                                child: StatusCard(
                                  label: _localizedPolicyLabel(),
                                  value: _localizedPolicyValue(),
                                  icon: _command?.requiresConfirmation == true
                                      ? Icons.lock_outline_rounded
                                      : Icons.bolt_rounded,
                                  iconBackground:
                                      _command?.requiresConfirmation == true
                                          ? AppColors.warningSoft
                                          : themedSurfaceTheme
                                              .contentBackground,
                                  iconColor:
                                      _command?.requiresConfirmation == true
                                          ? AppColors.warning
                                          : themedSurfaceTheme.textMuted,
                                  showDot: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: _debugMode
                            ? _buildDebugModeBody(
                                themedContext,
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
                                themedContext,
                                latestDetail: latestDetail,
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WindowControlButton extends StatefulWidget {
  const _WindowControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onPressed;
  final bool isClose;

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    final background = widget.isClose
        ? (_hovered ? const Color(0xFFE5484D) : Colors.transparent)
        : (_hovered ? surfaceTheme.contentBackground : Colors.transparent);
    final foreground =
        widget.isClose && _hovered ? Colors.white : surfaceTheme.textPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => widget.onPressed(),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 44,
              height: 36,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(widget.icon, size: 18, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
