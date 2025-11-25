#ifndef FLUTTER_PLUGIN_FLUTTER_BLE_PERIPHERAL_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_BLE_PERIPHERAL_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

#include "handlers/state_changed_handler.h"
#include "manager/flutter_ble_peripheral_manager.h"

namespace flutter_ble_peripheral {

    using flutter::EncodableMap;
    using flutter::EncodableValue;

    class FlutterBlePeripheralPlugin : public flutter::Plugin {
    public:
        static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

        FlutterBlePeripheralPlugin();

        virtual ~FlutterBlePeripheralPlugin();

        // Disallow copy and assign.
        FlutterBlePeripheralPlugin(const FlutterBlePeripheralPlugin&) = delete;
        FlutterBlePeripheralPlugin& operator=(const FlutterBlePeripheralPlugin&) = delete;

        // Called when a method is called on this plugin's channel from Dart.
        void HandleMethodCall(
            const flutter::MethodCall<flutter::EncodableValue>& method_call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    private:
        std::unique_ptr<handlers::StateChangedHandler> state_changed_handler_;
        std::unique_ptr<manager::FlutterBlePeripheralManager> peripheral_manager_;
    };

}  // namespace flutter_ble_peripheral

#endif  // FLUTTER_PLUGIN_FLUTTER_BLE_PERIPHERAL_PLUGIN_H_
