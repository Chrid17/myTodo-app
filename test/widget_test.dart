import 'package:flutter_test/flutter_test.dart';
import 'package:my_project/main.dart';

void main() {
  testWidgets('First page renders with navigation button', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Verify the First Page UI renders as expected.
    expect(find.text('First Page'), findsOneWidget);
    expect(find.text('Go to Second Page'), findsOneWidget);
  });
}
