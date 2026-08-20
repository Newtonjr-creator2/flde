import 'package:flutter_test/flutter_test.dart';
import 'package:real_buzzing_identifier/main.dart';

void main() {
  testWidgets('FLDE app starts', (tester) async {
    await tester.pumpWidget(const FldeApp());
    expect(find.text('FLDE'), findsWidgets);
  });
}
