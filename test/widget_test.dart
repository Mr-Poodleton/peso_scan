
import 'package:flutter_test/flutter_test.dart';
import 'package:peso_scan/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PesoScanApp());

    // Verify that the app starts
    expect(find.text('PesoScan'), findsOneWidget);
  });
}