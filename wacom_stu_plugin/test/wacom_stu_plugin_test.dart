import 'package:flutter_test/flutter_test.dart';
import 'package:wacom_stu_plugin/wacom_stu_plugin.dart';
import 'package:wacom_stu_plugin/wacom_stu_plugin_platform_interface.dart';
import 'package:wacom_stu_plugin/wacom_stu_plugin_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockWacomStuPluginPlatform
    with MockPlatformInterfaceMixin
    implements WacomStuPluginPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final WacomStuPluginPlatform initialPlatform = WacomStuPluginPlatform.instance;

  test('$MethodChannelWacomStuPlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelWacomStuPlugin>());
  });

  test('getPlatformVersion', () async {
    WacomStuPlugin wacomStuPlugin = WacomStuPlugin();
    MockWacomStuPluginPlatform fakePlatform = MockWacomStuPluginPlatform();
    WacomStuPluginPlatform.instance = fakePlatform;

    expect(await wacomStuPlugin.getPlatformVersion(), '42');
  });
}
