class HomeUserSettings {
  const HomeUserSettings({
    this.autoRunSafeCommands = true,
    this.showSimpleSummary = true,
    this.preferredLanguage = 'ko',
    this.voiceInputEnabled = true,
    this.voiceAutoInterpret = true,
    this.wakeWordEnabled = true,
    this.wakeWordPhrase = '\ub098\ube44\uc57c',
    this.wakeWordThreshold = 0.3,
    this.microphoneSensitivity = 0.65,
    this.guidanceSpeed = 1.0,
    this.guidanceVolume = 1.0,
    this.ttsVoiceKo = 'ko-KR-SunHiNeural',
    this.ttsVoiceJa = '',
    this.startWithWindows = false,
    this.requireSensitiveApproval = true,
    this.warnBeforeExternalSites = true,
    this.confirmPersonalInfoInput = true,
    this.alwaysConfirmDestructiveActions = true,
    this.verboseResultGuidance = true,
    this.largeText = true,
    this.highContrast = false,
    this.darkTheme = false,
    this.screenScaleEnabled = true,
  });

  factory HomeUserSettings.fromJson(Map<String, dynamic> json) {
    return HomeUserSettings(
      autoRunSafeCommands: json['auto_run_safe_commands'] as bool? ?? true,
      showSimpleSummary: json['show_simple_summary'] as bool? ?? true,
      preferredLanguage:
          _normalizeLanguage(json['preferred_language'] as String?),
      voiceInputEnabled: json['voice_input_enabled'] as bool? ?? true,
      voiceAutoInterpret: json['voice_auto_interpret'] as bool? ?? true,
      wakeWordEnabled: json['wake_word_enabled'] as bool? ?? true,
      wakeWordPhrase:
          _normalizeWakeWordPhrase(json['wake_word_phrase'] as String?),
      wakeWordThreshold:
          (json['wake_word_threshold'] as num?)?.toDouble() ?? 0.2,
      microphoneSensitivity:
          (json['microphone_sensitivity'] as num?)?.toDouble() ?? 0.65,
      guidanceSpeed: (json['guidance_speed'] as num?)?.toDouble() ?? 1.0,
      guidanceVolume: (json['guidance_volume'] as num?)?.toDouble() ?? 1.0,
      ttsVoiceKo: _normalizeTtsVoice(
        json['tts_voice_ko'] as String?,
        fallback: 'ko-KR-SunHiNeural',
      ),
      ttsVoiceJa: _normalizeTtsVoice(
        json['tts_voice_ja'] as String?,
        fallback: '',
      ),
      startWithWindows: json['start_with_windows'] as bool? ?? false,
      requireSensitiveApproval:
          json['require_sensitive_approval'] as bool? ?? true,
      warnBeforeExternalSites:
          json['warn_before_external_sites'] as bool? ?? true,
      confirmPersonalInfoInput:
          json['confirm_personal_info_input'] as bool? ?? true,
      alwaysConfirmDestructiveActions:
          json['always_confirm_destructive_actions'] as bool? ?? true,
      verboseResultGuidance: json['verbose_result_guidance'] as bool? ?? true,
      largeText: json['large_text'] as bool? ?? true,
      highContrast: json['high_contrast'] as bool? ?? false,
      darkTheme: json['dark_theme'] as bool? ?? false,
      screenScaleEnabled: json['screen_scale_enabled'] as bool? ?? true,
    );
  }

  final bool autoRunSafeCommands;
  final bool showSimpleSummary;
  final String preferredLanguage;
  final bool voiceInputEnabled;
  final bool voiceAutoInterpret;
  final bool wakeWordEnabled;
  final String wakeWordPhrase;
  final double wakeWordThreshold;
  final double microphoneSensitivity;
  final double guidanceSpeed;
  final double guidanceVolume;
  final String ttsVoiceKo;
  final String ttsVoiceJa;
  final bool startWithWindows;
  final bool requireSensitiveApproval;
  final bool warnBeforeExternalSites;
  final bool confirmPersonalInfoInput;
  final bool alwaysConfirmDestructiveActions;
  final bool verboseResultGuidance;
  final bool largeText;
  final bool highContrast;
  final bool darkTheme;
  final bool screenScaleEnabled;

