import 'package:flutter_test/flutter_test.dart';
import 'package:macro_relay/main.dart';

void main() {
  testWidgets('dashboard loads', (tester) async {
    await tester.pumpWidget(const MacroRelayApp());
    expect(find.text('MACRORELAY'), findsOneWidget);
  });
}
