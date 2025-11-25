#include "flutter_ble_peripheral_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace flutter_ble_peripheral {

    // static
    void FlutterBlePeripheralPlugin::RegisterWithRegistrar(
        flutter::PluginRegistrarWindows* registrar) {

        auto plugin = std::make_unique<FlutterBlePeripheralPlugin>();

        // Method channel for BLE operations
        auto method_channel =
            std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
                registrar->messenger(),
                "dev.steenbakker.flutter_ble_peripheral/ble_state",
                &flutter::StandardMethodCodec::GetInstance());

        method_channel->SetMethodCallHandler(
            [plugin_pointer = plugin.get()](const auto& call, auto result) {
                plugin_pointer->HandleMethodCall(call, std::move(result));
            });

        // Event channel for state changes
        auto state_event_channel =
            std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
                registrar->messenger(),
                "dev.steenbakker.flutter_ble_peripheral/ble_state_changed",
                &flutter::StandardMethodCodec::GetInstance());

        auto state_handler = std::make_unique<
            flutter::StreamHandlerFunctions<>>(
                [plugin_pointer = plugin.get()](
                    const flutter::EncodableValue* arguments,
                    std::unique_ptr<flutter::EventSink<>>&& events)
                -> std::unique_ptr<flutter::StreamHandlerError<>> {
                    return plugin_pointer->state_changed_handler_->OnListen(
                        arguments, std::move(events));
                },
                [plugin_pointer = plugin.get()](const flutter::EncodableValue* arguments)
                -> std::unique_ptr<flutter::StreamHandlerError<>> {
                    return plugin_pointer->state_changed_handler_->OnCancel(arguments);
                });

        state_event_channel->SetStreamHandler(std::move(state_handler));

        registrar->AddPlugin(std::move(plugin));
    }

    FlutterBlePeripheralPlugin::FlutterBlePeripheralPlugin() {
        state_changed_handler_ = std::make_unique<handlers::StateChangedHandler>();
        peripheral_manager_ = std::make_unique<manager::FlutterBlePeripheralManager>(
            state_changed_handler_.get());
    }

    FlutterBlePeripheralPlugin::~FlutterBlePeripheralPlugin() {}

    void FlutterBlePeripheralPlugin::HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue>& method_call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

        const std::string& method = method_call.method_name();

        if (method == "start") {
            const auto* arguments = std::get_if<EncodableMap>(method_call.arguments());
            if (arguments) {
                peripheral_manager_->StartAdvertising(*arguments, std::move(result));
            } else {
                result->Error("INVALID_ARGUMENTS", "Arguments must be a map", EncodableValue());
            }
        }
        else if (method == "stop") {
            peripheral_manager_->StopAdvertising(std::move(result));
        }
        else if (method == "isAdvertising") {
            bool is_advertising = peripheral_manager_->IsAdvertising();
            result->Success(EncodableValue(is_advertising));
        }
        else if (method == "isSupported") {
            bool is_supported = peripheral_manager_->IsSupported();
            result->Success(EncodableValue(is_supported));
        }
        else if (method == "isConnected") {
            // TODO: Implement GATT server connection tracking
            result->Success(EncodableValue(false));
        }
        else if (method == "enableBluetooth") {
            // Windows doesn't allow programmatic Bluetooth enabling
            // Return current state instead
            bool is_enabled = peripheral_manager_->IsBluetoothEnabled();
            result->Success(EncodableValue(is_enabled));
        }
        else if (method == "requestPermission") {
            // Windows handles permissions differently
            // Return supported state if Bluetooth is available
            auto state = peripheral_manager_->IsSupported() ?
                static_cast<int>(models::PeripheralState::Idle) :
                static_cast<int>(models::PeripheralState::Unsupported);
            result->Success(EncodableValue(state));
        }
        else if (method == "hasPermission") {
            // Windows handles permissions differently
            // Return supported state if Bluetooth is available
            auto state = peripheral_manager_->IsSupported() ?
                static_cast<int>(models::PeripheralState::Idle) :
                static_cast<int>(models::PeripheralState::Unsupported);
            result->Success(EncodableValue(state));
        }
        else if (method == "openBluetoothSettings") {
            // Open Windows Bluetooth settings
            ShellExecute(
                NULL,
                L"open",
                L"ms-settings:bluetooth",
                NULL,
                NULL,
                SW_SHOWNORMAL
            );
            result->Success(EncodableValue());
        }
        else if (method == "openAppSettings") {
            // Open Windows Settings app
            ShellExecute(
                NULL,
                L"open",
                L"ms-settings:",
                NULL,
                NULL,
                SW_SHOWNORMAL
            );
            result->Success(EncodableValue());
        }
        else {
            result->NotImplemented();
        }
    }

}  // namespace flutter_ble_peripheral
