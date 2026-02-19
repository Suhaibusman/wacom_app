import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'wacom_stu_plugin_platform_interface.dart';

/// An implementation of [WacomStuPluginPlatform] that uses method channels.
class MethodChannelWacomStuPlugin extends WacomStuPluginPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('wacom_stu_plugin');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
