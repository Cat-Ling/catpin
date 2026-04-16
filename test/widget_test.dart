import 'package:flutter_test/flutter_test.dart';
import 'package:catpin/main.dart';

void main() {
  testWidgets('Catpin app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CatpinApp());
    expect(find.byType(CatpinApp), findsOneWidget);
  });
}
