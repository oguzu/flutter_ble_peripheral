/*
 * Copyright (c) 2020. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

package dev.steenbakker.flutter_ble_peripheral

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.AdvertisingSetCallback
import android.bluetooth.le.AdvertisingSetParameters
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.PeriodicAdvertisingParameters
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import dev.steenbakker.flutter_ble_peripheral.callbacks.GattServerCallback
import dev.steenbakker.flutter_ble_peripheral.callbacks.PeripheralAdvertisingCallback
import dev.steenbakker.flutter_ble_peripheral.callbacks.PeripheralAdvertisingSetCallback
import dev.steenbakker.flutter_ble_peripheral.handlers.DataReceivedHandler
import dev.steenbakker.flutter_ble_peripheral.handlers.MtuChangedHandler
import dev.steenbakker.flutter_ble_peripheral.handlers.StateChangedHandler
import dev.steenbakker.flutter_ble_peripheral.models.State
import io.flutter.Log
import java.util.UUID

class FlutterBlePeripheralManager(
    private val context: Context,
    private val stateChangedHandler: StateChangedHandler,
    private val dataReceivedHandler: DataReceivedHandler?,
    private val mtuChangedHandler: MtuChangedHandler?
) {

    companion object {
        const val REQUEST_ENABLE_BT = 4
        const val REQUEST_PERMISSION_BT = 8
        private const val TAG = "FlutterBlePeripheralMgr"

        // Client Characteristic Configuration Descriptor UUID
        private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    var mBluetoothManager: BluetoothManager? = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    var mBluetoothLeAdvertiser: BluetoothLeAdvertiser? = null

    private var mBluetoothGattServer: BluetoothGattServer? = null
    private var gattServerCallback: GattServerCallback? = null
    private var txCharacteristic: BluetoothGattCharacteristic? = null
    private var rxCharacteristic: BluetoothGattCharacteristic? = null
    private var currentServiceUuid: String? = null

    // Permissions for Bluetooth API > 31
    @RequiresApi(Build.VERSION_CODES.S)
    private fun hasBluetoothAdvertisePermission(context: Context): Boolean {
        return (context.checkSelfPermission(
            Manifest.permission.BLUETOOTH_ADVERTISE
        )
                == PackageManager.PERMISSION_GRANTED)
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun hasBluetoothConnectPermission(context: Context): Boolean {
        return (context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
                == PackageManager.PERMISSION_GRANTED)
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun hasLocationFinePermission(context: Context): Boolean {
        return (context.checkSelfPermission(
            Manifest.permission.ACCESS_FINE_LOCATION
        )
                == PackageManager.PERMISSION_GRANTED)
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun hasLocationCoarsePermission(context: Context): Boolean {
        return (context.checkSelfPermission(
            Manifest.permission.ACCESS_COARSE_LOCATION
        )
                == PackageManager.PERMISSION_GRANTED)
    }

    /**
     * Check if bluetooth is enabled.
     */
    fun isBluetoothEnabled(): Boolean {
        return mBluetoothManager?.adapter?.isEnabled ?: false
    }
    fun hasPermission(activity: Activity): State {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (!hasBluetoothAdvertisePermission(activity) || !hasBluetoothConnectPermission(activity)) {
                if (ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.BLUETOOTH_ADVERTISE) ||
                    ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.BLUETOOTH_CONNECT)) {
                    return State.Denied
                }
                return State.PermanentlyDenied
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            if (!hasLocationCoarsePermission(activity) || !hasLocationFinePermission(activity)) {
                if (ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_FINE_LOCATION) ||
                    ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_COARSE_LOCATION)) {
                    return State.Denied
                }
                return State.PermanentlyDenied
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!hasLocationCoarsePermission(activity)) {
                if (ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_COARSE_LOCATION)) {
                    return State.Denied
                }
                return State.PermanentlyDenied
            }
        }
        return State.Granted
    }

    fun requestPermission(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.BLUETOOTH_ADVERTISE
                ),
                REQUEST_PERMISSION_BT
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ),
                REQUEST_PERMISSION_BT
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION),
                REQUEST_PERMISSION_BT
            )
        }
    }

    fun enableBluetoothWithDialog(activity: Activity) {
        ActivityCompat.startActivityForResult(
            activity,
            Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
            REQUEST_ENABLE_BT,
            null
        )
    }

    fun enableBluetoothDirectly() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            @Suppress("DEPRECATION")
            mBluetoothManager!!.adapter.enable()
        }
    }

    /**
     * Start advertising using the startAdvertising() method.
     */
    fun start(
        peripheralData: AdvertiseData,
        peripheralSettings: AdvertiseSettings,
        peripheralResponse: AdvertiseData?,
        mAdvertiseCallback: PeripheralAdvertisingCallback,
        serviceUuid: String? = null,
        addGattService: Boolean = false
    ) {
        // Store service UUID for GATT server
        currentServiceUuid = serviceUuid

        mBluetoothLeAdvertiser!!.startAdvertising(
                peripheralSettings,
                peripheralData,
                peripheralResponse,
                mAdvertiseCallback
        )

        // Add GATT service if requested
        if (addGattService && serviceUuid != null) {
            addService(serviceUuid)
        }
    }

    /**
     * Start advertising using the startAdvertisingSet method.
     */
    @RequiresApi(Build.VERSION_CODES.O)
    fun startSet(
        advertiseData: AdvertiseData,
        advertiseSettingsSet: AdvertisingSetParameters,
        peripheralResponse: AdvertiseData?,
        periodicResponse: AdvertiseData?,
        periodicResponseSettings: PeriodicAdvertisingParameters?,
        maxExtendedAdvertisingEvents: Int = 0,
        duration: Int = 0,
        mAdvertiseSetCallback: PeripheralAdvertisingSetCallback,
        serviceUuid: String? = null,
        addGattService: Boolean = false
    ) {
        // Store service UUID for GATT server
        currentServiceUuid = serviceUuid

        mBluetoothLeAdvertiser!!.startAdvertisingSet(
                advertiseSettingsSet,
                advertiseData,
                peripheralResponse,
                periodicResponseSettings,
                periodicResponse,
                duration,
                maxExtendedAdvertisingEvents,
                mAdvertiseSetCallback,
        )

        // Add GATT service if requested
        if (addGattService && serviceUuid != null) {
            addService(serviceUuid)
        }
    }

    fun stop(advertisingCallback: AdvertiseCallback) {
        mBluetoothLeAdvertiser!!.stopAdvertising(advertisingCallback)
        closeGattServer()
    }

    @RequiresApi(Build.VERSION_CODES.O)
    fun stopSet(advertisingSetCallback: AdvertisingSetCallback) {
        mBluetoothLeAdvertiser!!.stopAdvertisingSet(advertisingSetCallback)
        closeGattServer()
    }

    /**
     * Add a GATT service with TX and RX characteristics.
     * @param serviceUuid The UUID of the service to add
     * @param txCharacteristicUuid Optional UUID for TX characteristic (defaults to auto-generated)
     * @param rxCharacteristicUuid Optional UUID for RX characteristic (defaults to auto-generated)
     */
    fun addService(
        serviceUuid: String,
        txCharacteristicUuid: String? = null,
        rxCharacteristicUuid: String? = null
    ) {
        try {
            // Create callback if not exists
            if (gattServerCallback == null) {
                gattServerCallback = GattServerCallback(
                    stateChangedHandler,
                    dataReceivedHandler,
                    mtuChangedHandler,
                    rxCharacteristicUuid
                )
                gattServerCallback!!.sendResponse = { device, requestId, status, offset, value ->
                    mBluetoothGattServer?.sendResponse(device, requestId, status, offset, value)
                }
            }

            // Open GATT server if not already open
            if (mBluetoothGattServer == null) {
                mBluetoothGattServer = mBluetoothManager?.openGattServer(context, gattServerCallback)
                Log.i(TAG, "GATT server opened")
            }

            // Generate default characteristic UUIDs if not provided
            val txUuid = txCharacteristicUuid ?: generateCharacteristicUuid(serviceUuid, "TX")
            val rxUuid = rxCharacteristicUuid ?: generateCharacteristicUuid(serviceUuid, "RX")

            // Create TX characteristic (for sending data to central)
            txCharacteristic = BluetoothGattCharacteristic(
                UUID.fromString(txUuid),
                BluetoothGattCharacteristic.PROPERTY_READ or
                BluetoothGattCharacteristic.PROPERTY_NOTIFY or
                BluetoothGattCharacteristic.PROPERTY_INDICATE,
                BluetoothGattCharacteristic.PERMISSION_READ
            )

            // Add CCCD descriptor to TX characteristic for notifications
            val cccdDescriptor = BluetoothGattDescriptor(
                CCCD_UUID,
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
            )
            txCharacteristic?.addDescriptor(cccdDescriptor)

            // Create RX characteristic (for receiving data from central)
            rxCharacteristic = BluetoothGattCharacteristic(
                UUID.fromString(rxUuid),
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
                BluetoothGattCharacteristic.PERMISSION_WRITE
            )

            // Create service and add characteristics
            val service = BluetoothGattService(
                UUID.fromString(serviceUuid),
                BluetoothGattService.SERVICE_TYPE_PRIMARY
            )
            service.addCharacteristic(txCharacteristic)
            service.addCharacteristic(rxCharacteristic)

            // Add service to GATT server
            val added = mBluetoothGattServer?.addService(service)
            if (added == true) {
                Log.i(TAG, "GATT service added: $serviceUuid with TX: $txUuid, RX: $rxUuid")
            } else {
                Log.e(TAG, "Failed to add GATT service")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error adding GATT service: ${e.message}")
        }
    }

    /**
     * Generate a characteristic UUID based on the service UUID.
     * This creates a predictable UUID by modifying the service UUID.
     */
    private fun generateCharacteristicUuid(serviceUuid: String, type: String): String {
        val baseUuid = UUID.fromString(serviceUuid)
        val hashCode = type.hashCode()
        return UUID(baseUuid.mostSignificantBits xor hashCode.toLong(), baseUuid.leastSignificantBits).toString()
    }

    /**
     * Send data to connected centrals via the TX characteristic.
     * @param data The data to send
     * @return true if notification was sent successfully
     */
    fun sendData(data: ByteArray): Boolean {
        val characteristic = txCharacteristic
        val server = mBluetoothGattServer
        val callback = gattServerCallback

        if (characteristic == null || server == null || callback == null) {
            Log.e(TAG, "Cannot send data: GATT server not initialized or no TX characteristic")
            return false
        }

        if (!callback.hasConnectedDevices()) {
            Log.w(TAG, "Cannot send data: No devices connected")
            return false
        }

        return try {
            // Set the characteristic value
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // For API 33+, send to each connected device
                var allSuccess = true
                callback.getConnectedDevices().forEach { device ->
                    val result = server.notifyCharacteristicChanged(device, characteristic, false, data)
                    allSuccess = allSuccess && result == 0
                }
                Log.i(TAG, "Data sent to ${callback.getConnectedDevices().size} device(s)")
                allSuccess
            } else {
                // For older APIs, use deprecated method
                @Suppress("DEPRECATION")
                characteristic.value = data
                @Suppress("DEPRECATION")
                val result = server.notifyCharacteristicChanged(null, characteristic, false)
                Log.i(TAG, "Data sent: $result")
                result
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error sending data: ${e.message}")
            false
        }
    }

    /**
     * Close the GATT server and clean up resources.
     */
    fun closeGattServer() {
        try {
            mBluetoothGattServer?.clearServices()
            mBluetoothGattServer?.close()
            mBluetoothGattServer = null
            gattServerCallback = null
            txCharacteristic = null
            rxCharacteristic = null
            Log.i(TAG, "GATT server closed")
        } catch (e: Exception) {
            Log.e(TAG, "Error closing GATT server: ${e.message}")
        }
    }

    /**
     * Check if GATT server is running.
     */
    fun isGattServerRunning(): Boolean {
        return mBluetoothGattServer != null
    }

    /**
     * Check if any devices are connected to the GATT server.
     */
    fun hasConnectedDevices(): Boolean {
        return gattServerCallback?.hasConnectedDevices() ?: false
    }
}
