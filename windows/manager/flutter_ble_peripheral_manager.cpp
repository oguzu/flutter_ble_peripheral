#include "flutter_ble_peripheral_manager.h"

#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.Collections.h>

#include <sstream>
#include <iomanip>

namespace flutter_ble_peripheral {
namespace manager {

    using namespace winrt::Windows::Foundation::Collections;

    FlutterBlePeripheralManager::FlutterBlePeripheralManager(StateChangedHandler* state_handler)
        : state_handler_(state_handler),
        is_advertising_(false),
        is_initialized_(false) {
        InitializeAsync();
    }

    FlutterBlePeripheralManager::~FlutterBlePeripheralManager() {
        if (bluetooth_publisher_) {
            if (is_advertising_) {
                bluetooth_publisher_.Stop();
            }
            if (publisher_status_token_) {
                bluetooth_publisher_.StatusChanged(publisher_status_token_);
            }
        }
        if (bluetooth_radio_ && radio_state_token_) {
            bluetooth_radio_.StateChanged(radio_state_token_);
        }
    }

    winrt::fire_and_forget FlutterBlePeripheralManager::InitializeAsync() {
        try {
            auto bluetooth_adapter = co_await BluetoothAdapter::GetDefaultAsync();
            if (bluetooth_adapter) {
                bluetooth_radio_ = co_await bluetooth_adapter.GetRadioAsync();

                if (bluetooth_radio_) {
                    // Set up radio state change handler
                    radio_state_token_ = bluetooth_radio_.StateChanged(
                        { this, &FlutterBlePeripheralManager::OnRadioStateChanged });

                    // Publish initial state based on radio state
                    if (bluetooth_radio_.State() == RadioState::On) {
                        state_handler_->PublishPeripheralState(PeripheralState::Idle);
                    }
                    else if (bluetooth_radio_.State() == RadioState::Off) {
                        state_handler_->PublishPeripheralState(PeripheralState::PoweredOff);
                    }
                    else {
                        state_handler_->PublishPeripheralState(PeripheralState::Unknown);
                    }
                }
                else {
                    state_handler_->PublishPeripheralState(PeripheralState::Unsupported);
                }
            }
            else {
                state_handler_->PublishPeripheralState(PeripheralState::Unsupported);
            }
            is_initialized_ = true;
        }
        catch (...) {
            state_handler_->PublishPeripheralState(PeripheralState::Unsupported);
            is_initialized_ = false;
        }
    }

