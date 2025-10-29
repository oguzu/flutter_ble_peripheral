export 'src/flutter_ble_peripheral.dart';

// Core models (cross-platform)
export 'src/core/enums/flutter_ble_bluetooth_state.dart';
export 'src/core/models/advertise_data_core.dart';

// Legacy (deprecated, use platform-specific models instead)
export 'src/core/models/advertise_data.dart';

// Android platform
export 'src/platform/android/enums/advertise_mode.dart';
export 'src/platform/android/enums/flutter_ble_peripheral_state.dart';
export 'src/platform/android/models/advertise_set_parameters.dart';
export 'src/platform/android/models/advertise_settings.dart'; // Legacy
export 'src/platform/android/models/advertise_tx_power.dart';
export 'src/platform/android/models/android_advertise_data.dart';
export 'src/platform/android/models/android_advertise_settings.dart'; // New unified settings
export 'src/platform/android/models/constants.dart';
export 'src/platform/android/models/periodic_advertise_settings.dart';

// Darwin (iOS/macOS) platform
export 'src/platform/darwin/models/darwin_advertise_settings.dart';

// Windows platform
export 'src/platform/windows/models/windows_advertise_settings.dart';
