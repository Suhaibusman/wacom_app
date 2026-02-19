#include "wacom_stu_plugin.h"
#include <flutter/standard_method_codec.h>
#include <WacomGSS/STU/Tablet.hpp>
#include <WacomGSS/STU/getUsbDevices.hpp>
#include <WacomGSS/STU/UsbInterface.hpp>
#include <WacomGSS/STU/ProtocolHelper.hpp>
#include <WacomGSS/STU/ReportHandler.hpp>

using flutter::EncodableValue;

// PenHandler to process reports
class PenHandler : public WacomGSS::STU::ProtocolHelper::ReportHandler {
public:
    PenHandler(std::function<void(const EncodableValue&)> callback) 
        : callback_(callback) {}

    void onReport(WacomGSS::STU::Protocol::PenData& penData) override {
        Notify(penData.x, penData.y, penData.pressure, penData.sw);
    }

    void onReport(WacomGSS::STU::Protocol::PenDataOption& penData) override {
        Notify(penData.x, penData.y, penData.pressure, penData.sw);
    }

    void onReport(WacomGSS::STU::Protocol::PenDataTimeCountSequence& penData) override {
        Notify(penData.x, penData.y, penData.pressure, penData.sw);
    }

    void onReport(WacomGSS::STU::Protocol::PenDataEncrypted& penData) override {
        // Encrypted data contains 2 pen data points
        for (const auto& p : penData.penData) {
            Notify(p.x, p.y, p.pressure, p.sw);
        }
    }
    
    void onReport(WacomGSS::STU::Protocol::PenDataEncryptedOption& penData) override {
         // EncryptedOption inherits from Encrypted, so it also has penData[2]
        for (const auto& p : penData.penData) {
            Notify(p.x, p.y, p.pressure, p.sw);
        }
    }

    void onReport(WacomGSS::STU::Protocol::PenDataTimeCountSequenceEncrypted& penData) override {
        // This one inherits from PenDataTimeCountSequence, so it has x,y directly
        Notify(penData.x, penData.y, penData.pressure, penData.sw);
    }

private:
   void Notify(uint16_t x, uint16_t y, uint16_t p, uint16_t sw) {
        flutter::EncodableMap map;
        map[EncodableValue("x")] = EncodableValue((int64_t)x);
        map[EncodableValue("y")] = EncodableValue((int64_t)y);
        map[EncodableValue("pressure")] = EncodableValue((int64_t)p);
        map[EncodableValue("sw")] = EncodableValue((int64_t)sw);
        callback_(EncodableValue(map));
    }

    std::function<void(const EncodableValue&)> callback_;
};

// ForwardingStreamHandler to avoid double ownership
class ForwardingStreamHandler : public flutter::StreamHandler<EncodableValue> {
public:
    ForwardingStreamHandler(WacomStuPlugin* plugin) : plugin_(plugin) {}
    
    std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> OnListenInternal(
        const EncodableValue* arguments,
        std::unique_ptr<flutter::EventSink<EncodableValue>>&& events) override {
            return plugin_->OnListenInternal(arguments, std::move(events));
    }

    std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> OnCancelInternal(
        const EncodableValue* arguments) override {
            return plugin_->OnCancelInternal(arguments);
    }
private:
    WacomStuPlugin* plugin_;
};

WacomStuPlugin::WacomStuPlugin() : keepRunning(false) {}

WacomStuPlugin::~WacomStuPlugin() {
  StopReportThread();
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
      
  auto event_channel =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar->messenger(),
          "wacom_stu_events",
          &flutter::StandardMethodCodec::GetInstance());

  event_channel->SetStreamHandler(
      std::make_unique<ForwardingStreamHandler>(plugin.get()));

  registrar->AddPlugin(std::move(plugin));
}

