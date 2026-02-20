//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <syncfusion_pdfviewer_windows/syncfusion_pdfviewer_windows_plugin.h>
#include <url_launcher_windows/url_launcher_windows.h>
#include <wacom_stu_plugin/wacom_stu_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  SyncfusionPdfviewerWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("SyncfusionPdfviewerWindowsPlugin"));
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
  WacomStuPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("WacomStuPluginCApi"));
}
