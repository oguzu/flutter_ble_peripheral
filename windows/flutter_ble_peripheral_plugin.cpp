#include "flutter_ble_peripheral_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Enumeration.h>

#include <flutter/method_channel.h>
#include <flutter/basic_message_channel.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/standard_message_codec.h>

#include <map>
#include <memory>
#include <sstream>
#include <algorithm>
#include <iomanip>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#pragma warning( push )
#pragma warning( disable : 4101)
#pragma warning( disable : 4244)

namespace flutter_ble_peripheral {

    // static
    void FlutterBlePeripheralPlugin::RegisterWithRegistrar(
        flutter::PluginRegistrarWindows* registrar) {
        auto channel =
            std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
                registrar->messenger(), "dev.steenbakker.flutter_ble_peripheral/ble_state",
                &flutter::StandardMethodCodec::GetInstance());

        auto channelState =
            std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
                registrar->messenger(), "dev.steenbakker.flutter_ble_peripheral/ble_state_changed",
                &flutter::StandardMethodCodec::GetInstance());

        auto event_scan_result =
            std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
                registrar->messenger(), "dev.steenbakker.flutter_ble_peripheral/scan_result",
                &flutter::StandardMethodCodec::GetInstance());

        auto plugin = std::make_unique<FlutterBlePeripheralPlugin>();

        channel->SetMethodCallHandler(
            [plugin_pointer = plugin.get()](const auto& call, auto result) {
                plugin_pointer->HandleMethodCall(call, std::move(result));
            });

        auto handler = std::make_unique<
            flutter::StreamHandlerFunctions<>>(
                [plugin_pointer = plugin.get()](
                    const flutter::EncodableValue* arguments,
                    std::unique_ptr<flutter::EventSink<>>&& events)
                -> std::unique_ptr<flutter::StreamHandlerError<>> {
                    return plugin_pointer->OnListen(arguments, std::move(events));
                },
                [plugin_pointer = plugin.get()](const flutter::EncodableValue* arguments)
                    -> std::unique_ptr<flutter::StreamHandlerError<>> {
                    return plugin_pointer->OnCancel(arguments);
                });
        event_scan_result->SetStreamHandler(std::move(handler));



        registrar->AddPlugin(std::move(plugin));
    }

    FlutterBlePeripheralPlugin::FlutterBlePeripheralPlugin() {
        InitializeAsync();
    }

    FlutterBlePeripheralPlugin::~FlutterBlePeripheralPlugin() {}

    winrt::fire_and_forget FlutterBlePeripheralPlugin::InitializeAsync() {
        auto bluetoothAdapter = co_await BluetoothAdapter::GetDefaultAsync();
        bluetoothRadio = co_await bluetoothAdapter.GetRadioAsync();
    }

    void FlutterBlePeripheralPlugin::HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue>& method_call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (method_call.method_name().compare("start") == 0) {
            if (!bluetoothLEPublisher) {
                bluetoothLEPublisher = BluetoothLEAdvertisementPublisher();
            }

            const auto* arguments = std::get_if<EncodableMap>(method_call.arguments());
            if (arguments) {
                // Parse core advertising data
                auto& advertisement = bluetoothLEPublisher.Advertisement();

                // Add service UUID if present
                auto serviceUuidIt = arguments->find(EncodableValue("serviceUuid"));
                if (serviceUuidIt != arguments->end()) {
                    if (auto* serviceUuidStr = std::get_if<std::string>(&serviceUuidIt->second)) {
                        try {
                            auto uuid = winrt::guid(*serviceUuidStr);
                            advertisement.ServiceUuids().Append(uuid);
                        }
                        catch (...) {
                            // Invalid UUID format
                        }
                    }
                }

                // Add multiple service UUIDs if present
                auto serviceUuidsIt = arguments->find(EncodableValue("serviceUuids"));
                if (serviceUuidsIt != arguments->end()) {
                    if (auto* uuidsList = std::get_if<flutter::EncodableList>(&serviceUuidsIt->second)) {
                        for (const auto& uuidValue : *uuidsList) {
                            if (auto* uuidStr = std::get_if<std::string>(&uuidValue)) {
                                try {
                                    auto uuid = winrt::guid(*uuidStr);
                                    advertisement.ServiceUuids().Append(uuid);
                                }
                                catch (...) {
                                    // Invalid UUID format
                                }
                            }
                        }
                    }
                }

                // Set local name if present
                auto localNameIt = arguments->find(EncodableValue("localName"));
                if (localNameIt != arguments->end()) {
                    if (auto* localName = std::get_if<std::string>(&localNameIt->second)) {
                        advertisement.LocalName(winrt::to_hstring(*localName));
                    }
                }

                // Parse Windows-specific settings (prefixed with "windows")

                // Manufacturer data
                Advertisement::BluetoothLEManufacturerData manufacturerData = Advertisement::BluetoothLEManufacturerData();
                bool hasManufacturerData = false;

                auto windowsManuDataIt = arguments->find(EncodableValue("windowsManufacturerDataBytes"));
                if (windowsManuDataIt != arguments->end()) {
                    auto dataWriter = DataWriter();
                    auto& vector = std::get<std::vector<uint8_t>>(windowsManuDataIt->second);
                    dataWriter.WriteBytes(vector);
                    manufacturerData.Data(dataWriter.DetachBuffer());
                    hasManufacturerData = true;
                }

                auto windowsManuIdIt = arguments->find(EncodableValue("windowsmanufacturerId"));
                if (windowsManuIdIt != arguments->end()) {
                    auto manuId = std::get<std::int32_t>(windowsManuIdIt->second);
                    manufacturerData.CompanyId(static_cast<uint16_t>(manuId));
                    hasManufacturerData = true;
                }

                if (hasManufacturerData) {
                    advertisement.ManufacturerData().Append(manufacturerData);
                }

                // Advertisement flags
                auto flagsIt = arguments->find(EncodableValue("windowsflags"));
                if (flagsIt != arguments->end()) {
                    if (auto* flags = std::get_if<std::int32_t>(&flagsIt->second)) {
                        auto flagsData = Advertisement::BluetoothLEAdvertisementFlags(*flags);
                        advertisement.Flags(flagsData);
                    }
                }

                // Use extended advertisement
                auto useExtendedIt = arguments->find(EncodableValue("windowsuseExtendedAdvertisement"));
                if (useExtendedIt != arguments->end()) {
                    if (auto* useExtended = std::get_if<bool>(&useExtendedIt->second)) {
                        if (*useExtended) {
                            // Enable extended advertisement format
                            bluetoothLEPublisher.UseExtendedAdvertisement(true);
                        }
                    }
                }

                // Preferred transmit power level
                auto txPowerIt = arguments->find(EncodableValue("windowspreferredTransmitPowerLevel"));
                if (txPowerIt != arguments->end()) {
                    if (auto* txPower = std::get_if<std::int32_t>(&txPowerIt->second)) {
                        auto powerLevel = static_cast<int16_t>(*txPower);
                        bluetoothLEPublisher.PreferredTransmitPowerLevelInDBm(powerLevel);
                    }
                }

                // Include TX power
                auto includeTxPowerIt = arguments->find(EncodableValue("windowsincludeTxPower"));
                if (includeTxPowerIt != arguments->end()) {
                    if (auto* includeTxPower = std::get_if<bool>(&includeTxPowerIt->second)) {
                        if (*includeTxPower) {
                            // Windows API: This is typically controlled via flags
                            // The TX power level advertisement is automatic in some scenarios
                        }
                    }
                }
            }

            bluetoothLEPublisher.Start();
            result->Success(8);
        }
        else if (method_call.method_name().compare("stop") == 0) {
            if (bluetoothLEPublisher) {
                bluetoothLEPublisher.Advertisement().ManufacturerData().Clear();
                bluetoothLEPublisher.Stop();
            }
            result->Success(8);
        } else if (method_call.method_name().compare("isAdvertising") == 0) {
            result->Success(true);
        }
        else {
            result->NotImplemented();
        }
    }

    BluetoothLEAdvertisementPublisherStatusChangedEventArgs statuss = nullptr;

    void Publisher_StatusChanged(BluetoothLEAdvertisementPublisher sender,
        BluetoothLEAdvertisementPublisherStatusChangedEventArgs args)
    {

        statuss = args;
    }

    union uint16_t_union {
        uint16_t uint16;
        byte bytes[sizeof(uint16_t)];
    };

    std::vector<uint8_t> to_bytevc(IBuffer buffer) {
        auto reader = DataReader::FromBuffer(buffer);
        auto result = std::vector<uint8_t>(reader.UnconsumedBufferLength());
        reader.ReadBytes(result);
        return result;
    }

    std::vector<uint8_t> parseManufacturerData(BluetoothLEAdvertisement advertisement) {
        if (advertisement.ManufacturerData().Size() == 0)
            return std::vector<uint8_t>();

        auto manufacturerData = advertisement.ManufacturerData().GetAt(0);
        // FIXME Compat with REG_DWORD_BIG_ENDIAN
        uint8_t* prefix = uint16_t_union{ manufacturerData.CompanyId() }.bytes;
        auto result = std::vector<uint8_t>{ prefix, prefix + sizeof(uint16_t_union) };

        auto data = to_bytevc(manufacturerData.Data());
        result.insert(result.end(), data.begin(), data.end());
        return result;
    }

    void FlutterBlePeripheralPlugin::BluetoothLEWatcher_Received(
        BluetoothLEAdvertisementWatcher sender,
        BluetoothLEAdvertisementReceivedEventArgs args) {
        //OutputDebugString((L"Received " + winrt::to_hstring(args.BluetoothAddress()) + L"\n").c_str());
        auto manufacturer_data = parseManufacturerData(args.Advertisement());
        if (scan_result_sink_) {
            auto bluetoothAddress = args.BluetoothAddress();
            auto localName = args.Advertisement().LocalName();
            auto name = winrt::to_string(localName);
            if (localName.empty()) {
                // TODO
                // auto device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(bluetoothAddress);
                // name = winrt::to_string(device.Name());

                std::stringstream sstream;
                sstream << std::hex << bluetoothAddress;
                name = sstream.str();
            }
            scan_result_sink_->Success(flutter::EncodableMap{
              {"deviceName", name},
              {"address", std::to_string(bluetoothAddress)},
              {"manufacturerSpecificData", manufacturer_data},
              {"rssi", args.RawSignalStrengthInDBm()},
              //{"serviceUuids", args.Advertisement().ServiceUuids()},
                });
        }
    }



    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> FlutterBlePeripheralPlugin::OnListenInternal(
        const flutter::EncodableValue* arguments, std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
    {
        scan_result_sink_ = std::move(events);
        return nullptr;
    }

    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> FlutterBlePeripheralPlugin::OnCancelInternal(
        const flutter::EncodableValue* arguments)
    {
        scan_result_sink_ = nullptr;
        return nullptr;
    }

}  // namespace flutter_ble_peripheral
