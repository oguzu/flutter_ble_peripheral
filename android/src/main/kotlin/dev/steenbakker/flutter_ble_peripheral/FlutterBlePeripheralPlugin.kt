/*
 * Copyright (c) 2020. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

package dev.steenbakker.flutter_ble_peripheral

import android.app.Activity
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.AdvertisingSetParameters
import android.bluetooth.le.PeriodicAdvertisingParameters
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.provider.Settings
import androidx.core.app.ActivityCompat
import dev.steenbakker.flutter_ble_peripheral.FlutterBlePeripheralManager.Companion.REQUEST_ENABLE_BT
import dev.steenbakker.flutter_ble_peripheral.FlutterBlePeripheralManager.Companion.REQUEST_PERMISSION_BT
import dev.steenbakker.flutter_ble_peripheral.callbacks.PeripheralAdvertisingCallback
import dev.steenbakker.flutter_ble_peripheral.callbacks.PeripheralAdvertisingSetCallback
import dev.steenbakker.flutter_ble_peripheral.handlers.DataReceivedHandler
import dev.steenbakker.flutter_ble_peripheral.handlers.MtuChangedHandler
import dev.steenbakker.flutter_ble_peripheral.handlers.FlutterBlePeripheralStateChangedHandler
import dev.steenbakker.flutter_ble_peripheral.models.*
import io.flutter.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.*

/**
 * Flutter plugin entry point for the Flutter BLE Peripheral library.
 *
 * Responsibilities:
 * - Manage the method channel and handle Flutter method calls.
 * - Coordinate Bluetooth LE peripheral operations through [FlutterBlePeripheralManager].
 * - Handle Android runtime permissions and activity results.
 * - Interface with Flutter handlers for state changes, data received, and MTU changes.
 */
class FlutterBlePeripheralPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.ActivityResultListener {

    /** Tag for logging purposes. */
    private val tag: String = "flutter_ble_peripheral"

    /** Method channel used for communication with Flutter. */
    private lateinit var methodChannel: MethodChannel

    /** Handler for broadcasting peripheral state changes to Flutter. */
    private lateinit var flutterBlePeripheralStateChangedHandler: FlutterBlePeripheralStateChangedHandler

    /** Handler for broadcasting received data from centrals to Flutter. */
    private lateinit var dataReceivedHandler: DataReceivedHandler

    /** Handler for broadcasting MTU changes to Flutter. */
    private lateinit var mtuChangedHandler: MtuChangedHandler

    /** BLE manager responsible for low-level Bluetooth peripheral operations. */
    private var flutterBlePeripheralManager: FlutterBlePeripheralManager? = null

    /** Plugin context (application context). */
    private var context: Context? = null

