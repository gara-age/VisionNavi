import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/colors.dart';

class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    this.showWave = false,
    this.showDot = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final bool showWave;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final surfaceTheme = Theme.of(context).extension<AppSurfaceTheme>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: surfaceTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: surfaceTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (showWave)
            _WaveBars(active: value == 'Running')
          else if (showDot)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
        ],
      ),
    );
  }
}

class _WaveBars extends StatefulWidget {
  const _WaveBars({required this.active});

  final bool active;

  @override
  State<_WaveBars> createState() => _WaveBarsState();
}

class _WaveBarsState extends State<_WaveBars> with SingleTickerProviderStateMixin {
  static const List<int> _delaySteps = [0, 80, 160, 240, 320];
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _WaveBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) {
      return;
    }
    if (widget.active) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
          5,
          (_) => Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: AppColors.success,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(_delaySteps.length, (index) {
            final delayedValue = (_controller.value - (_delaySteps[index] / 1000)) % 1.0;
            final curveValue = Curves.easeInOut.transform(
              delayedValue <= 0.5 ? delayedValue * 2 : (1 - delayedValue) * 2,
            );
            final height = 4.0 + (10.0 * curveValue);
            return Container(
              width: 4,
              height: height,
              margin: const EdgeInsets.only(left: 2),
              decoration: BoxDecoration(
                color: AppColors.success,
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        );
      },
    );
  }
}
