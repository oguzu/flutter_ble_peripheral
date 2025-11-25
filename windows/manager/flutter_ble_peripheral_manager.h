#ifndef FLUTTER_PLUGIN_FLUTTER_BLE_PERIPHERAL_MANAGER_H_
#define FLUTTER_PLUGIN_FLUTTER_BLE_PERIPHERAL_MANAGER_H_

#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Storage.Streams.h>

#include <flutter/encodable_value.h>
#include <flutter/method_result.h>

#include <memory>
#include <functional>

#include "../handlers/state_changed_handler.h"
#include "../models/peripheral_state.h"

namespace flutter_ble_peripheral {
namespace manager {

    using namespace winrt;
    using namespace winrt::Windows::Foundation;
    using namespace winrt::Windows::Devices::Radios;
    using namespace winrt::Windows::Devices::Bluetooth;
    using namespace winrt::Windows::Devices::Bluetooth::Advertisement;
    using namespace winrt::Windows::Storage::Streams;

    using flutter::EncodableMap;
    using flutter::EncodableValue;
    using handlers::StateChangedHandler;
    using models::PeripheralState;
    using models::AdvertiseError;

    class FlutterBlePeripheralManager {
    public:
        explicit FlutterBlePeripheralManager(StateChangedHandler* state_handler);
        ~FlutterBlePeripheralManager();

        // Disallow copy and assign.
        FlutterBlePeripheralManager(const FlutterBlePeripheralManager&) = delete;
        FlutterBlePeripheralManager& operator=(const FlutterBlePeripheralManager&) = delete;

        // Initialize Bluetooth adapter and radio
        winrt::fire_and_forget InitializeAsync();

        // Start advertising with given parameters
        void StartAdvertising(
            const EncodableMap& arguments,
            std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

        // Stop advertising
        void StopAdvertising(
            std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

        // Check if currently advertising
        bool IsAdvertising() const;

        // Check if Bluetooth is supported
        bool IsSupported() const;

        // Check if Bluetooth is enabled
        bool IsBluetoothEnabled() const;

        // Get current peripheral state
        PeripheralState GetState() const;

    private:
        // Build BluetoothLEAdvertisement from parameters
        void BuildAdvertisement(const EncodableMap& arguments);

        // Handle advertising status changes
        void OnAdvertisingStatusChanged(
            BluetoothLEAdvertisementPublisher sender,
            BluetoothLEAdvertisementPublisherStatusChangedEventArgs args);

        // Handle radio state changes
        winrt::fire_and_forget OnRadioStateChanged(
            Radio sender,
            IInspectable args);

        // Helper to convert error to AdvertiseError enum
        AdvertiseError MapPublisherStatusToError(
            BluetoothLEAdvertisementPublisherStatus status);

        StateChangedHandler* state_handler_;
        Radio bluetooth_radio_{ nullptr };
        BluetoothLEAdvertisementPublisher bluetooth_publisher_{ nullptr };

        winrt::event_token publisher_status_token_;
        winrt::event_token radio_state_token_;

        bool is_advertising_;
        bool is_initialized_;

        std::unique_ptr<flutter::MethodResult<EncodableValue>> pending_result_;
    };

}  // namespace manager
}  // namespace flutter_ble_peripheral

#endif  // FLUTTER_PLUGIN_FLUTTER_BLE_PERIPHERAL_MANAGER_H_
