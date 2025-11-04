#if os(iOS)
import Flutter
import UIKit
#else
import FlutterMacOS
import AppKit
#endif
import CoreLocation
import CoreBluetooth

/**
 The `FlutterBlePeripheralPlugin` class is the main entry point for the
 Flutter BLE Peripheral plugin on iOS and macOS.

 **Responsibilities:**
 - Registers the plugin with the Flutter engine.
 - Handles method channel calls from the Flutter side.
 - Delegates BLE advertising and GATT server operations to [FlutterBlePeripheralManager].
 - Manages peripheral state, MTU changes, and data transfer events.
 - Handles permission and capability checks.
 - Opens system Bluetooth settings when requested.

 This class mirrors the structure of the Android peripheral plugin,
 ensuring consistent API behavior across platforms.
 */
public class FlutterBlePeripheralPlugin: NSObject, FlutterPlugin {

    /// The BLE peripheral manager responsible for advertising and data transfer.
    private let flutterBlePeripheralManager: FlutterBlePeripheralManager

    /// Handler that publishes peripheral state changes (e.g., idle, advertising, connected) to Flutter event channels.
    private let stateChangedHandler: StateChangedHandler

    /// Handler that publishes MTU (Maximum Transmission Unit) changes to Flutter event channels.
    private let mtuChangedHandler: MtuChangedHandler

    /// Handler that publishes received GATT data from central devices to Flutter event channels.
    private let dataReceivedHandler: DataReceivedHandler

    /**
     Initializes the plugin with state, MTU, and data handlers.

     - Parameters:
       - stateChangedHandler: Handles and publishes peripheral state updates.
       - mtuChangedHandler: Handles and publishes MTU change events.
       - dataReceivedHandler: Handles and publishes data received from connected devices.
     */
    init(
        stateChangedHandler: StateChangedHandler,
        mtuChangedHandler: MtuChangedHandler,
        dataReceivedHandler: DataReceivedHandler
    ) {
        self.stateChangedHandler = stateChangedHandler
        self.mtuChangedHandler = mtuChangedHandler
        self.dataReceivedHandler = dataReceivedHandler
        self.flutterBlePeripheralManager = FlutterBlePeripheralManager(
            stateChangedHandler: stateChangedHandler,
            dataReceivedHandler: dataReceivedHandler,
            mtuChangedHandler: mtuChangedHandler
        )
        super.init()
    }

