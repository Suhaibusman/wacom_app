#include "wacom_stu_plugin.h"
#include <flutter/standard_method_codec.h>
#include <WacomGSS/STU/Tablet.hpp>
#include <WacomGSS/STU/getUsbDevices.hpp>
#include <WacomGSS/STU/UsbInterface.hpp>

using flutter::EncodableValue;

WacomStuPlugin::WacomStuPlugin() {}
WacomStuPlugin::~WacomStuPlugin() {
  if (tablet) tablet->disconnect();
}

void WacomStuPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {

  auto plugin = std::make_unique<WacomStuPlugin>();

  auto channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(),
          "wacom_stu_channel",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

void WacomStuPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {

  if (call.method_name() == "connect") {
    try {
      auto devices = wgssSTU::getUsbDevices();
      if (devices.empty()) {
        result->Error("NO_DEVICE", "No STU device found");
        return;
      }

      auto device = devices[0];
      usbInterface = std::make_unique<wgssSTU::UsbInterface>();
      
      std::error_code ec = usbInterface->connect(device, true);
      if (ec) {
        result->Error("CONNECTION_FAILED", "Failed to connect to device: " + ec.message());
        return;
      }

      tablet = std::make_unique<wgssSTU::Tablet>();
      tablet->attach(std::move(usbInterface)); // ownership transferred to tablet
      // Note: usbInterface unique_ptr is now moved, so member variable is null/invalid. 
      // Reuse tablet->getInterface() if needed or manage lifecycle differently. 
      // For simplicity in this fix, we'll let tablet own it.
      
      result->Success(EncodableValue("Connected"));
    } catch (const std::exception& e) {
      result->Error("EXCEPTION", e.what());
    }
  }

  else if (call.method_name() == "disconnect") {
    if (tablet) {
      tablet->disconnect();
      tablet.reset();
    }
    result->Success(EncodableValue("Disconnected"));
  }

  else {
    result->NotImplemented();
  }
}
