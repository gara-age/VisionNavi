import 'package:flutter/material.dart';

import '../../../../../app/theme/app_theme.dart';
import '../../models/home_user_settings.dart';

class HomeSettingsDialog extends StatefulWidget {
  const HomeSettingsDialog({
    super.key,
    required this.initialSettings,
    required this.onTestGuidanceTts,
  });

  final HomeUserSettings initialSettings;
  final Future<void> Function(
    HomeUserSettings settings,
    String language,
    String provider,
  ) onTestGuidanceTts;

  @override
  State<HomeSettingsDialog> createState() => _HomeSettingsDialogState();
}

class _HomeSettingsDialogState extends State<HomeSettingsDialog> {
  final ScrollController _bodyScrollController = ScrollController();
  late HomeUserSettings _draft;
  int _selectedTab = 0;

  bool get _isJapanese => _draft.preferredLanguage == 'ja';

  String _t(String ko, String ja) => _isJapanese ? ja : ko;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialSettings;
  }

  @override
  void dispose() {
    _bodyScrollController.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    setState(() => _selectedTab = index);
    if (_bodyScrollController.hasClients) {
      _bodyScrollController.jumpTo(0);
    }
  }

  void _save() {
    Navigator.of(context).pop(_draft);
  }

  List<_VoiceOptionData> _koVoiceOptions() {
    return const [
      _VoiceOptionData('ko-KR-SunHiNeural', 'SunHi', '부드럽고 또렷한 기본 음성'),
      _VoiceOptionData('ko-KR-InJoonNeural', 'InJoon', '차분한 남성 음성'),
      _VoiceOptionData(
        'ko-KR-HyunsuMultilingualNeural',
        'Hyunsu',
        '밝고 자연스러운 남성 음성',
      ),
    ];
  }

  List<_VoiceOptionData> _jaVoiceOptions() {
    return const [
      _VoiceOptionData('', '기본 추천', '현재 가장 안정적으로 재생되는 기본 음성'),
      _VoiceOptionData('ja-JP-NanamiNeural', 'Nanami', '부드러운 여성 음성'),
      _VoiceOptionData('ja-JP-KeitaNeural', 'Keita', '차분한 남성 음성'),
    ];
  }

  // ignore: unused_element
  List<_VoiceOptionData> _wakeWordPhraseOptions() {
    if (_isJapanese) {
      return const [
        _VoiceOptionData('ねえ、ナビ', 'ねえ、ナビ', '일본어 기본 호출어'),
        _VoiceOptionData('ナビさん', 'ナビさん', '조금 더 정중한 호출어'),
      ];
    }

    return const [
      _VoiceOptionData('나비야', '나비야', '기본 한국어 호출어'),
      _VoiceOptionData('헤이 나비', '헤이 나비', '조금 더 또렷한 호출어'),
    ];
  }

  List<_VoiceOptionData> _wakeWordPhraseOptionsSafe() {
    if (_isJapanese) {
      return const [
        _VoiceOptionData(
          '\u306d\u3048\u3001\u30ca\u30d3',
          '\u306d\u3048\u3001\u30ca\u30d3',
          '\uc77c\ubcf8\uc5b4 \uae30\ubcf8 \ud638\ucd9c\uc5b4',
        ),
        _VoiceOptionData(
          '\u30ca\u30d3\u3055\u3093',
          '\u30ca\u30d3\u3055\u3093',
          '\uc77c\ubcf8\uc5b4 \ud638\ucd9c\uc5b4',
        ),
      ];
    }

    return const [
      _VoiceOptionData(
        '\ub098\ube44\uc57c',
        '\ub098\ube44\uc57c',
        '\ud55c\uad6d\uc5b4 \uae30\ubcf8 \ud638\ucd9c\uc5b4',
      ),
      _VoiceOptionData(
        '\ud5e4\uc774 \ub098\ube44',
        '\ud5e4\uc774 \ub098\ube44',
        '\ud55c\uad6d\uc5b4 \ud638\ucd9c\uc5b4',
      ),
    ];
  }

  String _voiceDescription(String language, String value) {
    final options = language == 'ja' ? _jaVoiceOptions() : _koVoiceOptions();
    for (final option in options) {
      if (option.value == value) {
        return option.description;
      }
    }
    return language == 'ja' ? '선택한 일본어 안내 음성' : '선택한 한국어 안내 음성';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.transparent,
      child: Container(
        width: 820,
        height: 680,
        decoration: BoxDecoration(
          color: surfaceTheme.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: surfaceTheme.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F0F172A),
              blurRadius: 36,
              offset: Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          children: [
            _DialogHeader(
              title: _t('설정', '設定'),
              subtitle: _t(
                '사용 방법, 말하기, 안전, 화면 보기를 생활형 환경에 맞게 조정합니다.',
                '使い方、話しかけ、安心、画面表示を生活スタイルに合わせて調整します。',
              ),
              closeTooltip: _t('닫기', '閉じる'),
              onClose: () => Navigator.of(context).pop(),
            ),
            Divider(height: 1, color: surfaceTheme.border),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 230,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 20, 16, 18),
                      child: Column(
                        children: [
                          _SettingsNavTile(
                            icon: Icons.home_rounded,
                            title: _t('사용 방법', '使い方'),
                            description: _t('기본 사용 설정', '基本の使い方'),
                            selected: _selectedTab == 0,
                            onTap: () => _selectTab(0),
                          ),
                          const SizedBox(height: 10),
                          _SettingsNavTile(
                            icon: Icons.mic_rounded,
                            title: _t('말하기 설정', '話しかけ設定'),
                            description: _t('음성 입력과 안내 설정', '音声入力と案内設定'),
                            selected: _selectedTab == 1,
                            onTap: () => _selectTab(1),
                          ),
                          const SizedBox(height: 10),
                          _SettingsNavTile(
                            icon: Icons.shield_outlined,
                            title: _t('안전 설정', '安心設定'),
                            description: _t('중요 작업 확인', '大切な操作の確認'),
                            selected: _selectedTab == 2,
                            onTap: () => _selectTab(2),
                          ),
                          const SizedBox(height: 10),
                          _SettingsNavTile(
                            icon: Icons.desktop_windows_outlined,
                            title: _t('화면 보기', '画面表示'),
                            description: _t('글자와 화면 크기', '文字と画面サイズ'),
                            selected: _selectedTab == 3,
                            onTap: () => _selectTab(3),
                          ),
                          const Spacer(),
                          _InfoCallout(
                            title: _t('알아두세요', 'ご案内'),
                            description: _t(
                              '설정은 이 PC에 저장되며, 저장하기를 눌러야 반영됩니다.',
                              '設定はこの PC に保存され、保存を押すと反映されます。',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(width: 1, color: surfaceTheme.border),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _bodyScrollController,
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                      child: _buildBody(context),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              decoration: BoxDecoration(
                color: surfaceTheme.contentBackground,
                border: Border(top: BorderSide(color: surfaceTheme.border)),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _t(
                        '일부 설정은 아직 준비 중이며, 연결된 기능부터 먼저 저장됩니다.',
                        '一部の設定は準備中で、接続済みの機能から先に保存されます。',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: surfaceTheme.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(_t('취소', 'キャンセル')),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _save,
                    child: Text(_t('저장하기', '保存する')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_selectedTab) {
      case 0:
        return _buildUsageTab(context);
      case 1:
        return _buildSpeechTab(context);
      case 2:
        return _buildSafetyTab(context);
      case 3:
      default:
        return _buildDisplayTab(context);
    }
  }

  Widget _buildUsageTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: _t('사용 방법', '使い方'),
          description: _t(
            'VisionNavi 기본 사용 방법을 정해요.',
            'VisionNavi の基本的な使い方を決めます。',
          ),
        ),
        _SubSectionTitle(_t('언어 설정', '言語設定')),
        _SubSectionDescription(
          _t('앱에서 사용할 언어를 선택하세요.', 'アプリで使う言語を選んでください。'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _LanguageOptionCard(
                label: '한국어',
                shortLabel: 'KR',
                selected: _draft.preferredLanguage == 'ko',
                onTap: () => setState(
                  () => _draft = _draft.copyWith(
                    preferredLanguage: 'ko',
                    wakeWordPhrase: _draft.wakeWordPhrase == 'ねえ、ナビ' ||
                            _draft.wakeWordPhrase == 'ナビさん'
                        ? '나비야'
                        : _draft.wakeWordPhrase,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LanguageOptionCard(
                label: '日本語',
                shortLabel: 'JP',
                selected: _draft.preferredLanguage == 'ja',
                onTap: () => setState(
                  () => _draft = _draft.copyWith(
                    preferredLanguage: 'ja',
                    wakeWordPhrase: _draft.wakeWordPhrase == '나비야' ||
                            _draft.wakeWordPhrase == '헤이 나비'
                        ? 'ねえ、ナビ'
                        : _draft.wakeWordPhrase,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _SubSectionTitle(_t('음성 안내', '音声案内')),
        _SubSectionDescription(
          _t('VisionNavi가 들려주는 안내 속도를 조절해요.', 'VisionNavi の案内速度を調整します。'),
        ),
        const SizedBox(height: 12),
        _SliderSettingCard(
          icon: Icons.record_voice_over_rounded,
          color: const Color(0xFF8B5CF6),
          title: _t('말하는 속도', '話す速さ'),
          description: _t(
            '안내 음성의 말하는 속도를 조절합니다.',
            '案内音声の話す速さを調整します。',
          ),
          value: _draft.guidanceSpeed,
          min: 0.7,
          max: 1.3,
          minLabel: _t('천천히', 'ゆっくり'),
          centerLabel: _speedLabel(_draft.guidanceSpeed),
          maxLabel: _t('빠르게', '速く'),
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(guidanceSpeed: value),
          ),
        ),
        const SizedBox(height: 16),
        _DisabledSettingCard(
          icon: Icons.power_settings_new_rounded,
          color: const Color(0xFF3B82F6),
          title: _t('컴퓨터 시작할 때 함께 실행', 'パソコン起動時に一緒に実行'),
          description: _t(
            '현재 저장은 되지만 Windows 시작 프로그램 연결은 아직 준비 중입니다.',
            '現在は保存のみで、Windows のスタートアップ連携は準備中です。',
          ),
          badge: _t('준비중', '準備中'),
          value: _draft.startWithWindows,
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(startWithWindows: value),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeechTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: _t('말하기 설정', '話しかけ設定'),
          description: _t(
            '말로 요청하고 들을 때 관련된 설정을 조절합니다.',
            '話しかけるときと聞き取るときの設定を調整します。',
          ),
        ),
        _ToggleSettingCard(
          icon: Icons.mic_rounded,
          color: const Color(0xFF2563EB),
          title: _t('말하기 버튼 표시', '話しかけボタン表示'),
          description: _t(
            '메인 화면에 말하기 버튼을 표시합니다.',
            'メイン画面に話しかけボタンを表示します。',
          ),
          value: _draft.voiceInputEnabled,
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(voiceInputEnabled: value),
          ),
        ),
        const SizedBox(height: 12),
        _ToggleSettingCard(
          icon: Icons.chat_bubble_outline_rounded,
          color: const Color(0xFF22C55E),
          title: _t('말을 마치면 바로 알아듣기', '話し終えたらすぐ理解する'),
          description: _t(
            '음성 입력 뒤 바로 명령 확인 단계로 넘어갑니다.',
            '音声入力のあと、すぐに命令確認へ進みます。',
          ),
          value: _draft.voiceAutoInterpret,
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(voiceAutoInterpret: value),
          ),
        ),
        const SizedBox(height: 12),
        _ChoiceSettingCard(
          icon: Icons.graphic_eq_rounded,
          color: const Color(0xFF7C3AED),
          title: _t('마이크 반응 정도', 'マイク反応の強さ'),
          description: _t(
            '작은 목소리를 얼마나 민감하게 들을지 정합니다.',
            '小さな声をどれくらい敏感に聞くかを決めます。',
          ),
          options: [
            _ChoiceOptionData(
              label: _t('낮게', '低め'),
              description: _t('큰 소리 위주로 듣기', '大きな声を中心に聞く'),
              selected: _draft.microphoneSensitivity < 0.5,
              onTap: () => setState(
                () => _draft = _draft.copyWith(microphoneSensitivity: 0.35),
              ),
            ),
            _ChoiceOptionData(
              label: _t('보통', '普通'),
              description: _t('일반적인 크기로 듣기', '一般的な大きさで聞く'),
              selected: _draft.microphoneSensitivity >= 0.5 &&
                  _draft.microphoneSensitivity < 0.8,
              onTap: () => setState(
                () => _draft = _draft.copyWith(microphoneSensitivity: 0.65),
              ),
            ),
            _ChoiceOptionData(
              label: _t('높게', '高め'),
              description: _t('작은 소리도 잘 듣기', '小さな声もよく聞く'),
              selected: _draft.microphoneSensitivity >= 0.8,
              onTap: () => setState(
                () => _draft = _draft.copyWith(microphoneSensitivity: 0.9),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DisabledSliderSettingCard(
          icon: Icons.volume_up_rounded,
          color: const Color(0xFFF59E0B),
          title: _t('안내 음량', '案内音量'),
          description: _t(
            '설정 저장은 되지만 현재 앱 음성 출력 볼륨에는 직접 연결되지 않았습니다.',
            '設定は保存されますが、現在はアプリ音声出力の音量へ直接は連携していません。',
          ),
          value: _draft.guidanceVolume,
          min: 0.7,
          max: 1.3,
          minLabel: _t('낮게', '低め'),
          centerLabel: _volumeLabel(_draft.guidanceVolume),
          maxLabel: _t('크게', '大きく'),
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(guidanceVolume: value),
          ),
        ),
        const SizedBox(height: 12),
        _VoiceDropdownSettingCard(
          icon: Icons.record_voice_over_rounded,
          color: const Color(0xFF0F766E),
          title: _t('한국어 안내 목소리', '韓国語の案内音声'),
          description: _voiceDescription('ko', _draft.ttsVoiceKo),
          value: _draft.ttsVoiceKo,
          options: _koVoiceOptions(),
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(
              ttsVoiceKo: value ?? _draft.ttsVoiceKo,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => widget.onTestGuidanceTts(_draft, 'ko', 'edge'),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('\ud55c\uad6d\uc5b4 Edge \ud14c\uc2a4\ud2b8'),
          ),
        ),
        const SizedBox(height: 12),
        _VoiceDropdownSettingCard(
          icon: Icons.multitrack_audio_rounded,
          color: const Color(0xFF2563EB),
          title: _t('일본어 안내 목소리', '日本語の案内音声'),
          description: _voiceDescription('ja', _draft.ttsVoiceJa),
          value: _draft.ttsVoiceJa,
          options: _jaVoiceOptions(),
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(
              ttsVoiceJa: value ?? _draft.ttsVoiceJa,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => widget.onTestGuidanceTts(_draft, 'ja', 'edge'),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('\uc77c\ubcf8\uc5b4 Edge \ud14c\uc2a4\ud2b8'),
          ),
        ),
        const SizedBox(height: 12),
        _ToggleSettingCard(
          icon: Icons.hearing_rounded,
          color: const Color(0xFF2563EB),
          title: _t('“나비야” 기다리기', '「ナビ」待機'),
          description: _t(
            '호출어를 들으면 바로 음성을 들을 준비를 합니다.',
            '呼びかけを聞くと、すぐに音声を聞く準備をします。',
          ),
          value: _draft.wakeWordEnabled,
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(wakeWordEnabled: value),
          ),
        ),
        const SizedBox(height: 12),
        _VoiceDropdownSettingCard(
          icon: Icons.campaign_rounded,
          color: const Color(0xFF7C3AED),
          title: _t('호출어 선택', '呼びかけの選択'),
          description: _t(
            '듣고 싶은 호출어를 하나 골라 주세요.',
            '使いたい呼びかけを一つ選んでください。',
          ),
          value: _draft.wakeWordPhrase,
          options: _wakeWordPhraseOptionsSafe(),
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(
              wakeWordPhrase: value ?? _draft.wakeWordPhrase,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ChoiceSettingCard(
          icon: Icons.hearing_disabled_outlined,
          color: const Color(0xFF4F46E5),
          title: _t('호출어 반응 정도', '呼びかけ反応の強さ'),
          description: _t(
            '호출어를 어느 정도 민감하게 들을지 정합니다.',
            '呼びかけをどれくらい敏感に聞くかを決めます。',
          ),
          options: [
            _ChoiceOptionData(
              label: _t('낮게', '低め'),
              description: _t('정확한 발음 위주로 듣기', 'はっきりした発音を中心に聞く'),
              selected: _draft.wakeWordThreshold >= 0.35,
              onTap: () => setState(
                () => _draft = _draft.copyWith(wakeWordThreshold: 0.4),
              ),
            ),
            _ChoiceOptionData(
              label: _t('보통', '普通'),
              description: _t('일반적인 반응', '標準的な反応'),
              selected: _draft.wakeWordThreshold >= 0.2 &&
                  _draft.wakeWordThreshold < 0.35,
              onTap: () => setState(
                () => _draft = _draft.copyWith(wakeWordThreshold: 0.25),
              ),
            ),
            _ChoiceOptionData(
              label: _t('높게', '高め'),
              description: _t('작은 소리에도 반응하기', '小さな声にも反応する'),
              selected: _draft.wakeWordThreshold < 0.2,
              onTap: () => setState(
                () => _draft = _draft.copyWith(wakeWordThreshold: 0.12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSafetyTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: _t('안전 설정', '安心設定'),
          description: _t(
            '중요한 작업 전 안내와 확인 방식을 정합니다.',
            '大切な作業の前にどう案内し確認するかを決めます。',
          ),
        ),
        _InfoCallout(
          title: _t('현재 상태', '現在の状態'),
          description: _t(
            '이 항목들은 저장은 되지만 오케스트레이터 정책에 아직 직접 연결되지 않았습니다.',
            'これらの項目は保存されますが、まだオーケストレーターの実行ポリシーには直接連携していません。',
          ),
          badge: _t('준비중', '準備中'),
        ),
        const SizedBox(height: 14),
        _DisabledSettingCard(
          icon: Icons.help_outline_rounded,
          color: const Color(0xFF2563EB),
          title: _t('중요한 작업은 다시 물어보기', '大切な作業はもう一度確認'),
          description: _t(
            '삭제, 결제, 개인정보 입력 같은 작업 전에 다시 확인합니다.',
            '削除、決済、個人情報入力の前にもう一度確認します。',
          ),
          badge: _t('준비중', '準備中'),
          value: _draft.requireSensitiveApproval,
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(requireSensitiveApproval: value),
          ),
        ),
        const SizedBox(height: 12),
        _DisabledSettingCard(
          icon: Icons.open_in_new_rounded,
          color: const Color(0xFF0EA5E9),
          title: _t('다른 사이트로 이동 전에 알려주기', '別サイト移動前に知らせる'),
          description: _t(
            '새 사이트나 외부 프로그램을 열기 전에 먼저 알려줍니다.',
            '新しいサイトや外部プログラムを開く前に先に知らせます。',
          ),
          badge: _t('준비중', '準備中'),
          value: _draft.warnBeforeExternalSites,
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(warnBeforeExternalSites: value),
          ),
        ),
        const SizedBox(height: 12),
        _DisabledSettingCard(
          icon: Icons.badge_outlined,
          color: const Color(0xFF22C55E),
          title: _t('개인정보 입력 전에 확인하기', '個人情報入力前に確認'),
          description: _t(
            '이름, 전화번호, 주소를 넣기 전에 다시 확인합니다.',
            '名前、電話番号、住所を入れる前に再確認します。',
          ),
          badge: _t('준비중', '準備中'),
          value: _draft.confirmPersonalInfoInput,
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(confirmPersonalInfoInput: value),
          ),
        ),
        const SizedBox(height: 12),
        _DisabledSettingCard(
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFF59E0B),
          title: _t('삭제나 결제는 항상 확인하기', '削除や決済は常に確認'),
          description: _t(
            '위험한 작업은 반드시 다시 물어본 뒤 실행합니다.',
            '危険な作業は必ず再確認してから実行します。',
          ),
          badge: _t('준비중', '準備中'),
          value: _draft.alwaysConfirmDestructiveActions,
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(
              alwaysConfirmDestructiveActions: value,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _DisabledSettingCard(
          icon: Icons.campaign_outlined,
          color: const Color(0xFF8B5CF6),
          title: _t('실행 결과를 자세히 알려주기', '実行結果を詳しく知らせる'),
          description: _t(
            '작업이 어떻게 끝났는지 더 자세한 안내를 제공합니다.',
            '作業がどう終わったかを、より詳しく案内します。',
          ),
          badge: _t('준비중', '準備中'),
          value: _draft.verboseResultGuidance,
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(verboseResultGuidance: value),
          ),
        ),
      ],
    );
  }

  Widget _buildDisplayTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: _t('화면 보기', '画面表示'),
          description: _t(
            '글자와 화면을 보기 쉽게 조절해요.',
            '文字と画面を見やすく調整します。',
          ),
        ),
        _ToggleSettingCard(
          icon: Icons.text_fields_rounded,
          color: const Color(0xFF2563EB),
          title: _t('큰 글씨 사용', '大きい文字を使う'),
          description: _t(
            '글자를 더 크게 보여줍니다.',
            '文字をより大きく表示します。',
          ),
          value: _draft.largeText,
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(largeText: value),
          ),
        ),
        const SizedBox(height: 12),
        _ToggleSettingCard(
          icon: Icons.wb_sunny_outlined,
          color: const Color(0xFF22C55E),
          title: _t('또렷하게 보기', 'くっきり表示'),
          description: _t(
            '글자와 버튼의 대비를 높여 더 또렷하게 보여줍니다.',
            '文字やボタンのコントラストを高めてくっきり表示します。',
          ),
          value: _draft.highContrast,
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(
              highContrast: value,
              darkTheme: value ? false : _draft.darkTheme,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ToggleSettingCard(
          icon: Icons.dark_mode_outlined,
          color: const Color(0xFF7C3AED),
          title: _t('다크 모드', 'ダークモード'),
          description: _t(
            '눈부심을 줄이도록 어두운 화면으로 바꿉니다.',
            'まぶしさを減らすため暗い画面に切り替えます。',
          ),
          value: _draft.darkTheme,
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(
              darkTheme: value,
              highContrast: value ? false : _draft.highContrast,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ToggleSettingCard(
          icon: Icons.desktop_windows_outlined,
          color: const Color(0xFFF59E0B),
          title: _t('화면 크기 조절', '画面サイズ調整'),
          description: _t(
            '앱 안의 글자와 요소를 조금 더 크게 표시합니다.',
            'アプリ内の文字や要素を少し大きく表示します。',
          ),
          value: _draft.screenScaleEnabled,
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(screenScaleEnabled: value),
          ),
        ),
      ],
    );
  }

  String _speedLabel(double value) {
    if (value < 0.9) {
      return _t('천천히', 'ゆっくり');
    }
    if (value > 1.1) {
      return _t('빠르게', '速く');
    }
    return _t('보통', '普通');
  }

  String _volumeLabel(double value) {
    if (value < 0.9) {
      return _t('낮게', '低め');
    }
    if (value > 1.1) {
      return _t('크게', '大きく');
    }
    return _t('보통', '普通');
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.title,
    required this.subtitle,
    required this.closeTooltip,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final String closeTooltip;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 14, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: surfaceTheme.textMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: closeTooltip,
            icon: const Icon(Icons.close_rounded, size: 32),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: theme.textTheme.titleMedium?.copyWith(
              color: surfaceTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubSectionTitle extends StatelessWidget {
  const _SubSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
    );
  }
}

class _SubSectionDescription extends StatelessWidget {
  const _SubSectionDescription(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final surfaceTheme = Theme.of(context).extension<AppSurfaceTheme>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: surfaceTheme.textMuted,
            ),
      ),
    );
  }
}

class _SettingsNavTile extends StatelessWidget {
  const _SettingsNavTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : surfaceTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : surfaceTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 26,
              color: selected
                  ? theme.colorScheme.primary
                  : surfaceTheme.textPrimary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: surfaceTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCallout extends StatelessWidget {
  const _InfoCallout({
    required this.title,
    required this.description,
    this.badge,
  });

  final String title;
  final String description;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: surfaceTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                _StatusBadge(label: badge!),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: surfaceTheme.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageOptionCard extends StatelessWidget {
  const _LanguageOptionCard({
    required this.label,
    required this.shortLabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String shortLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : surfaceTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : surfaceTheme.border,
          ),
        ),
        child: Row(
          children: [
            Text(
              shortLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: selected
                      ? theme.colorScheme.primary
                      : surfaceTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceOptionData {
  const _ChoiceOptionData({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;
}

class _ChoiceSettingCard extends StatelessWidget {
  const _ChoiceSettingCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.options,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final List<_ChoiceOptionData> options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: surfaceTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitleRow(
            icon: icon,
            color: color,
            title: title,
            description: description,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var index = 0; index < options.length; index++) ...[
                Expanded(
                  child: _ChoiceOptionTile(option: options[index]),
                ),
                if (index != options.length - 1) const SizedBox(width: 10),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoiceOptionTile extends StatelessWidget {
  const _ChoiceOptionTile({required this.option});

  final _ChoiceOptionData option;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: option.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: option.selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: option.selected
                ? theme.colorScheme.primary
                : theme.dividerColor,
          ),
        ),
        child: Column(
          children: [
            Text(
              option.label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              option.description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleSettingCard extends StatelessWidget {
  const _ToggleSettingCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final surfaceTheme = Theme.of(context).extension<AppSurfaceTheme>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: surfaceTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _CardTitleRow(
              icon: icon,
              color: color,
              title: title,
              description: description,
            ),
          ),
          const SizedBox(width: 16),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _DisabledSettingCard extends StatelessWidget {
  const _DisabledSettingCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.badge,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String badge;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: surfaceTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _CardTitleRow(
                        icon: icon,
                        color: color,
                        title: title,
                        description: description,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(label: badge),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Opacity(
            opacity: 0.55,
            child: IgnorePointer(
              child: Switch(
                value: value,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderSettingCard extends StatelessWidget {
  const _SliderSettingCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.minLabel,
    required this.centerLabel,
    required this.maxLabel,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final double value;
  final double min;
  final double max;
  final String minLabel;
  final String centerLabel;
  final String maxLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: surfaceTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitleRow(
            icon: icon,
            color: color,
            title: title,
            description: description,
          ),
          const SizedBox(height: 14),
          Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
          Row(
            children: [
              Text(minLabel, style: theme.textTheme.bodySmall),
              const Spacer(),
              Text(
                centerLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(maxLabel, style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _DisabledSliderSettingCard extends StatelessWidget {
  const _DisabledSliderSettingCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.minLabel,
    required this.centerLabel,
    required this.maxLabel,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final double value;
  final double min;
  final double max;
  final String minLabel;
  final String centerLabel;
  final String maxLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: surfaceTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _CardTitleRow(
                  icon: icon,
                  color: color,
                  title: title,
                  description: description,
                ),
              ),
              const SizedBox(width: 8),
              const _StatusBadge(label: '준비중'),
            ],
          ),
          const SizedBox(height: 14),
          Opacity(
            opacity: 0.55,
            child: IgnorePointer(
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          Row(
            children: [
              Text(minLabel, style: theme.textTheme.bodySmall),
              const Spacer(),
              Text(
                centerLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(maxLabel, style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardTitleRow extends StatelessWidget {
  const _CardTitleRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: surfaceTheme.textMuted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _VoiceOptionData {
  const _VoiceOptionData(this.value, this.label, this.description);

  final String value;
  final String label;
  final String description;
}

class _VoiceDropdownSettingCard extends StatelessWidget {
  const _VoiceDropdownSettingCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String value;
  final List<_VoiceOptionData> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: surfaceTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitleRow(
            icon: icon,
            color: color,
            title: title,
            description: description,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: surfaceTheme.contentBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: surfaceTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: surfaceTheme.border),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            items: options
                .map(
                  (option) => DropdownMenuItem<String>(
                    value: option.value,
                    child: Text(option.label),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
