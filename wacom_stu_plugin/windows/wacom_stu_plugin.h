#pragma once

#ifndef NOCRYPT
#define NOCRYPT
#endif

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <memory>

// Forward declarations
namespace WacomGSS {
  namespace STU {
    class Tablet;
    class UsbInterface;
  }
}

namespace wgssSTU = WacomGSS::STU;

class WacomStuPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  WacomStuPlugin();
  virtual ~WacomStuPlugin();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<WacomGSS::STU::Tablet> tablet;
  std::unique_ptr<WacomGSS::STU::UsbInterface> usbInterface;
};
