import 'package:flutter_test/flutter_test.dart';

import 'package:keyra_app/main.dart';

void main() {
  testWidgets('Keyra app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const KeyraApp());

    expect(find.text('Keyra'), findsWidgets);
  });
}
