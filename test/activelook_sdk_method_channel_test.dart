import 'package:activelook_sdk/src/activelook_sdk_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelActivelookSdk();
  const channel = MethodChannel('activelook_sdk');

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        calls.add(methodCall);
        switch (methodCall.method) {
          case 'getBatteryLevel':
            return 88;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('connect forwards the glasses id', () async {
    await platform.connect('AA:BB:CC:DD:EE:FF');
    expect(calls.single.method, 'connect');
    expect(calls.single.arguments, {'id': 'AA:BB:CC:DD:EE:FF'});
  });

  test('getBatteryLevel returns the platform value', () async {
    expect(await platform.getBatteryLevel(), 88);
  });
}
