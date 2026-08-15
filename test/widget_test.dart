import 'package:flutter_test/flutter_test.dart';
import 'package:scene_app/main.dart';

void main() {
  testWidgets('CarRunnerApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CarRunnerApp());

    // Verify that the title or app is rendered
    expect(find.byType(CarRunnerApp), findsOneWidget);
  });
}

