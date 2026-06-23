import 'package:flutter_test/flutter_test.dart';
import 'package:visionnavi_frontend/app/vision_navi_app.dart';

void main() {
  testWidgets('app renders title', (tester) async {
    await tester.pumpWidget(const VisionNaviApp());

    expect(find.text('VisionNavi'), findsOneWidget);
  });
}