    /**
     Registers the plugin with the Flutter engine.

     This sets up the method channel and associates the plugin instance
     with incoming Flutter method calls.
     */
    public static func register(with registrar: FlutterPluginRegistrar) {
        let stateChangedHandler = StateChangedHandler(registrar: registrar)
        let mtuChangedHandler = MtuChangedHandler(registrar: registrar)
        let dataReceivedHandler = DataReceivedHandler(registrar: registrar)

        let instance = FlutterBlePeripheralPlugin(
            stateChangedHandler: stateChangedHandler,
            mtuChangedHandler: mtuChangedHandler,
            dataReceivedHandler: dataReceivedHandler
        )

#if os(iOS)
        let messenger = registrar.messenger()
#else
        let messenger = registrar.messenger
#endif

        let methodChannel = FlutterMethodChannel(
            name: "dev.steenbakker.flutter_ble_peripheral/ble_state",
            binaryMessenger: messenger
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
    }
    
    /**
     Handles incoming method calls from Flutter.

     Supported methods:
     - `"start"` → Start BLE advertising as a peripheral.
     - `"stop"` → Stop BLE advertising and reset state.
     - `"isAdvertising"` → Returns whether the device is currently advertising.
     - `"isSupported"` → Checks whether BLE peripheral mode is supported on the device.
     - `"isConnected"` → Returns whether a central device is connected.
     - `"openBluetoothSettings"` → Opens system Bluetooth settings.
     - `"sendData"` → Sends data to connected central devices over GATT.
     */
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            startPeripheral(call, result)
        case "stop":
            stopPeripheral(result)
        case "openAppSettings", "openBluetoothSettings":
#if os(iOS)
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
#else
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
#endif
            result(nil)
        case "hasPermission", "requestPermission":
            result(flutterBlePeripheralManager.permissionState.rawValue)
        case "isAdvertising":
            result(stateChangedHandler.state == FlutterBlePeripheralState.advertising)
        case "isSupported":
            isSupported(result)
        case "isConnected":
            result(stateChangedHandler.state == FlutterBlePeripheralState.connected)
        case "sendData":
            sendData(call, result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    /**
     Starts BLE advertising as a peripheral.

     Initializes the peripheral with advertising data provided from Flutter,
     such as the local name and service UUIDs.

     - Parameters:
       - call: The method call containing advertising configuration.
       - result: The Flutter result callback used to send back operation state.
     */
    private func startPeripheral(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        // Check combined state (permissions + Bluetooth adapter state)
        let state = flutterBlePeripheralManager.getCombinedState()

        // Only start peripheral if Bluetooth is ready
        if state == .Ready || state == .Granted {
            let map = call.arguments as? [String: Any]

            // Parse core advertising data
            let advertiseData = FlutterBlePeripheralData(
                uuid: map?["serviceUuid"] as? String,
                localName: map?["localName"] as? String,
                uuids: map?["serviceUuids"] as? [String]
            )

            // Build advertisement data dictionary
            var advertisementData: [String: Any] = [:]

            // Add service UUIDs
            if let uuids = advertiseData.uuids {
                advertisementData[CBAdvertisementDataServiceUUIDsKey] = uuids.map { CBUUID(string: $0) }
            } else if let uuid = advertiseData.uuid {
                advertisementData[CBAdvertisementDataServiceUUIDsKey] = [CBUUID(string: uuid)]
            }

            // Add local name
            if let localName = advertiseData.localName {
                advertisementData[CBAdvertisementDataLocalNameKey] = localName
            }

            // Parse Darwin-specific settings (prefixed with "darwin")

            // Manufacturer data
//            if let manufacturerData = map?["darwinManufacturerDataBytes"] as? FlutterStandardTypedData {
//                advertisementData[CBAdvertisementDataManufacturerDataKey] = manufacturerData.data
//            }

            // Service data (dictionary of UUID -> Data)
//            if let serviceDataMap = map?["darwinServiceDataMap"] as? [String: Any] {
//                var cbServiceData: [CBUUID: Data] = [:]
//                for (uuidString, dataValue) in serviceDataMap {
//                    if let data = dataValue as? FlutterStandardTypedData {
//                        cbServiceData[CBUUID(string: uuidString)] = data.data
//                    }
//                }
//                if !cbServiceData.isEmpty {
//                    advertisementData[CBAdvertisementDataServiceDataKey] = cbServiceData
//                }
//            }

            // Overflow service UUIDs
            if let overflowUuids = map?["darwinoverflowServiceUuids"] as? [String] {
                advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] = overflowUuids.map { CBUUID(string: $0) }
            }

            // Solicited service UUIDs
            if let solicitedUuids = map?["darwinsolicitedServiceUuids"] as? [String] {
                advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] = solicitedUuids.map { CBUUID(string: $0) }
            }

            // Is connectable
//            if let isConnectable = map?["darwinisConnectable"] as? Bool {
//                advertisementData[CBAdvertisementDataIsConnectable] = NSNumber(value: isConnectable)
//            }

            print("[flutter_ble_peripheral] Starting advertising with data: \(advertisementData)")

            flutterBlePeripheralManager.startWithAdvertisementData(advertisementData: advertisementData)
            result(nil)
        } else {
            // Return the error state (TurnedOff, Denied, Unsupported, etc.)
            result(state.rawValue)
        }
    }
    
    /**
     Stops BLE advertising and resets the peripheral state to `idle`.

     - Parameter result: The Flutter result callback used to send back operation state.
     */
    private func stopPeripheral(_ result: @escaping FlutterResult) {
        flutterBlePeripheralManager.stop()
        stateChangedHandler.publishPeripheralState(state: FlutterBlePeripheralState.idle)
        result(nil)
    }
    
    /**
     Checks whether BLE peripheral mode is supported on the current device.

     On iOS, this is determined by verifying that iBeacon region monitoring
     is available, as it depends on BLE advertising support.

     - Parameter result: Returns `true` if supported, otherwise `false`.
     */
    private func isSupported(_ result: @escaping FlutterResult) {
        if CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self) {
            result(true)
        } else {
            result(false)
        }
    }

    /**
     Sends binary data to connected central devices over GATT.

     Validates the input data and passes it to the peripheral manager for transmission.
     If no devices are connected or the GATT server is uninitialized, an error is returned.

     - Parameters:
       - call: The method call containing a byte array to send.
       - result: The Flutter result callback used to return success or error state.
     */
    private func sendData(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let flutterData = call.arguments as? FlutterStandardTypedData else {
            print("[flutter_ble_peripheral] Send data error: arguments is not FlutterStandardTypedData")
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Data must be a byte array",
                details: nil
            ))
            return
        }

        print("[flutter_ble_peripheral] Trying to send \(flutterData.data.count) bytes")
        let success = flutterBlePeripheralManager.sendData(data: flutterData.data)

        if success {
            print("[flutter_ble_peripheral] Data sent successfully")
            result(nil)
        } else {
            print("[flutter_ble_peripheral] Failed to send data")
            result(FlutterError(
                code: "SEND_FAILED",
                message: "Failed to send data. GATT server may not be initialized or no devices connected",
                details: nil
            ))
        }
    }
}
