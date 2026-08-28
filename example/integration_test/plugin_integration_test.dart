// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:activelook_sdk/activelook_sdk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('draw commands error with NOT_CONNECTED when no glasses are connected', (
    WidgetTester tester,
  ) async {
    final plugin = ActivelookSdk();

    await expectLater(
      plugin.clear(),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'NOT_CONNECTED')),
    );
  });
}