std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> WacomStuPlugin::OnListenInternal(
    const EncodableValue* arguments,
    std::unique_ptr<flutter::EventSink<EncodableValue>>&& events) {
    
    std::lock_guard<std::mutex> lock(sinkMutex);
    eventSink = std::move(events);
    return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> WacomStuPlugin::OnCancelInternal(
    const EncodableValue* arguments) {
    
    std::lock_guard<std::mutex> lock(sinkMutex);
    eventSink = nullptr;
    return nullptr;
}

void WacomStuPlugin::StartReportThread() {
    if (keepRunning) return;
    
    // Ensure we are connected first
    if (!tablet || !tablet->isConnected()) return;

    keepRunning = true;
    reportThread = std::thread([this]() {
        // Init pen handler with callback to sink
        PenHandler penHandler([this](const EncodableValue& val) {
            std::lock_guard<std::mutex> lock(sinkMutex);
            if (eventSink) {
                eventSink->Success(val);
            }
        });

        // Create queue via tablet interface
        WacomGSS::STU::InterfaceQueue queue = tablet->interfaceQueue();

        while (keepRunning) {
            WacomGSS::STU::Report report;
            try {
                // Poll for report, returns true if report retrieved
                if (queue.try_getReport(report)) {
                     penHandler.handleReport(report.begin(), report.end(), false); 
                } else {
                    std::this_thread::sleep_for(std::chrono::milliseconds(2));
                }
            } catch (...) {
                // Ignore transient errors
            }
        }
        
        // Queue is automatically cleaned up when it goes out of scope (destructor)
        // or we can explicitly clear/disconnect if needed, but SDK handles it mostly.
    });
}

void WacomStuPlugin::StopReportThread() {
    keepRunning = false;
    if (reportThread.joinable()) {
        reportThread.join();
    }
}

void WacomStuPlugin::ClearScreen() {
    if (tablet && tablet->isConnected()) {
        tablet->setClearScreen();
    }
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
        result->Error("CONNECTION_FAILED", ec.message());
        return;
      }

      tablet = std::make_unique<wgssSTU::Tablet>();
      tablet->attach(std::move(usbInterface));
      
      // Get capability for max X/Y
      auto cap = tablet->getCapability();
      
      StartReportThread();

      flutter::EncodableMap reply;
      reply[EncodableValue("status")] = EncodableValue("Connected");
      reply[EncodableValue("maxX")] = EncodableValue((int64_t)cap.tabletMaxX);
      reply[EncodableValue("maxY")] = EncodableValue((int64_t)cap.tabletMaxY);
      reply[EncodableValue("screenWidth")] = EncodableValue((int64_t)cap.screenWidth);
      reply[EncodableValue("screenHeight")] = EncodableValue((int64_t)cap.screenHeight);

      result->Success(EncodableValue(reply));
    } catch (const std::exception& e) {
      result->Error("EXCEPTION", e.what());
    }
  }

  else if (call.method_name() == "disconnect") {
    StopReportThread();
    if (tablet) {
      tablet->disconnect();
      tablet.reset();
    }
    result->Success(EncodableValue("Disconnected"));
  }
  


  else if (call.method_name() == "clearScreen") {
    try {
        ClearScreen();
        result->Success(EncodableValue(true));
    } catch (const std::exception& e) {
        result->Error("CLEAR_FAILED", e.what());
    }
  }

  else if (call.method_name() == "setSignatureScreen") {
    try {
        const auto* map = std::get_if<flutter::EncodableMap>(call.arguments());
        if (!map) {
             result->Error("INVALID_ARGUMENTS", "Arguments must be a map");
             return;
        }

        auto data_it = map->find(EncodableValue("data"));
        auto mode_it = map->find(EncodableValue("mode"));

        if (data_it == map->end() || mode_it == map->end()) {
             result->Error("INVALID_ARGUMENTS", "Missing 'data' or 'mode'");
             return;
        }

        std::vector<uint8_t> data;
        if (std::holds_alternative<std::vector<uint8_t>>(data_it->second)) {
            data = std::get<std::vector<uint8_t>>(data_it->second);
        } else {
             result->Error("INVALID_ARGUMENTS", "'data' must be a byte array");
             return;
        }

        int mode = 0;
        if (std::holds_alternative<int>(mode_it->second)) {
             mode = std::get<int>(mode_it->second);
        } else if (std::holds_alternative<int64_t>(mode_it->second)) {
             mode = (int)std::get<int64_t>(mode_it->second);
        }

        if (tablet && tablet->isConnected()) {
             // 0=1bit, 1=1bit_Zlib, 2=16bit, 4=24bit
             // We cast int to EncodingMode
             tablet->writeImage((WacomGSS::STU::Protocol::EncodingMode)mode, data.data(), data.size());
             result->Success(EncodableValue(true));
        } else {
             result->Error("NO_DEVICE", "Tablet not connected");
        }
        
    } catch (const std::exception& e) {
        result->Error("WRITE_IMAGE_FAILED", e.what());
    }
  }

  else {
    result->NotImplemented();
  }
}