  HomeUserSettings copyWith({
    bool? autoRunSafeCommands,
    bool? showSimpleSummary,
    String? preferredLanguage,
    bool? voiceInputEnabled,
    bool? voiceAutoInterpret,
    bool? wakeWordEnabled,
    String? wakeWordPhrase,
    double? wakeWordThreshold,
    double? microphoneSensitivity,
    double? guidanceSpeed,
    double? guidanceVolume,
    String? ttsVoiceKo,
    String? ttsVoiceJa,
    bool? startWithWindows,
    bool? requireSensitiveApproval,
    bool? warnBeforeExternalSites,
    bool? confirmPersonalInfoInput,
    bool? alwaysConfirmDestructiveActions,
    bool? verboseResultGuidance,
    bool? largeText,
    bool? highContrast,
    bool? darkTheme,
    bool? screenScaleEnabled,
  }) {
    return HomeUserSettings(
      autoRunSafeCommands: autoRunSafeCommands ?? this.autoRunSafeCommands,
      showSimpleSummary: showSimpleSummary ?? this.showSimpleSummary,
      preferredLanguage: preferredLanguage == null
          ? this.preferredLanguage
          : _normalizeLanguage(preferredLanguage),
      voiceInputEnabled: voiceInputEnabled ?? this.voiceInputEnabled,
      voiceAutoInterpret: voiceAutoInterpret ?? this.voiceAutoInterpret,
      wakeWordEnabled: wakeWordEnabled ?? this.wakeWordEnabled,
      wakeWordPhrase: wakeWordPhrase == null
          ? this.wakeWordPhrase
          : _normalizeWakeWordPhrase(wakeWordPhrase),
      wakeWordThreshold: (wakeWordThreshold ?? this.wakeWordThreshold).clamp(
        0.05,
        0.9,
      ),
      microphoneSensitivity:
          (microphoneSensitivity ?? this.microphoneSensitivity).clamp(0.1, 1.0),
      guidanceSpeed: (guidanceSpeed ?? this.guidanceSpeed).clamp(0.7, 1.3),
      guidanceVolume: (guidanceVolume ?? this.guidanceVolume).clamp(0.7, 1.3),
      ttsVoiceKo: ttsVoiceKo == null
          ? this.ttsVoiceKo
          : _normalizeTtsVoice(ttsVoiceKo, fallback: 'ko-KR-SunHiNeural'),
      ttsVoiceJa: ttsVoiceJa == null
          ? this.ttsVoiceJa
          : _normalizeTtsVoice(ttsVoiceJa, fallback: ''),
      startWithWindows: startWithWindows ?? this.startWithWindows,
      requireSensitiveApproval:
          requireSensitiveApproval ?? this.requireSensitiveApproval,
      warnBeforeExternalSites:
          warnBeforeExternalSites ?? this.warnBeforeExternalSites,
      confirmPersonalInfoInput:
          confirmPersonalInfoInput ?? this.confirmPersonalInfoInput,
      alwaysConfirmDestructiveActions: alwaysConfirmDestructiveActions ??
          this.alwaysConfirmDestructiveActions,
      verboseResultGuidance:
          verboseResultGuidance ?? this.verboseResultGuidance,
      largeText: largeText ?? this.largeText,
      highContrast: highContrast ?? this.highContrast,
      darkTheme: darkTheme ?? this.darkTheme,
      screenScaleEnabled: screenScaleEnabled ?? this.screenScaleEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'auto_run_safe_commands': autoRunSafeCommands,
      'show_simple_summary': showSimpleSummary,
      'preferred_language': preferredLanguage,
      'voice_input_enabled': voiceInputEnabled,
      'voice_auto_interpret': voiceAutoInterpret,
      'wake_word_enabled': wakeWordEnabled,
      'wake_word_phrase': wakeWordPhrase,
      'wake_word_threshold': wakeWordThreshold,
      'microphone_sensitivity': microphoneSensitivity,
      'guidance_speed': guidanceSpeed,
      'guidance_volume': guidanceVolume,
      'tts_voice_ko': ttsVoiceKo,
      'tts_voice_ja': ttsVoiceJa,
      'start_with_windows': startWithWindows,
      'require_sensitive_approval': requireSensitiveApproval,
      'warn_before_external_sites': warnBeforeExternalSites,
      'confirm_personal_info_input': confirmPersonalInfoInput,
      'always_confirm_destructive_actions': alwaysConfirmDestructiveActions,
      'verbose_result_guidance': verboseResultGuidance,
      'large_text': largeText,
      'high_contrast': highContrast,
      'dark_theme': darkTheme,
      'screen_scale_enabled': screenScaleEnabled,
    };
  }

  static String _normalizeLanguage(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return 'ko';
    }

    switch (normalized) {
      case 'ja':
      case 'ja-jp':
      case 'jp':
      case 'japanese':
      case '\u65e5\u672c\u8a9e':
      case '\uc77c\ubcf8\uc5b4':
        return 'ja';
      default:
        return 'ko';
    }
  }

  static String _normalizeWakeWordPhrase(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return '\ub098\ube44\uc57c';
    }

    switch (normalized) {
      case '\ub098\ube44\uc57c':
      case '\ud5e4\uc774 \ub098\ube44':
      case '\u306d\u3048\u3001\u30ca\u30d3':
      case '\u30ca\u30d3\u3055\u3093':
        return normalized;
    }

    return '\ub098\ube44\uc57c';
  }

  static String _normalizeTtsVoice(String? value, {required String fallback}) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return fallback;
    }
    const supportedKoVoices = <String>{
      'ko-KR-SunHiNeural',
      'ko-KR-InJoonNeural',
      'ko-KR-HyunsuMultilingualNeural',
    };
    const supportedJaVoices = <String>{
      '',
      'ja-JP-NanamiNeural',
      'ja-JP-KeitaNeural',
    };

    if (normalized.startsWith('ko-')) {
      return supportedKoVoices.contains(normalized) ? normalized : fallback;
    }
    if (normalized.startsWith('ja-')) {
      return supportedJaVoices.contains(normalized) ? normalized : fallback;
    }
    return fallback;
  }
}
