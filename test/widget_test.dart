import 'package:flutter_test/flutter_test.dart';

import 'package:real_buzzing_identifier/main.dart';

import 'test_helpers.dart';

void main() {
  setUp(() async {
    await mockPathProvider();
  });

  testWidgets('App launches and shows the home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FldeApp());
    await tester.pumpAndSettle();

    // The home screen may show "FLDE" in multiple places (logo, title, status bar).
    // So we only check that it appears at least once.
    expect(find.text('FLDE'), findsWidgets);
    expect(find.text('Create Flutter project'), findsOneWidget);
    expect(find.text('Open folder'), findsOneWidget);
    expect(find.text('Import ZIP'), findsOneWidget);
  });
}
