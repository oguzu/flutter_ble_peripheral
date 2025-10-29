//
//  FlutterBlePeripheralManager.swift
//  flutter_ble_peripheral
//
//  Created by Julian Steenbakker on 28/03/2022.
//

import Foundation
import CoreBluetooth
import CoreLocation

/**
 The `FlutterBlePeripheralManager` class manages BLE peripheral functionality
 for the Flutter BLE Peripheral plugin on iOS and macOS.

 **Responsibilities:**
 - Manages the CoreBluetooth `CBPeripheralManager` lifecycle.
 - Handles BLE advertising (start/stop).
 - Sets up and manages GATT services and characteristics (TX/RX).
 - Tracks central device connections and subscriptions.
 - Sends and receives data between peripheral and connected centrals.
 - Reports Bluetooth state, permission state, and MTU changes to Flutter via handlers.

 This class mirrors the Android-side `BlePeripheralManager` and provides a consistent API
 surface for the Flutter plugin across platforms.
 */
class FlutterBlePeripheralManager: NSObject {

    // MARK: - Handlers

    /// Handler that publishes peripheral state changes (e.g., idle, advertising, connected) to Flutter event channels.
    let stateChangedHandler: StateChangedHandler

    /// Handler that publishes data received from connected central devices to Flutter event channels.
    let dataReceivedHandler: DataReceivedHandler?

    /// Handler that publishes MTU (Maximum Transmission Unit) updates to Flutter event channels.
    let mtuChangedHandler: MtuChangedHandler?

    // MARK: - Core Bluetooth

    /// The CoreBluetooth peripheral manager instance responsible for advertising and GATT management.
    var peripheralManager: CBPeripheralManager!

    // MARK: - GATT Attributes

    /// The currently active GATT service.
    var currentService: CBMutableService?

    /// The transmit (TX) characteristic for sending data to centrals.
    var txCharacteristic: CBMutableCharacteristic?

    /// The receive (RX) characteristic for receiving data from centrals.
    var rxCharacteristic: CBMutableCharacteristic?

    // MARK: - Connection Tracking

    /// Set of UUIDs representing centrals subscribed to the TX characteristic.
    var txSubscriptions = Set<UUID>()

    /// Set of UUIDs representing currently connected centrals.
    var connectedCentrals = Set<UUID>()

    // MARK: - MTU Tracking

    /// The current MTU (Maximum Transmission Unit) size.
    /// Default is 158 (minimum supported before iOS 10).
    var mtu: Int = 158 {
        didSet {
            mtuChangedHandler?.publishMtu(mtu: mtu)
        }
    }

    /// Indicates whether any central has subscribed to TX notifications.
    /// Updates the published peripheral state accordingly.
    var txSubscribed = false {
        didSet {
            if txSubscribed {
                stateChangedHandler.publishPeripheralState(state: .connected)
            } else if peripheralManager.isAdvertising {
                stateChangedHandler.publishPeripheralState(state: .advertising)
            }
        }
    }

    // MARK: - Initialization

