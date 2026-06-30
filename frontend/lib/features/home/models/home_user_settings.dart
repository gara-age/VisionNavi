class HomeUserSettings {
  const HomeUserSettings({
    this.autoRunSafeCommands = true,
    this.showSimpleSummary = true,
    this.preferredLanguage = '한국어',
    this.voiceInputEnabled = true,
    this.microphoneSensitivity = 0.65,
    this.guidanceSpeed = 1.0,
    this.requireSensitiveApproval = true,
    this.warnBeforeExternalSites = false,
    this.largeText = true,
    this.highContrast = false,
    this.darkTheme = false,
  });

  factory HomeUserSettings.fromJson(Map<String, dynamic> json) {
    return HomeUserSettings(
      autoRunSafeCommands: json['auto_run_safe_commands'] as bool? ?? true,
      showSimpleSummary: json['show_simple_summary'] as bool? ?? true,
      preferredLanguage: json['preferred_language'] as String? ?? '한국어',
      voiceInputEnabled: json['voice_input_enabled'] as bool? ?? true,
      microphoneSensitivity:
          (json['microphone_sensitivity'] as num?)?.toDouble() ?? 0.65,
      guidanceSpeed: (json['guidance_speed'] as num?)?.toDouble() ?? 1.0,
      requireSensitiveApproval:
          json['require_sensitive_approval'] as bool? ?? true,
      warnBeforeExternalSites:
          json['warn_before_external_sites'] as bool? ?? false,
      largeText: json['large_text'] as bool? ?? true,
      highContrast: json['high_contrast'] as bool? ?? false,
      darkTheme: json['dark_theme'] as bool? ?? false,
    );
  }

  final bool autoRunSafeCommands;
  final bool showSimpleSummary;
  final String preferredLanguage;
  final bool voiceInputEnabled;
  final double microphoneSensitivity;
  final double guidanceSpeed;
  final bool requireSensitiveApproval;
  final bool warnBeforeExternalSites;
  final bool largeText;
  final bool highContrast;
  final bool darkTheme;

  HomeUserSettings copyWith({
    bool? autoRunSafeCommands,
    bool? showSimpleSummary,
    String? preferredLanguage,
    bool? voiceInputEnabled,
    double? microphoneSensitivity,
    double? guidanceSpeed,
    bool? requireSensitiveApproval,
    bool? warnBeforeExternalSites,
    bool? largeText,
    bool? highContrast,
    bool? darkTheme,
  }) {
    return HomeUserSettings(
      autoRunSafeCommands: autoRunSafeCommands ?? this.autoRunSafeCommands,
      showSimpleSummary: showSimpleSummary ?? this.showSimpleSummary,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      voiceInputEnabled: voiceInputEnabled ?? this.voiceInputEnabled,
      microphoneSensitivity:
          microphoneSensitivity ?? this.microphoneSensitivity,
      guidanceSpeed: guidanceSpeed ?? this.guidanceSpeed,
      requireSensitiveApproval:
          requireSensitiveApproval ?? this.requireSensitiveApproval,
      warnBeforeExternalSites:
          warnBeforeExternalSites ?? this.warnBeforeExternalSites,
      largeText: largeText ?? this.largeText,
      highContrast: highContrast ?? this.highContrast,
      darkTheme: darkTheme ?? this.darkTheme,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'auto_run_safe_commands': autoRunSafeCommands,
      'show_simple_summary': showSimpleSummary,
      'preferred_language': preferredLanguage,
      'voice_input_enabled': voiceInputEnabled,
      'microphone_sensitivity': microphoneSensitivity,
      'guidance_speed': guidanceSpeed,
      'require_sensitive_approval': requireSensitiveApproval,
      'warn_before_external_sites': warnBeforeExternalSites,
      'large_text': largeText,
      'high_contrast': highContrast,
      'dark_theme': darkTheme,
    };
  }
}
