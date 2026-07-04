class HomeUserSettings {
  const HomeUserSettings({
    this.autoRunSafeCommands = true,
    this.showSimpleSummary = true,
    this.preferredLanguage = 'ko',
    this.voiceInputEnabled = true,
    this.voiceAutoInterpret = true,
    this.wakeWordEnabled = true,
    this.wakeWordPhrase = '나비야',
    this.wakeWordThreshold = 0.2,
    this.microphoneSensitivity = 0.65,
    this.guidanceSpeed = 1.0,
    this.guidanceVolume = 1.0,
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
      preferredLanguage: _normalizeLanguage(
        json['preferred_language'] as String?,
      ),
      voiceInputEnabled: json['voice_input_enabled'] as bool? ?? true,
      voiceAutoInterpret: json['voice_auto_interpret'] as bool? ?? true,
      wakeWordEnabled: json['wake_word_enabled'] as bool? ?? true,
      wakeWordPhrase: _normalizeWakeWordPhrase(
        json['wake_word_phrase'] as String?,
      ),
      wakeWordThreshold:
          (json['wake_word_threshold'] as num?)?.toDouble() ?? 0.2,
      microphoneSensitivity:
          (json['microphone_sensitivity'] as num?)?.toDouble() ?? 0.65,
      guidanceSpeed: (json['guidance_speed'] as num?)?.toDouble() ?? 1.0,
      guidanceVolume: (json['guidance_volume'] as num?)?.toDouble() ?? 1.0,
      startWithWindows: json['start_with_windows'] as bool? ?? false,
      requireSensitiveApproval:
          json['require_sensitive_approval'] as bool? ?? true,
      warnBeforeExternalSites:
          json['warn_before_external_sites'] as bool? ?? true,
      confirmPersonalInfoInput:
          json['confirm_personal_info_input'] as bool? ?? true,
      alwaysConfirmDestructiveActions:
          json['always_confirm_destructive_actions'] as bool? ?? true,
      verboseResultGuidance:
          json['verbose_result_guidance'] as bool? ?? true,
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
      preferredLanguage:
          preferredLanguage == null
              ? this.preferredLanguage
              : _normalizeLanguage(preferredLanguage),
      voiceInputEnabled: voiceInputEnabled ?? this.voiceInputEnabled,
      voiceAutoInterpret: voiceAutoInterpret ?? this.voiceAutoInterpret,
      wakeWordEnabled: wakeWordEnabled ?? this.wakeWordEnabled,
      wakeWordPhrase:
          wakeWordPhrase == null
              ? this.wakeWordPhrase
              : _normalizeWakeWordPhrase(wakeWordPhrase),
      wakeWordThreshold:
          (wakeWordThreshold ?? this.wakeWordThreshold).clamp(0.05, 0.9),
      microphoneSensitivity:
          (microphoneSensitivity ?? this.microphoneSensitivity).clamp(0.1, 1.0),
      guidanceSpeed: (guidanceSpeed ?? this.guidanceSpeed).clamp(0.7, 1.3),
      guidanceVolume: (guidanceVolume ?? this.guidanceVolume).clamp(0.7, 1.3),
      startWithWindows: startWithWindows ?? this.startWithWindows,
      requireSensitiveApproval:
          requireSensitiveApproval ?? this.requireSensitiveApproval,
      warnBeforeExternalSites:
          warnBeforeExternalSites ?? this.warnBeforeExternalSites,
      confirmPersonalInfoInput:
          confirmPersonalInfoInput ?? this.confirmPersonalInfoInput,
      alwaysConfirmDestructiveActions:
          alwaysConfirmDestructiveActions ??
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
      case '日本語':
      case '일본어':
        return 'ja';
      default:
        return 'ko';
    }
  }

  static String _normalizeWakeWordPhrase(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return '나비야';
    }

    switch (normalized) {
      case '나비야':
      case '헤이 나비':
      case 'ねえ、ナビ':
      case 'ナビさん':
        return normalized;
    }

    return '나비야';
  }
}
