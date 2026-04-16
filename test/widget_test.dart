import 'package:flutter_test/flutter_test.dart';
import 'package:binternet_app/main.dart';

void main() {
  testWidgets('Binternet app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BinternetApp());
    expect(find.byType(BinternetApp), findsOneWidget);
  });
}
