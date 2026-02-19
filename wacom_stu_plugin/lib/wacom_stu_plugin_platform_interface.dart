import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'wacom_stu_plugin_method_channel.dart';

abstract class WacomStuPluginPlatform extends PlatformInterface {
  /// Constructs a WacomStuPluginPlatform.
  WacomStuPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static WacomStuPluginPlatform _instance = MethodChannelWacomStuPlugin();

  /// The default instance of [WacomStuPluginPlatform] to use.
  ///
  /// Defaults to [MethodChannelWacomStuPlugin].
  static WacomStuPluginPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [WacomStuPluginPlatform] when
  /// they register themselves.
  static set instance(WacomStuPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
