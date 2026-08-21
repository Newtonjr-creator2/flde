import 'package:flutter_test/flutter_test.dart';

import 'package:real_buzzing_identifier/main.dart';

import 'test_helpers.dart';

void main() {
  setUp(() async {
    await mockPathProvider();
  });

  testWidgets('App launches and shows the home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const RealBuzzingIdeApp());
    await tester.pumpAndSettle();

    expect(find.text('RealBuzzingIdentifier'), findsOneWidget);
    expect(find.text('Create Flutter/Dart Project'), findsOneWidget);
    expect(find.text('Open Existing Project'), findsOneWidget);
    expect(find.text('Import Project from ZIP'), findsOneWidget);
  });
}
