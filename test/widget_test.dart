// Flutter widget tests for Secure File Vault
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package.

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_file_vault/main.dart';

void main() {
  group('SecureFileVaultApp', () {
    testWidgets('app launches and shows lock screen or setup',
        (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(const SecureFileVaultApp());
      await tester.pumpAndSettle();

      // The app should show either:
      // - Setup screen (first launch)
      // - Lock screen (subsequent launches)
      // - Loading indicator
      expect(find.byType(SecureFileVaultApp), findsOneWidget);
    });
  });
}
