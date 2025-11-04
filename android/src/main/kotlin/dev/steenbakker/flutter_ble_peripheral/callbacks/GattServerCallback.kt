/*
 * Copyright (c) 2020. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

package dev.steenbakker.flutter_ble_peripheral.callbacks

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothProfile
import android.os.Handler
import android.os.Looper
import dev.steenbakker.flutter_ble_peripheral.handlers.DataReceivedHandler
import dev.steenbakker.flutter_ble_peripheral.handlers.MtuChangedHandler
import dev.steenbakker.flutter_ble_peripheral.handlers.FlutterBlePeripheralStateChangedHandler
import dev.steenbakker.flutter_ble_peripheral.models.FlutterBlePeripheralState
import io.flutter.Log

class GattServerCallback(
    private val flutterBlePeripheralStateChangedHandler: FlutterBlePeripheralStateChangedHandler,
    private val dataReceivedHandler: DataReceivedHandler?,
    private val mtuChangedHandler: MtuChangedHandler?,
    private val rxCharacteristicUuid: String?
) : BluetoothGattServerCallback() {

    private val tag = "GattServerCallback"
    private val connectedDevices = mutableSetOf<BluetoothDevice>()

    override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
        super.onConnectionStateChange(device, status, newState)

        Log.i(tag, "onConnectionStateChange: device=${device?.address}, status=$status, newState=$newState")

        // Only process if device is not null and status indicates success
        if (device == null) {
            Log.w(tag, "onConnectionStateChange called with null device")
            return
        }

        // Status 0 = SUCCESS (GATT_SUCCESS)
        // Only transition states on successful status
        if (status != BluetoothGatt.GATT_SUCCESS) {
            Log.w(tag, "onConnectionStateChange with non-success status: $status for device ${device.address}")
            return
        }

        when (newState) {
            BluetoothProfile.STATE_CONNECTED -> {
                Log.i(tag, "Device connected: ${device.address} (status: $status)")
                connectedDevices.add(device)
                flutterBlePeripheralStateChangedHandler.publish(FlutterBlePeripheralState.connected)
            }
            BluetoothProfile.STATE_DISCONNECTED -> {
                Log.i(tag, "Device disconnected: ${device.address} (status: $status)")
                connectedDevices.remove(device)
                if (connectedDevices.isEmpty()) {
                    flutterBlePeripheralStateChangedHandler.publish(FlutterBlePeripheralState.advertising)
                }
            }
            BluetoothProfile.STATE_CONNECTING -> {
                Log.i(tag, "Device connecting: ${device.address}")
            }
            BluetoothProfile.STATE_DISCONNECTING -> {
                Log.i(tag, "Device disconnecting: ${device.address}")
            }
            else -> {
                Log.w(tag, "Unknown connection state: $newState for device ${device.address}")
            }
        }
    }

    override fun onCharacteristicReadRequest(
        device: BluetoothDevice?,
        requestId: Int,
        offset: Int,
        characteristic: BluetoothGattCharacteristic?
    ) {
        super.onCharacteristicReadRequest(device, requestId, offset, characteristic)
        Log.i(tag, "Read request from ${device?.address} for characteristic ${characteristic?.uuid}")

        // For read requests, we'll return success with empty data
        // The actual data should be sent via notifications/indications
        sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
    }

    override fun onCharacteristicWriteRequest(
        device: BluetoothDevice?,
        requestId: Int,
        characteristic: BluetoothGattCharacteristic?,
        preparedWrite: Boolean,
        responseNeeded: Boolean,
        offset: Int,
        value: ByteArray?
    ) {
        super.onCharacteristicWriteRequest(device, requestId, characteristic, preparedWrite, responseNeeded, offset, value)

        Log.i(tag, "Write request from ${device?.address} for characteristic ${characteristic?.uuid}")

        var status = BluetoothGatt.GATT_SUCCESS

        // Check if this is the RX characteristic (if specified)
        if (rxCharacteristicUuid != null && characteristic?.uuid.toString().equals(rxCharacteristicUuid, ignoreCase = true)) {
            value?.let { data ->
                if (data.isNotEmpty()) {
                    Log.i(tag, "Received data: ${data.size} bytes")
                    // Publish received data to Flutter
                    Handler(Looper.getMainLooper()).post {
                        dataReceivedHandler?.publish(data)
                    }
                }
            }
        } else if (rxCharacteristicUuid == null) {
            // If no RX characteristic is specified, accept writes to any characteristic
            value?.let { data ->
                if (data.isNotEmpty()) {
                    Log.i(tag, "Received data: ${data.size} bytes")
                    Handler(Looper.getMainLooper()).post {
                        dataReceivedHandler?.publish(data)
                    }
                }
            }
        } else {
            Log.w(tag, "Write to unsupported characteristic: ${characteristic?.uuid}")
            status = BluetoothGatt.GATT_WRITE_NOT_PERMITTED
        }

        if (responseNeeded) {
            sendResponse(device, requestId, status, 0, null)
        }
    }

    override fun onDescriptorReadRequest(
        device: BluetoothDevice?,
        requestId: Int,
        offset: Int,
        descriptor: BluetoothGattDescriptor?
    ) {
        super.onDescriptorReadRequest(device, requestId, offset, descriptor)
        Log.i(tag, "Descriptor read request from ${device?.address} for descriptor ${descriptor?.uuid}")

        sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, descriptor?.value)
    }

    override fun onDescriptorWriteRequest(
        device: BluetoothDevice?,
        requestId: Int,
        descriptor: BluetoothGattDescriptor?,
        preparedWrite: Boolean,
        responseNeeded: Boolean,
        offset: Int,
        value: ByteArray?
    ) {
        super.onDescriptorWriteRequest(device, requestId, descriptor, preparedWrite, responseNeeded, offset, value)
        Log.i(tag, "Descriptor write request from ${device?.address} for descriptor ${descriptor?.uuid}")

        // Check if this is a CCCD (Client Characteristic Configuration Descriptor)
        val cccdUuid = "00002902-0000-1000-8000-00805f9b34fb"
        if (descriptor?.uuid.toString().equals(cccdUuid, ignoreCase = true)) {
            val characteristic = descriptor?.characteristic
            Log.i(tag, "CCCD write for characteristic ${characteristic?.uuid}")

            // Check if notifications/indications are being enabled
            value?.let {
                if (it.isNotEmpty()) {
                    val notificationsEnabled = it[0].toInt() and 0x01 != 0
                    val indicationsEnabled = it[0].toInt() and 0x02 != 0
                    Log.i(tag, "Notifications enabled: $notificationsEnabled, Indications enabled: $indicationsEnabled")
                }
            }
        }

        if (responseNeeded) {
            sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
        }
    }

    override fun onMtuChanged(device: BluetoothDevice?, mtu: Int) {
        super.onMtuChanged(device, mtu)
        Log.i(tag, "MTU changed to $mtu for device ${device?.address}")

        Handler(Looper.getMainLooper()).post {
            mtuChangedHandler?.publish(mtu)
        }
    }

    override fun onExecuteWrite(device: BluetoothDevice?, requestId: Int, execute: Boolean) {
        super.onExecuteWrite(device, requestId, execute)
        Log.i(tag, "Execute write from ${device?.address}, execute: $execute")

        sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
    }

    fun getConnectedDevices(): Set<BluetoothDevice> {
        return connectedDevices.toSet()
    }

    fun hasConnectedDevices(): Boolean {
        return connectedDevices.isNotEmpty()
    }

    // This method needs to be set by the manager that creates this callback
    var sendResponse: (device: BluetoothDevice?, requestId: Int, status: Int, offset: Int, value: ByteArray?) -> Unit = { _, _, _, _, _ -> }
}
