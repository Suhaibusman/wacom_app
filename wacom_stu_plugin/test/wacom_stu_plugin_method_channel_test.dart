import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wacom_stu_plugin/wacom_stu_plugin_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelWacomStuPlugin platform = MethodChannelWacomStuPlugin();
  const MethodChannel channel = MethodChannel('wacom_stu_plugin');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
