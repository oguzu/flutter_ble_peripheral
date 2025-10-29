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
import androidx.core.content.edit
import dev.steenbakker.flutter_ble_peripheral.callbacks.GattServerCallback
import dev.steenbakker.flutter_ble_peripheral.callbacks.PeripheralAdvertisingCallback
import dev.steenbakker.flutter_ble_peripheral.callbacks.PeripheralAdvertisingSetCallback
import dev.steenbakker.flutter_ble_peripheral.handlers.DataReceivedHandler
import dev.steenbakker.flutter_ble_peripheral.handlers.MtuChangedHandler
import dev.steenbakker.flutter_ble_peripheral.handlers.FlutterBlePeripheralStateChangedHandler
import dev.steenbakker.flutter_ble_peripheral.models.FlutterBleBluetoothState
import io.flutter.Log
import java.util.UUID

/**
 * BLE Peripheral manager responsible for low-level Bluetooth LE peripheral operations.
 *
 * Responsibilities:
 * - Manage BLE advertising (both legacy and advertising sets).
 * - Handle Bluetooth adapter state and permissions.
 * - Manage GATT server for bidirectional communication with centrals.
 * - Coordinate with Flutter handlers for state changes, data received, and MTU changes.
 */
class FlutterBlePeripheralManager(
    private val context: Context,
    private val flutterBlePeripheralStateChangedHandler: FlutterBlePeripheralStateChangedHandler,
    private val dataReceivedHandler: DataReceivedHandler?,
    private val mtuChangedHandler: MtuChangedHandler?
) {

    companion object {
        /** Request code for Bluetooth enable intent. */
        const val REQUEST_ENABLE_BT = 4

        /** Request code for Bluetooth permission requests. */
        const val REQUEST_PERMISSION_BT = 8

        /** Tag for logging purposes. */
        private const val TAG = "FlutterBlePeripheralMgr"

        /** Client Characteristic Configuration Descriptor UUID for enabling notifications/indications. */
        private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    /** Bluetooth manager for accessing the BLE adapter. */
    var mBluetoothManager: BluetoothManager? = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager

    /** BLE advertiser for broadcasting peripheral data. */
    var mBluetoothLeAdvertiser: BluetoothLeAdvertiser? = mBluetoothManager?.adapter?.bluetoothLeAdvertiser

    /** Callback invoked after permission request result */
    var permissionResultCallback: ((FlutterBleBluetoothState) -> Unit)? = null

    /** Callback invoked after enable bluetooth request */
    var bluetoothEnabledCallback: ((Boolean) -> Unit)? = null

    /** GATT server instance for handling connections from centrals. */
    private var mBluetoothGattServer: BluetoothGattServer? = null

    /** Callback handler for GATT server events. */
    private var gattServerCallback: GattServerCallback? = null

    /** TX characteristic for sending data to centrals (notify/indicate). */
    private var txCharacteristic: BluetoothGattCharacteristic? = null

    /** RX characteristic for receiving data from centrals (write). */
    private var rxCharacteristic: BluetoothGattCharacteristic? = null

    /** UUID of the currently active GATT service. */
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
     * Start BLE advertising using the legacy advertising API.
     *
     * Optionally creates a GATT server with TX/RX characteristics for bidirectional communication.
     *
     * @param peripheralData The advertise data to broadcast
     * @param peripheralSettings The advertise settings (mode, power, timeout, etc.)
     * @param peripheralResponse Optional scan response data
     * @param mAdvertiseCallback Callback for advertising events
     * @param serviceUuid Optional service UUID for GATT server
     * @param addGattService If true and serviceUuid is provided, creates a GATT server
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
     * Start BLE advertising using the Advertising Set API (Android O+).
     *
     * Supports extended advertising features like multiple PHYs and periodic advertising.
     * Optionally creates a GATT server with TX/RX characteristics for bidirectional communication.
     *
     * @param advertiseData The advertise data to broadcast
     * @param advertiseSettingsSet The advertising set parameters
     * @param peripheralResponse Optional scan response data
     * @param periodicResponse Optional periodic advertising data
     * @param periodicResponseSettings Optional periodic advertising parameters
     * @param maxExtendedAdvertisingEvents Maximum number of extended advertising events (0 = no limit)
     * @param duration Duration in 10ms units (0 = no time limit)
     * @param mAdvertiseSetCallback Callback for advertising set events
     * @param serviceUuid Optional service UUID for GATT server
     * @param addGattService If true and serviceUuid is provided, creates a GATT server
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

    /**
     * Stop legacy BLE advertising and close GATT server.
     *
     * @param advertisingCallback The callback used when starting advertising
     */
    fun stop(advertisingCallback: AdvertiseCallback) {
        mBluetoothLeAdvertiser!!.stopAdvertising(advertisingCallback)
        closeGattServer()
    }

    /**
     * Stop advertising set (Android O+) and close GATT server.
     *
     * @param advertisingSetCallback The callback used when starting the advertising set
     */
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
                    flutterBlePeripheralStateChangedHandler,
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

    /**
     * Checks whether Bluetooth is currently enabled.
     *
     * @return `true` if enabled, `false` otherwise
     */
    fun isBluetoothEnabled(): Boolean {
        return mBluetoothManager?.adapter?.isEnabled ?: false
    }

    /**
     * Attempts to enable Bluetooth on the device.
     *
     * If [callback] is not null, shows the system dialog to request user approval.
     * If [callback] is null and the Android version is below Tiramisu, enables Bluetooth programmatically.
     *
     * @param activity Activity to use for launching the enable dialog
     * @param callback Response on intent to enable bluetooth (pre-Android 13)
     */
    fun enableBluetooth(activity: Activity, callback: ((Boolean) -> Unit)?) {
        if (callback != null) {
            bluetoothEnabledCallback = callback
            ActivityCompat.startActivityForResult(
                activity,
                Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
                REQUEST_ENABLE_BT,
                null
            )
        } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            @Suppress("DEPRECATION")
            mBluetoothManager!!.adapter.enable()
        }
    }

    /**
     * Returns a list of missing permissions depending on the Android version.
     *
     * @param activity The activity to check permissions against
     * @return List of permission strings that are not currently granted
     */
    fun getMissingPermissions(activity: Activity): List<String> {
        val missingPermissions = mutableListOf<String>()

        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                if (!hasBluetoothAdvertisePermission(activity)) {
                    missingPermissions.add(Manifest.permission.BLUETOOTH_ADVERTISE)
                }
                if (!hasBluetoothConnectPermission(activity)) {
                    missingPermissions.add(Manifest.permission.BLUETOOTH_CONNECT)
                }
            }

            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P -> {
                if (!hasLocationFinePermission(activity)) {
                    missingPermissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
                }
                if (!hasLocationCoarsePermission(activity)) {
                    missingPermissions.add(Manifest.permission.ACCESS_COARSE_LOCATION)
                }
            }

            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> {
                if (!hasLocationCoarsePermission(activity)) {
                    missingPermissions.add(Manifest.permission.ACCESS_COARSE_LOCATION)
                }
            }
        }

        return missingPermissions
    }

    /**
     * Checks and optionally requests missing Bluetooth-related permissions.
     *
     * @param activity The activity to request permissions from
     * @param callback Optional callback for async permission result.
     * If `null`, the method just returns the current [FlutterBleBluetoothState].
     *
     * @return Current [FlutterBleBluetoothState] if no request is needed, or `null` if a request was initiated.
     */
    fun requestPermission(activity: Activity, callback: ((FlutterBleBluetoothState) -> Unit)?): FlutterBleBluetoothState? {
        val missingPermissions = getMissingPermissions(activity)

        // No missing permissions
        if (missingPermissions.isEmpty()) {
            setPermissionGranted(activity, true)
            return FlutterBleBluetoothState.Granted
        }

        val previouslyRequested = getPermissionRequested(activity)
        val previouslyGranted = getPermissionGranted(activity)

        val shouldShowRationale = missingPermissions.any { permission ->
            ActivityCompat.shouldShowRequestPermissionRationale(activity, permission)
        }

        val isRevoked = previouslyGranted && missingPermissions.isNotEmpty()

        // Just checking status
        if (callback == null) {
            return when {
                isRevoked -> FlutterBleBluetoothState.Denied
                shouldShowRationale -> FlutterBleBluetoothState.Denied
                !previouslyRequested -> FlutterBleBluetoothState.Denied
                else -> FlutterBleBluetoothState.PermanentlyDenied
            }
        }

        // Request permission
        permissionResultCallback = callback
        setPermissionRequested(activity, true)
        ActivityCompat.requestPermissions(
            activity,
            missingPermissions.toTypedArray(),
            REQUEST_PERMISSION_BT
        )

        return null
    }

    /**
     * Returns the current Bluetooth adapter state as a [FlutterBleBluetoothState] enum.
     *
     * @return [FlutterBleBluetoothState.Unsupported] if adapter is null,
     * [FlutterBleBluetoothState.Denied] if disabled, [FlutterBleBluetoothState.Ready] if enabled.
     */
    fun getBluetoothState(): FlutterBleBluetoothState {
        val adapter = mBluetoothManager?.adapter
        return if (adapter == null) FlutterBleBluetoothState.Unsupported
        else if (!adapter.isEnabled) FlutterBleBluetoothState.Denied
        else FlutterBleBluetoothState.Ready
    }

    /**
     * Ensures Bluetooth is ready before performing BLE operations.
     *
     * - Checks adapter support
     * - Requests permissions if needed
     * - Enables Bluetooth if disabled
     *
     * @param activity The activity context
     * @param onReady Callback executed if Bluetooth is ready
     * @param onError Callback executed with the error [FlutterBleBluetoothState]
     */
    fun ensureBluetoothReady(
        activity: Activity,
        onReady: () -> Unit,
        onError: (FlutterBleBluetoothState) -> Unit
    ) {
        if (getBluetoothState() == FlutterBleBluetoothState.Unsupported) {
            onError(FlutterBleBluetoothState.Unsupported)
            return
        }

        val permissionState = requestPermission(activity) { permState ->
            if (permState == FlutterBleBluetoothState.Granted) {
                if (!isBluetoothEnabled()) {
                    enableBluetooth(activity) { bluetoothEnabled ->
                        if (bluetoothEnabled) {
                            onReady()
                        } else {
                            onError(FlutterBleBluetoothState.TurnedOff)
                        }
                    }
                } else {
                    onReady()
                }
            } else {
                onError(permState)
            }
        }

        if (permissionState == FlutterBleBluetoothState.Granted) {
            if (!isBluetoothEnabled()) {
                enableBluetooth(activity) { bluetoothEnabled ->
                    if (bluetoothEnabled) {
                        onReady()
                    } else {
                        onError(FlutterBleBluetoothState.TurnedOff)
                    }
                }
            } else {
                onReady()
            }
        }
    }

    /**
     * Persist the permission granted flag in SharedPreferences.
     */
    fun setPermissionGranted(context: Context, granted: Boolean) {
        val prefs = context.getSharedPreferences("flutter_ble_central", Context.MODE_PRIVATE)
        prefs.edit { putBoolean("permission_granted", granted) }
    }

    /**
     * Persist the permission requested flag in SharedPreferences.
     */
    fun setPermissionRequested(context: Context, granted: Boolean) {
        val prefs = context.getSharedPreferences("flutter_ble_central", Context.MODE_PRIVATE)
        prefs.edit { putBoolean("permission_requested", granted) }
    }

    /**
     * Returns whether permission has been granted previously.
     */
    fun getPermissionGranted(context: Context): Boolean {
        val prefs = context.getSharedPreferences("flutter_ble_central", Context.MODE_PRIVATE)
        return prefs.getBoolean("permission_granted", false)
    }

    /**
     * Returns whether permission has been requested previously.
     */
    fun getPermissionRequested(context: Context): Boolean {
        val prefs = context.getSharedPreferences("flutter_ble_central", Context.MODE_PRIVATE)
        return prefs.getBoolean("permission_requested", false)
    }
}
