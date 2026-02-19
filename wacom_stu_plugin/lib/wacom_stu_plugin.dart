
import 'wacom_stu_plugin_platform_interface.dart';

class WacomStuPlugin {
  Future<String?> getPlatformVersion() {
    return WacomStuPluginPlatform.instance.getPlatformVersion();
  }
}