    void FlutterBlePeripheralManager::StartAdvertising(
        const EncodableMap& arguments,
        std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {

        // Check if Bluetooth is available and enabled
        if (!bluetooth_radio_ || bluetooth_radio_.State() != RadioState::On) {
            result->Error("BLUETOOTH_OFF", "Bluetooth is not enabled", EncodableValue());
            return;
        }

        // Check if already advertising
        if (is_advertising_) {
            state_handler_->PublishPeripheralState(PeripheralState::Advertising);
            result->Success(EncodableValue());
            return;
        }

        // Create new publisher if needed
        if (!bluetooth_publisher_) {
            bluetooth_publisher_ = BluetoothLEAdvertisementPublisher();

            // Set up status changed handler
            publisher_status_token_ = bluetooth_publisher_.StatusChanged(
                { this, &FlutterBlePeripheralManager::OnAdvertisingStatusChanged });
        }

        // Build advertisement from arguments
        BuildAdvertisement(arguments);

        // Store result for callback
        pending_result_ = std::move(result);

        // Start advertising
        try {
            bluetooth_publisher_.Start();
        }
        catch (const winrt::hresult_error& ex) {
            is_advertising_ = false;
            state_handler_->PublishPeripheralState(PeripheralState::Idle);
            pending_result_->Error(
                "START_FAILED",
                winrt::to_string(ex.message()),
                EncodableValue());
            pending_result_ = nullptr;
        }
    }

    void FlutterBlePeripheralManager::StopAdvertising(
        std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {

        if (bluetooth_publisher_ && is_advertising_) {
            bluetooth_publisher_.Stop();
            is_advertising_ = false;
        }

        state_handler_->PublishPeripheralState(PeripheralState::Idle);
        result->Success(EncodableValue(static_cast<int>(PeripheralState::Idle)));
    }

    void FlutterBlePeripheralManager::BuildAdvertisement(const EncodableMap& arguments) {
        auto advertisement = bluetooth_publisher_.Advertisement();
        advertisement.ManufacturerData().Clear();
        advertisement.ServiceUuids().Clear();
        advertisement.DataSections().Clear();

        // Local Name
        auto local_name_it = arguments.find(EncodableValue("localName"));
        if (local_name_it != arguments.end() && !local_name_it->second.IsNull()) {
            auto local_name = std::get<std::string>(local_name_it->second);
            advertisement.LocalName(winrt::to_hstring(local_name));
        }

        // Manufacturer Data
        auto manu_data_it = arguments.find(EncodableValue("manufacturerData"));
        auto manu_id_it = arguments.find(EncodableValue("manufacturerId"));
        if (manu_data_it != arguments.end() && manu_id_it != arguments.end()) {
            Advertisement::BluetoothLEManufacturerData manufacturer_data;

            // Set company ID
            auto company_id = std::get<int32_t>(manu_id_it->second);
            manufacturer_data.CompanyId(static_cast<uint16_t>(company_id));

            // Set data - convert EncodableList to std::vector<uint8_t>
            auto data_list = std::get<flutter::EncodableList>(manu_data_it->second);
            std::vector<uint8_t> data_vector;
            data_vector.reserve(data_list.size());
            for (const auto& byte_value : data_list) {
                data_vector.push_back(static_cast<uint8_t>(std::get<int32_t>(byte_value)));
            }
            DataWriter data_writer;
            data_writer.WriteBytes(data_vector);
            manufacturer_data.Data(data_writer.DetachBuffer());

            advertisement.ManufacturerData().Append(manufacturer_data);
        }

        // Service UUID (single)
        auto service_uuid_it = arguments.find(EncodableValue("serviceUuid"));
        if (service_uuid_it != arguments.end() && !service_uuid_it->second.IsNull()) {
            auto uuid_string = std::get<std::string>(service_uuid_it->second);
            try {
                auto uuid = winrt::guid(winrt::to_hstring(uuid_string));
                advertisement.ServiceUuids().Append(uuid);
            }
            catch (...) {
                // Invalid UUID, skip
            }
        }

        // Service UUIDs (multiple)
        auto service_uuids_it = arguments.find(EncodableValue("serviceUuids"));
        if (service_uuids_it != arguments.end() && !service_uuids_it->second.IsNull()) {
            auto uuids = std::get<flutter::EncodableList>(service_uuids_it->second);
            for (const auto& uuid_value : uuids) {
                auto uuid_string = std::get<std::string>(uuid_value);
                try {
                    auto uuid = winrt::guid(winrt::to_hstring(uuid_string));
                    advertisement.ServiceUuids().Append(uuid);
                }
                catch (...) {
                    // Invalid UUID, skip
                }
            }
        }

        // Service Data
        auto service_data_it = arguments.find(EncodableValue("serviceData"));
        auto service_data_uuid_it = arguments.find(EncodableValue("serviceDataUuid"));
        if (service_data_it != arguments.end() && service_data_uuid_it != arguments.end()) {
            // Convert EncodableList to std::vector<uint8_t>
            auto data_list = std::get<flutter::EncodableList>(service_data_it->second);
            std::vector<uint8_t> data_vector;
            data_vector.reserve(data_list.size());
            for (const auto& byte_value : data_list) {
                data_vector.push_back(static_cast<uint8_t>(std::get<int32_t>(byte_value)));
            }
            auto uuid_string = std::get<std::string>(service_data_uuid_it->second);

            try {
                auto uuid = winrt::guid(winrt::to_hstring(uuid_string));
                DataWriter data_writer;
                data_writer.WriteBytes(data_vector);

                BluetoothLEAdvertisementDataSection data_section(
                    0x16,  // Service Data - 16-bit UUID
                    data_writer.DetachBuffer()
                );
                advertisement.DataSections().Append(data_section);
            }
            catch (...) {
                // Invalid data or UUID, skip
            }
        }

        // Include Device Name flag
        auto include_name_it = arguments.find(EncodableValue("includeDeviceName"));
        if (include_name_it != arguments.end() && !include_name_it->second.IsNull()) {
            auto include_name = std::get<bool>(include_name_it->second);
            if (!include_name) {
                // Clear local name if includeDeviceName is false
                advertisement.LocalName(L"");
            }
        }

        // Flags
        auto flags_it = arguments.find(EncodableValue("flags"));
        if (flags_it != arguments.end() && !flags_it->second.IsNull()) {
            auto flags = std::get<int32_t>(flags_it->second);
            advertisement.Flags(static_cast<BluetoothLEAdvertisementFlags>(flags));
        }
    }

    void FlutterBlePeripheralManager::OnAdvertisingStatusChanged(
        BluetoothLEAdvertisementPublisher sender,
        BluetoothLEAdvertisementPublisherStatusChangedEventArgs args) {

        auto status = args.Status();
        auto error = args.Error();

        switch (status) {
        case BluetoothLEAdvertisementPublisherStatus::Started:
            is_advertising_ = true;
            state_handler_->PublishPeripheralState(PeripheralState::Advertising);
            if (pending_result_) {
                pending_result_->Success(EncodableValue());
                pending_result_ = nullptr;
            }
            break;

        case BluetoothLEAdvertisementPublisherStatus::Stopped:
            is_advertising_ = false;
            state_handler_->PublishPeripheralState(PeripheralState::Idle);
            break;

        case BluetoothLEAdvertisementPublisherStatus::Aborted:
            is_advertising_ = false;
            state_handler_->PublishPeripheralState(PeripheralState::Idle);

            if (pending_result_) {
                std::string error_message;
                std::string error_code;

                switch (error) {
                case BluetoothError::RadioNotAvailable:
                    error_code = "RADIO_NOT_AVAILABLE";
                    error_message = "Bluetooth radio is not available";
                    state_handler_->PublishPeripheralState(PeripheralState::PoweredOff);
                    break;
                case BluetoothError::ResourceInUse:
                    error_code = "RESOURCE_IN_USE";
                    error_message = "Bluetooth resource is already in use";
                    break;
                case BluetoothError::NotSupported:
                    error_code = "NOT_SUPPORTED";
                    error_message = "Advertising is not supported on this device";
                    state_handler_->PublishPeripheralState(PeripheralState::Unsupported);
                    break;
                case BluetoothError::DisabledByPolicy:
                    error_code = "DISABLED_BY_POLICY";
                    error_message = "Bluetooth is disabled by policy";
                    state_handler_->PublishPeripheralState(PeripheralState::Unauthorized);
                    break;
                case BluetoothError::DisabledByUser:
                    error_code = "DISABLED_BY_USER";
                    error_message = "Bluetooth is disabled by user";
                    state_handler_->PublishPeripheralState(PeripheralState::PoweredOff);
                    break;
                default:
                    error_code = "UNKNOWN_ERROR";
                    error_message = "Advertising failed with unknown error";
                    break;
                }

                pending_result_->Error(error_code, error_message, EncodableValue());
                pending_result_ = nullptr;
            }
            break;

        case BluetoothLEAdvertisementPublisherStatus::Waiting:
            // Waiting for resources, keep advertising flag
            break;

        default:
            break;
        }
    }

    winrt::fire_and_forget FlutterBlePeripheralManager::OnRadioStateChanged(
        Radio sender,
        IInspectable args) {

        auto radio_state = sender.State();

        switch (radio_state) {
        case RadioState::On:
            if (!is_advertising_) {
                state_handler_->PublishPeripheralState(PeripheralState::Idle);
            }
            break;
        case RadioState::Off:
            if (is_advertising_ && bluetooth_publisher_) {
                bluetooth_publisher_.Stop();
                is_advertising_ = false;
            }
            state_handler_->PublishPeripheralState(PeripheralState::PoweredOff);
            break;
        case RadioState::Disabled:
            if (is_advertising_ && bluetooth_publisher_) {
                bluetooth_publisher_.Stop();
                is_advertising_ = false;
            }
            state_handler_->PublishPeripheralState(PeripheralState::Unauthorized);
            break;
        default:
            state_handler_->PublishPeripheralState(PeripheralState::Unknown);
            break;
        }

        co_return;
    }

    bool FlutterBlePeripheralManager::IsAdvertising() const {
        return is_advertising_;
    }

    bool FlutterBlePeripheralManager::IsSupported() const {
        return bluetooth_radio_ != nullptr;
    }

    bool FlutterBlePeripheralManager::IsBluetoothEnabled() const {
        return bluetooth_radio_ && bluetooth_radio_.State() == RadioState::On;
    }

    PeripheralState FlutterBlePeripheralManager::GetState() const {
        return state_handler_->GetState();
    }

    AdvertiseError FlutterBlePeripheralManager::MapPublisherStatusToError(
        BluetoothLEAdvertisementPublisherStatus status) {

        switch (status) {
        case BluetoothLEAdvertisementPublisherStatus::Started:
            return AdvertiseError::Success;
        case BluetoothLEAdvertisementPublisherStatus::Aborted:
            return AdvertiseError::InternalError;
        default:
            return AdvertiseError::Unknown;
        }
    }

}  // namespace manager
}  // namespace flutter_ble_peripheral
