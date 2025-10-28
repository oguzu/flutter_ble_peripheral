/*
 * Copyright (c) 2020. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */


import Foundation
import CoreBluetooth
import CoreLocation

class FlutterBlePeripheralManager : NSObject {

    let stateChangedHandler: StateChangedHandler
    let dataReceivedHandler: DataReceivedHandler?
    let mtuChangedHandler: MtuChangedHandler?
    var peripheralManager : CBPeripheralManager!

    // GATT service and characteristics
    var currentService: CBMutableService?
    var txCharacteristic: CBMutableCharacteristic?
    var rxCharacteristic: CBMutableCharacteristic?

    // Connection tracking
    var txSubscriptions = Set<UUID>()
    var connectedCentrals = Set<UUID>()

    // MTU tracking (min MTU before iOS 10)
    var mtu: Int = 158 {
        didSet {
            mtuChangedHandler?.publishMtu(mtu: mtu)
        }
    }

    var txSubscribed = false {
        didSet {
            if txSubscribed {
                stateChangedHandler.publishPeripheralState(state: .connected)
            } else if peripheralManager.isAdvertising {
                stateChangedHandler.publishPeripheralState(state: .advertising)
            }
        }
    }

    init(stateChangedHandler: StateChangedHandler, dataReceivedHandler: DataReceivedHandler?, mtuChangedHandler: MtuChangedHandler?) {
        self.stateChangedHandler = stateChangedHandler
        self.dataReceivedHandler = dataReceivedHandler
        self.mtuChangedHandler = mtuChangedHandler
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey : true])
    }
    
    func start(advertiseData: FlutterBlePeripheralData, addGattService: Bool = false) {
        var dataToBeAdvertised: [String: Any]! = [:]
        if (advertiseData.uuids != nil) {
            dataToBeAdvertised[CBAdvertisementDataServiceUUIDsKey] = advertiseData.uuids!.map { CBUUID(string: $0) }
        } else if (advertiseData.uuid != nil) {
            dataToBeAdvertised[CBAdvertisementDataServiceUUIDsKey] = [CBUUID(string: advertiseData.uuid!)]
        }

        if (advertiseData.localName != nil) {
            dataToBeAdvertised[CBAdvertisementDataLocalNameKey] = advertiseData.localName
        }

        print("[flutter_ble_peripheral] start advertising data: \(String(describing: dataToBeAdvertised))")

        peripheralManager.startAdvertising(dataToBeAdvertised)

        // Add service if requested
        if addGattService, let serviceUuid = advertiseData.uuid, peripheralManager.state == .poweredOn {
            addService(serviceUuid: serviceUuid)
        }
    }

    /**
     * Add a GATT service with TX and RX characteristics.
     * @param serviceUuid The UUID of the service to add
     * @param txCharacteristicUuid Optional UUID for TX characteristic (defaults to auto-generated)
     * @param rxCharacteristicUuid Optional UUID for RX characteristic (defaults to auto-generated)
     */
    func addService(serviceUuid: String, txCharacteristicUuid: String? = nil, rxCharacteristicUuid: String? = nil) {
        // Generate default characteristic UUIDs if not provided
        let txUuid = txCharacteristicUuid ?? generateCharacteristicUuid(serviceUuid: serviceUuid, type: "TX")
        let rxUuid = rxCharacteristicUuid ?? generateCharacteristicUuid(serviceUuid: serviceUuid, type: "RX")

        // Create TX characteristic (for sending data to central)
        let mutableTxCharacteristic = CBMutableCharacteristic(
            type: CBUUID(string: txUuid),
            properties: [.read, .notify, .indicate],
            value: nil,
            permissions: [.readable]
        )

        // Create RX characteristic (for receiving data from central)
        let mutableRxCharacteristic = CBMutableCharacteristic(
            type: CBUUID(string: rxUuid),
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )

        // Create service and add characteristics
        let service = CBMutableService(type: CBUUID(string: serviceUuid), primary: true)
        service.characteristics = [mutableTxCharacteristic, mutableRxCharacteristic]

        // Add service to peripheral manager
        peripheralManager.add(service)

        self.currentService = service
        self.txCharacteristic = mutableTxCharacteristic
        self.rxCharacteristic = mutableRxCharacteristic

        print("[flutter_ble_peripheral] GATT service added: \(serviceUuid) with TX: \(txUuid), RX: \(rxUuid)")
    }

    /**
     * Generate a characteristic UUID based on the service UUID.
     * This creates a predictable UUID by modifying the service UUID.
     */
    private func generateCharacteristicUuid(serviceUuid: String, type: String) -> String {
        let uuid = UUID(uuidString: serviceUuid) ?? UUID()
        let hashValue = type.hashValue
        // XOR the hash with the UUID components to create a new UUID
        var uuidString = uuid.uuidString
        // Simple modification - append type suffix for uniqueness
        let components = uuidString.components(separatedBy: "-")
        if components.count == 5 {
            let lastComponent = components[4]
            let modified = String(format: "%08X", Int(lastComponent, radix: 16)! ^ hashValue)
            uuidString = "\(components[0])-\(components[1])-\(components[2])-\(components[3])-\(modified)"
        }
        return uuidString
    }

    /**
     * Send data to connected centrals via the TX characteristic.
     * @param data The data to send
     * @return true if notification was sent successfully
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

    /**
     * Stop advertising and clean up GATT server.
     */
    func stop() {
        peripheralManager.stopAdvertising()

        // Clean up GATT services
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
     * Check if any devices are connected.
     */
    func hasConnectedDevices() -> Bool {
        return !connectedCentrals.isEmpty
    }
}
