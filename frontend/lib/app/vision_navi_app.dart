import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'theme/app_theme.dart';
import '../features/home/presentation/home_screen.dart';

class VisionNaviApp extends StatelessWidget {
  const VisionNaviApp({super.key});

  @override
  Widget build(BuildContext context) {
    final virtualWindowFrameBuilder = VirtualWindowFrameInit();
    return MaterialApp(
      title: 'VisionNavi',
      theme: buildAppTheme(),
      builder: (context, child) {
        return virtualWindowFrameBuilder(
          context,
          child ?? const SizedBox.shrink(),
        );
      },
      home: const HomeScreen(),
    );
  }
}
