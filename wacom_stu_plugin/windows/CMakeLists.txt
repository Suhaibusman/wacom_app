cmake_minimum_required(VERSION 3.14)
project(wacom_stu_plugin LANGUAGES CXX)

set(WACOM_SDK_DIR "C:/Program Files (x86)/Wacom STU SDK/cpp")
set(WACOM_C_SDK_DIR "C:/Program Files (x86)/Wacom STU SDK/C")

add_library(wacom_stu_plugin_plugin SHARED
  "wacom_stu_plugin.cpp"
  "wacom_stu_plugin_c_api.cpp"
)

apply_standard_settings(wacom_stu_plugin_plugin)

target_compile_definitions(wacom_stu_plugin_plugin PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(wacom_stu_plugin_plugin PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${WACOM_SDK_DIR}/include"
)

# Add SDK source files
target_sources(wacom_stu_plugin_plugin PRIVATE
  "${WACOM_SDK_DIR}/src/STU/cpp/Tablet.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/Protocol.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/ProtocolHelper.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/Interface.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/InterfaceImpl.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/InterfaceQueue.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/ReportHandler.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/getUsbDevices.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/Win32/UsbInterface.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/Win32/getUsbDevices_Win32.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/Win32/ProtocolHelper_Win32_WIC.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/error_win32api.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/winusb.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/wstringConvert.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/error_NTSTATUS.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/error_HRESULT.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/error_CONFIGRET.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/getDevicePowerState.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/com.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/dliHook.cpp"
  "${WACOM_SDK_DIR}/src/utility/cpp/Win32/setThreadName.cpp"
  "${WACOM_SDK_DIR}/src/utility/cpp/Win32/enumUsbDevices.cpp"
  "${WACOM_SDK_DIR}/src/utility/cpp/Win32/enumDevices.cpp"
)

target_link_directories(wacom_stu_plugin_plugin PRIVATE
  "${WACOM_C_SDK_DIR}/lib/x64"
)

target_link_libraries(wacom_stu_plugin_plugin PRIVATE
  flutter
  flutter_wrapper_plugin
  setupapi
  winusb
  shlwapi
  windowscodecs
  ole32
  oleaut32
  user32
  gdi32
)

target_compile_options(wacom_stu_plugin_plugin PRIVATE /wd4267 /wd4244 /wd4834)

set_target_properties(wacom_stu_plugin_plugin PROPERTIES
  CXX_STANDARD 17
)

set(wacom_stu_plugin_bundled_libraries
  ""
)
