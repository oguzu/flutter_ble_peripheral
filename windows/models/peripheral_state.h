#ifndef FLUTTER_PLUGIN_PERIPHERAL_STATE_H_
#define FLUTTER_PLUGIN_PERIPHERAL_STATE_H_

namespace flutter_ble_peripheral {
namespace models {

    // Peripheral state enum matching the Dart/Kotlin/Swift implementations
    enum class PeripheralState {
        Idle = 0,
        Advertising = 1,
        Connected = 2,
        PoweredOff = 3,
        Unsupported = 4,
        Unauthorized = 5,
        Unknown = 6
    };

    // Advertising error codes matching Android implementation
    enum class AdvertiseError {
        Success = 0,
        AlreadyStarted = 1,
        FeatureUnsupported = 2,
        InternalError = 3,
        TooManyAdvertisers = 4,
        DataTooLarge = 5,
        Unknown = 99
    };

}  // namespace models
}  // namespace flutter_ble_peripheral

#endif  // FLUTTER_PLUGIN_PERIPHERAL_STATE_H_
