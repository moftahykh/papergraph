import 'package:flutter_test/flutter_test.dart';
import 'package:paper_graph/main.dart';

void main() {
  testWidgets('PaperGraph smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PaperGraphApp());
    expect(find.byType(PaperGraphApp), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
