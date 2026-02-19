#include "include/wacom_stu_plugin/wacom_stu_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "wacom_stu_plugin.h"

void WacomStuPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  WacomStuPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
