import 'package:flutter/material.dart';

import '../../../../../app/theme/app_theme.dart';
import '../../models/home_user_settings.dart';

class HomeSettingsDialog extends StatefulWidget {
  const HomeSettingsDialog({
    super.key,
    required this.initialSettings,
  });

  final HomeUserSettings initialSettings;

  @override
  State<HomeSettingsDialog> createState() => _HomeSettingsDialogState();
}

class _HomeSettingsDialogState extends State<HomeSettingsDialog> {
  final ScrollController _bodyScrollController = ScrollController();
  late HomeUserSettings _draft;
  int _selectedTab = 0;

  bool get _isJapanese => _draft.preferredLanguage == '일본어';

  String _t(String ko, String ja) => _isJapanese ? ja : ko;

  List<String> get _tabs => [
        _t('기본 설정', '基本設定'),
        _t('음성 및 입력', '音声と入力'),
        _t('보안', 'セキュリティ'),
        _t('화면 설정', '画面設定'),
      ];

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: Center(
        child: Container(
          width: 820,
          height: 640,
          decoration: BoxDecoration(
            color: surfaceTheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: surfaceTheme.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            children: [
              _DialogHeader(
                title: _t('설정', '設定'),
                subtitle: _t(
                  '사용 방식과 화면 표시 옵션을 조정합니다.',
                  '使い方と画面表示オプションを調整します。',
                ),
                closeTooltip: _t('닫기', '閉じる'),
                onClose: () => Navigator.of(context).pop(),
              ),
              Divider(height: 1, color: surfaceTheme.border),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingsSidebar(
                      items: _tabs,
                      selectedIndex: _selectedTab,
                      onSelect: _selectTab,
                      helperText: _t(
                        '기존 Navi의 설정 모달처럼 왼쪽에서 항목을 고르고 오른쪽에서 내용을 조정하는 구조입니다.',
                        '既存 Navi の設定モーダルのように、左で項目を選び、右で内容を調整する構成です。',
                      ),
                    ),
                    Container(width: 1, color: surfaceTheme.border),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            controller: _bodyScrollController,
                            padding: const EdgeInsets.all(20),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: constraints.maxWidth,
                                ),
                                child: _buildBody(context),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                decoration: BoxDecoration(
                  color: surfaceTheme.contentBackground,
                  border: Border(top: BorderSide(color: surfaceTheme.border)),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    const Spacer(),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(_t('취소', 'キャンセル')),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(_draft),
                      child: Text(_t('저장', '保存')),
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

  Widget _buildBody(BuildContext context) {
    switch (_selectedTab) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionTitle(_t('기본 설정', '基本設定')),
            _ToggleCard(
              title: _t('안전한 명령은 바로 실행', '安全な命令はすぐ実行'),
              description: _t(
                '위험도가 낮은 작업은 확인 없이 바로 진행합니다.',
                '危険度が低い作業は確認なしですぐに進めます。',
              ),
              value: _draft.autoRunSafeCommands,
              onChanged: (value) => setState(
                () => _draft = _draft.copyWith(autoRunSafeCommands: value),
              ),
            ),
            _ToggleCard(
              title: _t('간단한 결과 요약 먼저 보기', 'やさしい結果要約を先に表示'),
              description: _t(
                '디버그 정보보다 사용자가 이해하기 쉬운 결과를 우선 보여줍니다.',
                'デバッグ情報よりも利用者が分かりやすい結果を先に見せます。',
              ),
              value: _draft.showSimpleSummary,
              onChanged: (value) => setState(
                () => _draft = _draft.copyWith(showSimpleSummary: value),
              ),
            ),
            _LanguageChoiceCard(
              title: _t('기본 언어', '基本言語'),
              description: _t(
                '안내 문구와 기본 입력 예시에 사용할 언어입니다.',
                '案内文と入力例に使う言語です。',
              ),
              value: _draft.preferredLanguage,
              onSelected: (value) => setState(
                () => _draft = _draft.copyWith(preferredLanguage: value),
              ),
              isJapanese: _isJapanese,
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionTitle(_t('음성 및 입력', '音声と入力')),
            _ToggleCard(
              title: _t('음성 입력 버튼 표시', '音声入力ボタンを表示'),
              description: _t(
                '홈 화면에서 음성 요청 버튼 자리를 항상 보이게 합니다.',
                'ホーム画面で音声依頼ボタンをいつも表示します。',
              ),
              value: _draft.voiceInputEnabled,
              onChanged: (value) => setState(
                () => _draft = _draft.copyWith(voiceInputEnabled: value),
              ),
            ),
            _SliderCard(
              title: _t('마이크 감도', 'マイク感度'),
              description: _t(
                '음성 입력을 받을 때 반응 민감도를 조정합니다.',
                '音声入力時の反応感度を調整します。',
              ),
              value: _draft.microphoneSensitivity,
              min: 0.0,
              max: 1.0,
              onChanged: (value) => setState(
                () => _draft = _draft.copyWith(microphoneSensitivity: value),
              ),
            ),
            _SliderCard(
              title: _t('안내 속도', '案内速度'),
              description: _t(
                '음성 안내나 단계 설명의 빠르기를 조정합니다.',
                '音声案内や手順説明の速さを調整します。',
              ),
              value: _draft.guidanceSpeed,
              min: 0.7,
              max: 1.3,
              onChanged: (value) => setState(
                () => _draft = _draft.copyWith(guidanceSpeed: value),
              ),
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionTitle(_t('보안', 'セキュリティ')),
            _ToggleCard(
              title: _t('민감한 작업은 항상 확인', '重要な作業は必ず確認'),
              description: _t(
                '설정 변경이나 중요한 작업은 실행 전에 다시 묻습니다.',
                '設定変更や重要な作業は実行前にもう一度確認します。',
              ),
              value: _draft.requireSensitiveApproval,
              onChanged: (value) => setState(
                () => _draft = _draft.copyWith(requireSensitiveApproval: value),
              ),
            ),
            _ToggleCard(
              title: _t('외부 사이트 이동 전 알려주기', '外部サイト移動前に案内'),
              description: _t(
                '새 웹사이트로 이동할 때 간단한 안내를 먼저 보여줍니다.',
                '新しいWebサイトへ移動する前に案内を表示します。',
              ),
              value: _draft.warnBeforeExternalSites,
              onChanged: (value) => setState(
                () => _draft = _draft.copyWith(warnBeforeExternalSites: value),
              ),
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionTitle(_t('화면 설정', '画面設定')),
            _ToggleCard(
              title: _t('큰 글씨 사용', '大きな文字を使う'),
              description: _t(
                '고령자 사용에 맞게 주요 글자와 버튼을 조금 더 크게 보여줍니다.',
                '高齢者向けに主要な文字とボタンを少し大きく表示します。',
              ),
              value: _draft.largeText,
              onChanged: (value) =>
                  setState(() => _draft = _draft.copyWith(largeText: value)),
            ),
            _ToggleCard(
              title: _t('고대비 보기', '高コントラスト表示'),
              description: _t(
                '글자와 배경의 대비를 높여 읽기 쉽게 만듭니다.',
                '文字と背景のコントラストを高めて読みやすくします。',
              ),
              value: _draft.highContrast,
              onChanged: (value) =>
                  setState(() => _draft = _draft.copyWith(highContrast: value)),
            ),
            _ToggleCard(
              title: _t('어두운 화면 사용', 'ダーク画面を使う'),
              description: _t(
                '야간이나 저조도 환경에서 눈부심을 줄입니다.',
                '夜間や暗い環境でまぶしさを減らします。',
              ),
              value: _draft.darkTheme,
              onChanged: (value) =>
                  setState(() => _draft = _draft.copyWith(darkTheme: value)),
            ),
          ],
        );
    }
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
      padding: const EdgeInsets.fromLTRB(24, 22, 16, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: surfaceTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            tooltip: closeTooltip,
          ),
        ],
      ),
    );
  }
}

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.helperText,
  });

  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final String helperText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;

    return SizedBox(
      width: 190,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              _SidebarItem(
                label: items[index],
                selected: index == selectedIndex,
                onTap: () => onSelect(index),
              ),
              if (index != items.length - 1) const SizedBox(height: 8),
            ],
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surfaceTheme.contentBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: surfaceTheme.border),
              ),
              child: Text(
                helperText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: surfaceTheme.textMuted,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : surfaceTheme.border,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: surfaceTheme.textMuted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _SliderCard extends StatelessWidget {
  const _SliderCard({
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final String description;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: surfaceTheme.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: value,
                    min: min,
                    max: max,
                    onChanged: onChanged,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    value.toStringAsFixed(2),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageChoiceCard extends StatelessWidget {
  const _LanguageChoiceCard({
    required this.title,
    required this.description,
    required this.value,
    required this.onSelected,
    required this.isJapanese,
  });

  final String title;
  final String description;
  final String value;
  final ValueChanged<String> onSelected;
  final bool isJapanese;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    final options = [
      (
        value: '한국어',
        label: isJapanese ? '韓国語' : '한국어',
      ),
      (
        value: '일본어',
        label: isJapanese ? '日本語' : '일본어',
      ),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: surfaceTheme.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final option in options)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: value == option.value,
                    onSelected: (_) => onSelected(option.value),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
