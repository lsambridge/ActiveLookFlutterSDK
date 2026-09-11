import 'package:activelook_sdk/activelook_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockActivelookSdkPlatform extends ActivelookSdkPlatform with MockPlatformInterfaceMixin {
  bool connectCalled = false;
  String? lastText;

  @override
  Future<void> connect(String id) async {
    connectCalled = true;
  }

  @override
  Future<void> text(
    int x,
    int y,
    ActiveLookTextRotation rotation,
    int fontSize,
    int color,
    String text,
  ) async {
    lastText = text;
  }

  @override
  Future<int> getBatteryLevel() async => 77;
}

void main() {
  test('ActivelookSdk delegates to the platform instance', () async {
    final fakePlatform = MockActivelookSdkPlatform();
    ActivelookSdkPlatform.instance = fakePlatform;

    final sdk = ActivelookSdk();
    await sdk.connect('AA:BB:CC:DD:EE:FF');
    expect(fakePlatform.connectCalled, isTrue);

    await sdk.text(0, 0, ActiveLookTextRotation.bottomLeftToRight, 2, 15, 'Race Mode');
    expect(fakePlatform.lastText, 'Race Mode');

    expect(await sdk.getBatteryLevel(), 77);
  });
}