    /** Current activity binding, needed for permissions and settings. */
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "dev.steenbakker.flutter_ble_peripheral/ble_state")
        methodChannel.setMethodCallHandler(this)

        context = flutterPluginBinding.applicationContext
        flutterBlePeripheralStateChangedHandler = FlutterBlePeripheralStateChangedHandler(flutterPluginBinding)
        dataReceivedHandler = DataReceivedHandler(flutterPluginBinding)
        mtuChangedHandler = MtuChangedHandler(flutterPluginBinding)
        flutterBlePeripheralManager = FlutterBlePeripheralManager(
            flutterPluginBinding.applicationContext,
            flutterBlePeripheralStateChangedHandler,
            dataReceivedHandler,
            mtuChangedHandler
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        flutterBlePeripheralManager = null
        context = null
    }
    
    /**
     * Handles all incoming method calls from Flutter.
     */
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (flutterBlePeripheralManager == null || context == null) {
            result.error("Not initialized", "FlutterBlePeripheral is not correctly initialized", null)
            return
        }

        when (call.method) {
            "start" -> handleStart(call, result)
            "stop" -> handleStop(result)
            "isSupported" -> handleIsSupported(result)
            "enableBluetooth" -> handleEnableBluetooth(call, result)
            "requestPermission" -> handleRequestPermission(result)
            "hasPermission" -> handleHasPermission(result)
            "openAppSettings" -> handleOpenAppSettings(result)
            "openBluetoothSettings" -> handleOpenBluetoothSettings(result)
            "isAdvertising" -> handleIsAdvertising(result)
            "isConnected" -> handleIsConnected(result)
            "sendData" -> handleSendData(call, result)
            else -> handleNotImplemented(result)
        }
    }

    private fun handleStart(call: MethodCall, result: MethodChannel.Result) {
        if (flutterBlePeripheralManager == null) {
            safeResult(result) { result.success(FlutterBleBluetoothState.Unsupported.ordinal) }
            return
        }

        val manager = flutterBlePeripheralManager!!

        if (activityBinding == null) {
            result.error("No activity", "Activity is not attached", null)
            return
        }

        manager.ensureBluetoothReady(
            activityBinding!!.activity,
            onReady = {
                startPeripheral(call, result)
            },
            onError = { state ->
                safeResult(result) { result.success(state.ordinal) }
            }
        )
    }

    private fun startPeripheral(call: MethodCall, result: MethodChannel.Result) {

        if (call.arguments !is Map<*, *>) {
            throw IllegalArgumentException("Arguments are not a map! " + call.arguments)
        }

        val arguments = call.arguments as Map<*, *>

        // First build main advertise data.
        val advertiseData: AdvertiseData.Builder = AdvertiseData.Builder()
        (arguments["manufacturerData"] as ArrayList<*>?)?.let { list -> advertiseData.addManufacturerData((arguments["manufacturerId"] as Int), list.map { (it as Int).toByte() }.toByteArray()) }
        (arguments["serviceData"] as ByteArray?)?.let { advertiseData.addServiceData(ParcelUuid(UUID.fromString(arguments["serviceDataUuid"] as String)), it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            (arguments["serviceSolicitationUuid"] as String?)?.let { advertiseData.addServiceSolicitationUuid(
                ParcelUuid(UUID.fromString(it))) }

        (arguments["serviceUuid"] as String?)?.let { advertiseData.addServiceUuid(ParcelUuid(UUID.fromString(it))) }
        //TODO: addTransportDiscoveryData
        (arguments["includeDeviceName"] as Boolean?)?.let { advertiseData.setIncludeDeviceName(it) }
        (arguments["transmissionPowerIncluded"] as Boolean?)?.let {
            advertiseData.setIncludeTxPowerLevel(it)
        }

        // Build advertise response data if provided
        var advertiseResponseData: AdvertiseData.Builder? = null
        if ((arguments["responsemanufacturerData"] as ByteArray?) != null || (arguments["responseserviceDataUuid"] as ByteArray?) != null || (arguments["responseserviceUuid"] as String?) != null) {
            advertiseResponseData = AdvertiseData.Builder()
            (arguments["responsemanufacturerData"] as ByteArray?)?.let { advertiseData.addManufacturerData((arguments["responsemanufacturerId"] as Int), it) }
            (arguments["responseserviceData"] as ByteArray?).let { advertiseData.addServiceData(ParcelUuid(UUID.fromString(arguments["responseserviceDataUuid"] as String)), it) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                (arguments["responseserviceSolicitationUuid"] as String?)?.let { advertiseData.addServiceSolicitationUuid(
                    ParcelUuid(UUID.fromString(it))) }

            (arguments["responseserviceUuid"] as String?)?.let { advertiseData.addServiceUuid(ParcelUuid(UUID.fromString(it))) }
            //TODO: addTransportDiscoveryData
            (arguments["responseincludeDeviceName"] as Boolean?)?.let { advertiseData.setIncludeDeviceName(it) }
            (arguments["responsetransmissionPowerIncluded"] as Boolean?)?.let {
                advertiseData.setIncludeTxPowerLevel(it)
            }
        }

        // Check if we should use the advertiseSet method instead of advertise
        if (arguments["advertiseSet"] as Boolean? == true && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {


            val advertiseSettingsSet: AdvertisingSetParameters.Builder = AdvertisingSetParameters.Builder()
            (arguments["setanonymous"] as Boolean?)?.let { advertiseSettingsSet.setAnonymous(it) }
            (arguments["setconnectable"] as Boolean?)?.let { advertiseSettingsSet.setConnectable(it) }
            (arguments["settransmissionPowerIncluded"] as Boolean?)?.let { advertiseSettingsSet.setIncludeTxPower(it) }
            (arguments["setinterval"] as Int?)?.let { advertiseSettingsSet.setInterval(it) }
            (arguments["setlegacyMode"] as Boolean?)?.let { advertiseSettingsSet.setLegacyMode(it) }
            (arguments["setprimaryPhy"] as Int?)?.let { advertiseSettingsSet.setPrimaryPhy(it) }
            (arguments["setscannable"] as Boolean?)?.let { advertiseSettingsSet.setScannable(it) }
            (arguments["setsecondaryPhy"] as Int?)?.let { advertiseSettingsSet.setSecondaryPhy(it) }
            (arguments["settxPowerLevel"] as Int?)?.let { advertiseSettingsSet.setTxPowerLevel(it) }

            var periodicAdvertiseData: AdvertiseData.Builder? = null
            var periodicAdvertiseDataSettings: PeriodicAdvertisingParameters.Builder? = null
            if ((arguments["periodicmanufacturerData"] as ByteArray?) != null || (arguments["periodicServiceDataUuid"] as ByteArray?) != null || (arguments["periodicServiceUuid"] as String?) != null) {
                periodicAdvertiseData = AdvertiseData.Builder()
                periodicAdvertiseDataSettings = PeriodicAdvertisingParameters.Builder()

                (arguments["periodicmanufacturerData"] as ByteArray?)?.let {
                    periodicAdvertiseData.addManufacturerData(
                        (arguments["periodicManufacturerId"] as Int),
                        it
                    )
                }
                (arguments["periodicserviceData"] as ByteArray?).let {
                    periodicAdvertiseData.addServiceData(
                        ParcelUuid(UUID.fromString(arguments["periodicserviceDataUuid"] as String)),
                        it
                    )
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                    (arguments["periodicserviceSolicitationUuid"] as String?)?.let {
                        periodicAdvertiseData.addServiceSolicitationUuid(
                            ParcelUuid(UUID.fromString(it))
                        )
                    }

                (arguments["periodicserviceUuid"] as String?)?.let {
                    periodicAdvertiseData.addServiceUuid(
                        ParcelUuid(UUID.fromString(it))
                    )
                }
                //TODO: addTransportDiscoveryData
                (arguments["periodicincludeDeviceName"] as Boolean?)?.let {
                    periodicAdvertiseData.setIncludeDeviceName(
                        it
                    )
                }
                (arguments["periodictransmissionPowerIncluded"] as Boolean?)?.let {
                    periodicAdvertiseData.setIncludeTxPowerLevel(it)
                }

                (arguments["periodicsettingstransmissionPowerIncluded"] as Boolean?)?.let {
                    periodicAdvertiseDataSettings.setIncludeTxPower(it)
                }

                (arguments["periodicsettingsinterval"] as Int?)?.let {
                    periodicAdvertiseDataSettings.setInterval(it)
                }

            }

            var maxExtendedAdvertisingEvents = 0
            var duration = 0
            (arguments["setmaxExtendedAdvertisingEvents"] as Int?)?.let { maxExtendedAdvertisingEvents = it }
            (arguments["setduration"] as Int?)?.let { duration = it }

            advertisingSetCallback = PeripheralAdvertisingSetCallback(result, flutterBlePeripheralStateChangedHandler)

            // Extract serviceUuid and check if connectable to enable GATT server
            val serviceUuid = arguments["serviceUuid"] as String?
            val connectable = arguments["setconnectable"] as Boolean? ?: false
            val addGattService = connectable && serviceUuid != null

            flutterBlePeripheralManager!!.startSet(advertiseData.build(), advertiseSettingsSet.build(), advertiseResponseData?.build(), periodicAdvertiseData?.build(), periodicAdvertiseDataSettings?.build(),
                maxExtendedAdvertisingEvents, duration, advertisingSetCallback!!, serviceUuid, addGattService)
        } else {
            // Setup the advertiseSettings
            val advertiseSettings: AdvertiseSettings.Builder = AdvertiseSettings.Builder()

            (arguments["advertiseMode"] as Int?)?.let { advertiseSettings.setAdvertiseMode(it) }
            (arguments["connectable"] as Boolean?)?.let { advertiseSettings.setConnectable(it) }
            (arguments["timeout"] as Int?)?.let { advertiseSettings.setTimeout(it) }
            (arguments["txPowerLevel"] as Int?)?.let { advertiseSettings.setTxPowerLevel(it) }

            advertisingCallback = PeripheralAdvertisingCallback(result, flutterBlePeripheralStateChangedHandler)

            // Extract serviceUuid and check if connectable to enable GATT server
            val serviceUuid = arguments["serviceUuid"] as String?
            val connectable = arguments["connectable"] as Boolean? ?: false
            val addGattService = connectable && serviceUuid != null

            flutterBlePeripheralManager!!.start(advertiseData.build(), advertiseSettings.build(), advertiseResponseData?.build(), advertisingCallback!!, serviceUuid, addGattService)
        }
    }

    /**
     * Stop BLE scan if running.
     */
    private fun handleStop(result: MethodChannel.Result) {
        if (advertisingCallback != null) {
            flutterBlePeripheralManager?.stop(advertisingCallback!!)
        }

        if (advertisingSetCallback != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ) {
            flutterBlePeripheralManager?.stopSet(advertisingSetCallback!!)
        }
        safeResult(result) {
            result.success(FlutterBleBluetoothState.Ready.ordinal)
        }
    }

    /**
     * Check if device supports Bluetooth feature.
     */
    private fun handleIsSupported(result: MethodChannel.Result) {
        val isSupported = context?.packageManager?.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH)
        safeResult(result) {
            result.success(isSupported)
        }
    }

    private fun handleIsAdvertising(result: MethodChannel.Result) {
        safeResult(result) {
            result.success(flutterBlePeripheralStateChangedHandler.state == FlutterBlePeripheralState.advertising)
        }
    }

    private fun handleIsConnected(result: MethodChannel.Result) {
        val isConnected = flutterBlePeripheralStateChangedHandler.state == FlutterBlePeripheralState.connected
        safeResult(result) {
            Log.i(tag, "Is BLE connected: $isConnected")
            result.success(isConnected)
        }
    }
    
    /**
     * Request enabling Bluetooth.
     *
     * @param call Flutter method call with `shouldAsk` argument
     * @param result Method channel result callback
     */
    private fun handleEnableBluetooth(call: MethodCall, result: MethodChannel.Result) {
        if (activityBinding != null) {
            val shouldAsk = call.arguments as Boolean
            val isEnabled = flutterBlePeripheralManager!!.isBluetoothEnabled()
            if (!isEnabled) {
                if (shouldAsk) {
                    flutterBlePeripheralManager!!.enableBluetooth(activityBinding!!.activity) { bluetoothEnabled ->
                        safeResult(result) {
                            result.success(bluetoothEnabled)
                        }
                    }
                    return
                } else {
                    flutterBlePeripheralManager!!.enableBluetooth(activityBinding!!.activity, null)
                }
            }

            safeResult(result) {
                result.success(true)
            }
        } else {
            safeResult(result) {
                result.error("No activity", "FlutterBlePeripheral is not correctly initialized", "null")
            }
        }
    }

    /**
     * Request runtime Bluetooth permissions.
     */
    private fun handleRequestPermission(result: MethodChannel.Result) {
        val state = flutterBlePeripheralManager!!.requestPermission(activityBinding!!.activity) { state ->
            safeResult(result) {
                result.success(state.ordinal)
            }
        }

        // If already granted, return immediately
        if (state != null) {
            safeResult(result) {
                result.success(state.ordinal)
            }
        }
    }
    
    /**
     * Check if Bluetooth permissions are granted.
     */
    private fun handleHasPermission(result: MethodChannel.Result) {
        val permission = flutterBlePeripheralManager!!
            .requestPermission(activityBinding!!.activity, null)!!
            .ordinal
        safeResult(result) {
            result.success(permission)
        }
    }

    /**
     * Open system app settings for this application.
     */
    private fun handleOpenAppSettings(result: MethodChannel.Result) {
        activityBinding!!.activity.startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", context!!.packageName, null)
            )
        )
        safeResult(result) {
            result.success(null)
        }
    }

    /**
     * Open system Bluetooth settings.
     */
    private fun handleOpenBluetoothSettings(result: MethodChannel.Result) {
        activityBinding!!.activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS), null)
        safeResult(result) {
            result.success(null)
        }
    }

    /**
     * Handle unsupported or unknown method calls.
     */
    private fun handleNotImplemented(result: MethodChannel.Result) {
        safeResult(result) {
            result.notImplemented()
        }
    }
    
    /** Active advertising set callback, used for Android O+ advertising. */
    private var advertisingSetCallback: PeripheralAdvertisingSetCallback? = null

    /** Active advertising callback, used for legacy advertising. */
    private var advertisingCallback: PeripheralAdvertisingCallback? = null
    
    private fun handleSendData(call: MethodCall, result: MethodChannel.Result) {
        safeResult(result) {
            val data = call.arguments as? ByteArray
            if (data == null) {
                Log.e(tag, "Send data error: arguments is not ByteArray")
                result.error("INVALID_ARGUMENT", "Data must be a ByteArray", null)
                return@safeResult
            }

            if (flutterBlePeripheralManager == null) {
                Log.e(tag, "Send data error: manager is null")
                result.error("NOT_INITIALIZED", "FlutterBlePeripheralManager is not initialized", null)
                return@safeResult
            }

            Log.i(tag, "Trying to send ${data.size} bytes")
            val success = flutterBlePeripheralManager!!.sendData(data)

            if (success) {
                Log.i(tag, "Data sent successfully")
                result.success(null)
            } else {
                Log.w(tag, "Failed to send data")
                result.error("SEND_FAILED", "Failed to send data. GATT server may not be initialized or no devices connected", null)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == REQUEST_PERMISSION_BT) {
            val activity = activityBinding!!.activity

            var hasAllPermissions = true
            var shouldShowRationale = false

            for (i in permissions.indices) {
                val grantResult = grantResults[i]
                val permission = permissions[i]
                if (grantResult == PackageManager.PERMISSION_DENIED) {
                    hasAllPermissions = false
                    if (ActivityCompat.shouldShowRequestPermissionRationale(
                            activity,
                            permission
                        )
                    ) {
                        shouldShowRationale = true
                    }
                }
            }

            val resultState = when {
                hasAllPermissions -> {
                    flutterBlePeripheralManager?.setPermissionGranted(activity, true)
                    FlutterBleBluetoothState.Granted
                }
                shouldShowRationale -> {
                    flutterBlePeripheralManager?.setPermissionGranted(activity, false)
                    FlutterBleBluetoothState.Denied
                }
                else -> {
                    flutterBlePeripheralManager?.setPermissionGranted(activity, false)
                    FlutterBleBluetoothState.PermanentlyDenied
                }
            }

            flutterBlePeripheralManager?.permissionResultCallback?.invoke(resultState)
            flutterBlePeripheralManager?.permissionResultCallback = null
        }
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
        activityBinding = binding
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        flutterBlePeripheralManager?.permissionResultCallback?.invoke(FlutterBleBluetoothState.Denied)
        flutterBlePeripheralManager?.permissionResultCallback = null
        activityBinding = null
    }

    /**
     * Handle activity result from Bluetooth enable dialog.
     */
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ): Boolean {
        if (requestCode == REQUEST_ENABLE_BT) {
            flutterBlePeripheralManager?.bluetoothEnabledCallback?.invoke(resultCode == Activity.RESULT_OK)
            flutterBlePeripheralManager?.bluetoothEnabledCallback = null
        }
        return true
    }

    /**
     * Safely executes a [Result] callback on the main thread.
     *
     * Catches exceptions and reports them to Flutter.
     *
     * @param result The result callback to send responses to Flutter
     * @param block The action to perform
     */
    private fun safeResult(result: MethodChannel.Result, block: () -> Unit) {
        Handler(Looper.getMainLooper()).post {
            try {
                block()
            } catch (e: Exception) {
                result.error("UNEXPECTED_ERROR", e.message, null)
            }
        }
    }
}