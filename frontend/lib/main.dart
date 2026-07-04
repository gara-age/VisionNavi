import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app/vision_navi_app.dart';

const _fixedWindowSize = Size(900, 730);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: _fixedWindowSize,
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setMinimumSize(_fixedWindowSize);
    await windowManager.setMaximumSize(_fixedWindowSize);
    await windowManager.setResizable(false);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const VisionNaviApp());
}