    /**
     Initializes the BLE Peripheral Manager.

     - Parameters:
       - stateChangedHandler: Handler that publishes state changes to Flutter.
       - dataReceivedHandler: Handler that publishes received data to Flutter.
       - mtuChangedHandler: Handler that publishes MTU change events to Flutter.
     */
    init(
        stateChangedHandler: StateChangedHandler,
        dataReceivedHandler: DataReceivedHandler?,
        mtuChangedHandler: MtuChangedHandler?
    ) {
        self.stateChangedHandler = stateChangedHandler
        self.dataReceivedHandler = dataReceivedHandler
        self.mtuChangedHandler = mtuChangedHandler
        super.init()

        self.peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: nil,
            options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
        )
    }

    // MARK: - Advertising

    /**
     Starts BLE advertising as a peripheral.

     This method can optionally add a GATT service to the peripheral manager
     and advertise it to nearby devices.

     - Parameters:
       - advertiseData: The advertising payload including UUIDs and local name.
       - addGattService: Whether to automatically add a GATT service (default: `false`).
     */
    func start(advertiseData: FlutterBlePeripheralData, addGattService: Bool = false) {
        var dataToBeAdvertised: [String: Any] = [:]

        // Add advertised UUIDs
        if let uuids = advertiseData.uuids {
            dataToBeAdvertised[CBAdvertisementDataServiceUUIDsKey] = uuids.map { CBUUID(string: $0) }
        } else if let uuid = advertiseData.uuid {
            dataToBeAdvertised[CBAdvertisementDataServiceUUIDsKey] = [CBUUID(string: uuid)]
        }

        // Add local name
        if let localName = advertiseData.localName {
            dataToBeAdvertised[CBAdvertisementDataLocalNameKey] = localName
        }

        print("[flutter_ble_peripheral] start advertising data: \(String(describing: dataToBeAdvertised))")

        peripheralManager.startAdvertising(dataToBeAdvertised)

        // Optionally add a GATT service if powered on
        if addGattService, let serviceUuid = advertiseData.uuid, peripheralManager.state == .poweredOn {
            addService(serviceUuid: serviceUuid)
        }
    }

    /**
     Starts BLE advertising with a pre-built advertisement data dictionary.

     This method allows for more fine-grained control over advertisement data,
     including platform-specific settings like manufacturer data, service data, etc.

     - Parameter advertisementData: Complete advertisement data dictionary ready for CBPeripheralManager.
     */
    func startWithAdvertisementData(advertisementData: [String: Any]) {
        print("[flutter_ble_peripheral] Starting advertising with custom data: \(advertisementData)")

        peripheralManager.startAdvertising(advertisementData)

        // Extract service UUID if present to optionally add GATT service
        if let serviceUuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
           let firstUuid = serviceUuids.first,
           peripheralManager.state == .poweredOn {
            // Optionally add GATT service for the first advertised UUID
            // This enables connection support
            addService(serviceUuid: firstUuid.uuidString)
        }
    }

    // MARK: - GATT Service Management

    /**
     Adds a GATT service with TX and RX characteristics.

     - Parameters:
       - serviceUuid: The UUID of the service to add.
       - txCharacteristicUuid: Optional UUID for the TX characteristic (auto-generated if omitted).
       - rxCharacteristicUuid: Optional UUID for the RX characteristic (auto-generated if omitted).
     */
    func addService(serviceUuid: String, txCharacteristicUuid: String? = nil, rxCharacteristicUuid: String? = nil) {
        let txUuid = txCharacteristicUuid ?? generateCharacteristicUuid(serviceUuid: serviceUuid, type: "TX")
        let rxUuid = rxCharacteristicUuid ?? generateCharacteristicUuid(serviceUuid: serviceUuid, type: "RX")

        // TX characteristic: notify central devices of updates
        let mutableTxCharacteristic = CBMutableCharacteristic(
            type: CBUUID(string: txUuid),
            properties: [.read, .notify, .indicate],
            value: nil,
            permissions: [.readable]
        )

        // RX characteristic: receive data from central devices
        let mutableRxCharacteristic = CBMutableCharacteristic(
            type: CBUUID(string: rxUuid),
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )

        // Create and add service
        let service = CBMutableService(type: CBUUID(string: serviceUuid), primary: true)
        service.characteristics = [mutableTxCharacteristic, mutableRxCharacteristic]

        peripheralManager.add(service)

        self.currentService = service
        self.txCharacteristic = mutableTxCharacteristic
        self.rxCharacteristic = mutableRxCharacteristic

        print("[flutter_ble_peripheral] GATT service added: \(serviceUuid) with TX: \(txUuid), RX: \(rxUuid)")
    }

    /**
     Generates a predictable UUID for a characteristic based on the service UUID.

     This ensures a stable relationship between a service and its TX/RX characteristics.

     - Parameters:
       - serviceUuid: The base service UUID.
       - type: A string label, typically `"TX"` or `"RX"`.
     - Returns: A derived UUID string for the characteristic.
     */
    private func generateCharacteristicUuid(serviceUuid: String, type: String) -> String {
        let uuid = UUID(uuidString: serviceUuid) ?? UUID()
        let hashValue = type.hashValue
        var uuidString = uuid.uuidString

        // Modify the last UUID component for uniqueness
        let components = uuidString.components(separatedBy: "-")
        if components.count == 5 {
            let lastComponent = components[4]
            let modified = String(format: "%08X", Int(lastComponent, radix: 16)! ^ hashValue)
            uuidString = "\(components[0])-\(components[1])-\(components[2])-\(components[3])-\(modified)"
        }
        return uuidString
    }

    // MARK: - Data Transmission

    /**
     Sends data to connected central devices via the TX characteristic.

     - Parameter data: The binary payload to send.
     - Returns: `true` if the data was successfully transmitted, otherwise `false`.
     */
    func sendData(data: Data) -> Bool {
        print("[flutter_ble_peripheral] Send data: \(data.count) bytes")

        guard let characteristic = txCharacteristic else {
            print("[flutter_ble_peripheral] Cannot send data: No TX characteristic")
            return false
        }

        guard txSubscribed else {
            print("[flutter_ble_peripheral] Cannot send data: No devices subscribed")
            return false
        }

        let result = peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
        print("[flutter_ble_peripheral] Data sent: \(result)")
        return result
    }

    // MARK: - Lifecycle Management

    /**
     Stops BLE advertising and removes all GATT services.

     This also clears active connections and subscriptions.
     */
    func stop() {
        peripheralManager.stopAdvertising()

        if let service = currentService {
            peripheralManager.remove(service)
        }

        currentService = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        txSubscriptions.removeAll()
        connectedCentrals.removeAll()
        txSubscribed = false

        print("[flutter_ble_peripheral] Stopped advertising and removed services")
    }

    /**
     Returns whether any central devices are currently connected.

     - Returns: `true` if one or more centrals are connected, otherwise `false`.
     */
    func hasConnectedDevices() -> Bool {
        return !connectedCentrals.isEmpty
    }

    // MARK: - Bluetooth State and Permissions

    /**
     Returns the current Bluetooth permission state mapped to `FlutterBleBluetoothState`.

     On iOS 13+, the system triggers the permission dialog automatically
     when the `CBPeripheralManager` is created and authorization is `.notDetermined`.

     - Returns: The current Bluetooth permission state.
     */
    var permissionState: FlutterBleBluetoothState {
        if #available(iOS 13.1, *) {
            switch CBPeripheralManager.authorization {
            case .allowedAlways: return .Granted
            case .denied: return .PermanentlyDenied
            case .restricted: return .Restricted
            case .notDetermined: return .Denied
            @unknown default: return .Unknown
            }
        } else if #available(iOS 13.0, *) {
            switch peripheralManager.authorization {
            case .allowedAlways: return .Granted
            case .denied: return .PermanentlyDenied
            case .restricted: return .Restricted
            case .notDetermined: return .Denied
            @unknown default: return .Unknown
            }
        } else {
            return .Granted // Before iOS 13, permissions not required
        }
    }

    /// Convenience property indicating whether Bluetooth permission has been granted.
    var hasPermissions: Bool {
        return permissionState == .Granted
    }

    /**
     Returns the current Bluetooth adapter state mapped to `FlutterBleBluetoothState`.

     Reflects the actual state of the Bluetooth hardware or system stack.

     - Returns: The current adapter state.
     */
    var bluetoothState: FlutterBleBluetoothState {
        switch peripheralManager.state {
        case .poweredOn: return .Ready
        case .poweredOff: return .TurnedOff
        case .resetting: return .Unknown
        case .unauthorized: return .Denied
        case .unsupported: return .Unsupported
        case .unknown: return .Unknown
        @unknown default: return .Unknown
        }
    }

    /**
     Returns the combined Bluetooth readiness state,
     taking into account both permission and adapter status.

     - Returns: The overall `FlutterBleBluetoothState`.
     */
    func getCombinedState() -> FlutterBleBluetoothState {
        let permState = permissionState
        return permState == .Granted ? bluetoothState : permState
    }

    /**
     Attempts to request Bluetooth permission by triggering the system dialog if needed.

     - Parameter completion: Callback invoked with the updated permission state.
     */
    func requestPermission(completion: @escaping (FlutterBleBluetoothState) -> Void) {
        switch permissionState {
        case .Denied:
            _ = CBPeripheralManager(delegate: nil, queue: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion(self.permissionState)
            }
        default:
            completion(permissionState)
        }
    }
}
