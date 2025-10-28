//
//  PeripheralManagerDelegate.swift
//  flutter_ble_peripheral
//
//  Created by Julian Steenbakker on 25/03/2022.
//

import Foundation
import CoreBluetooth
import CoreLocation

extension FlutterBlePeripheralManager: CBPeripheralManagerDelegate {
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        var state: FlutterBlePeripheralState
        switch peripheral.state {
        case .poweredOn:
            state = .idle
//            addService() TODO: add service
        case .poweredOff:
            state = .poweredOff
        case .resetting:
            state = .idle
        case .unsupported:
            state = .unsupported
        case .unauthorized:
            state = .unauthorized
        case .unknown:
            state = .unknown
        @unknown default:
            state = .unknown
        }
        stateChangedHandler.publishPeripheralState(state: state)
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        print("[flutter_ble_peripheral] didStartAdvertising:", error ?? "success")

        guard error == nil else {
            return
        }

        stateChangedHandler.publishPeripheralState(state: .advertising)

        // Immediately set to connected if the tx Characteristic is already subscribed
        if txSubscribed {
            stateChangedHandler.publishPeripheralState(state: .connected)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        print("[flutter_ble_peripheral] didReceiveRead:", request)

        // For read requests, we'll return success with empty data
        // The actual data should be sent via notifications/indications
        peripheralManager.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        print("[flutter_ble_peripheral] didReceiveWrite:", requests)

        for request in requests {
            print("[flutter_ble_peripheral] write request:", request)

            let characteristic = request.characteristic
            guard let data = request.value else {
                print("[flutter_ble_peripheral] request.value is nil")
                peripheralManager.respond(to: request, withResult: .invalidAttributeValueLength)
                return
            }

            // Check if this is the RX characteristic (accept writes)
            if characteristic.uuid == rxCharacteristic?.uuid {
                print("[flutter_ble_peripheral] Received data on RX characteristic: \(data.count) bytes")

                if data.count > 0 {
                    // Publish received data to Flutter
                    dataReceivedHandler?.publishData(data: data)
                }

                // Respond with success
                peripheralManager.respond(to: request, withResult: .success)
            } else {
                // Write not supported on other characteristics
                print("[flutter_ble_peripheral] Write not supported on characteristic: \(characteristic.uuid)")
                peripheralManager.respond(to: request, withResult: .writeNotPermitted)
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        print("[flutter_ble_peripheral] didSubscribeTo:", central.identifier, characteristic.uuid)

        if characteristic.uuid == txCharacteristic?.uuid {
            // Update MTU
            self.mtu = central.maximumUpdateValueLength
            print("[flutter_ble_peripheral] MTU updated: \(mtu)")

            // Add to subscriptions and connected centrals
            txSubscriptions.insert(central.identifier)
            connectedCentrals.insert(central.identifier)

            txSubscribed = !txSubscriptions.isEmpty

            print("[flutter_ble_peripheral] txSubscriptions count: \(txSubscriptions.count)")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        print("[flutter_ble_peripheral] didUnsubscribeFrom:", central.identifier, characteristic.uuid)

        if characteristic.uuid == txCharacteristic?.uuid {
            // Remove from subscriptions and connected centrals
            txSubscriptions.remove(central.identifier)
            connectedCentrals.remove(central.identifier)

            txSubscribed = !txSubscriptions.isEmpty

            print("[flutter_ble_peripheral] txSubscriptions count: \(txSubscriptions.count)")

            // Update state based on remaining connections
            if !txSubscribed && peripheralManager.isAdvertising {
                stateChangedHandler.publishPeripheralState(state: .advertising)
            } else if !txSubscribed && !peripheralManager.isAdvertising {
                stateChangedHandler.publishPeripheralState(state: .idle)
            }
        }
    }
}
