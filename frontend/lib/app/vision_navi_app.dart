import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import '../features/home/presentation/home_screen.dart';

class VisionNaviApp extends StatelessWidget {
  const VisionNaviApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VisionNavi',
      theme: buildAppTheme(),
      home: const HomeScreen(),
    );
  }
}
