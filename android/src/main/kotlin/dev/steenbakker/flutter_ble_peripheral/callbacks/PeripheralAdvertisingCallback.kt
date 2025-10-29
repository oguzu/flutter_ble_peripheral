package dev.steenbakker.flutter_ble_peripheral.callbacks

import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseSettings
import dev.steenbakker.flutter_ble_peripheral.handlers.FlutterBlePeripheralStateChangedHandler
import dev.steenbakker.flutter_ble_peripheral.models.FlutterBlePeripheralState
import io.flutter.Log
import io.flutter.plugin.common.MethodChannel

class PeripheralAdvertisingCallback(private val result: MethodChannel.Result, private val flutterBlePeripheralStateChangedHandler: FlutterBlePeripheralStateChangedHandler): AdvertiseCallback() {
    override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
        super.onStartSuccess(settingsInEffect)
        Log.i("FlutterBlePeripheral", "onStartSuccess() mode: ${settingsInEffect.mode}, txPOWER ${settingsInEffect.txPowerLevel}")
        result.success(null)
        flutterBlePeripheralStateChangedHandler.publish(FlutterBlePeripheralState.advertising)
    }

    override fun onStartFailure(errorCode: Int) {
        super.onStartFailure(errorCode)
        val statusText: String
        when (errorCode) {
            ADVERTISE_FAILED_ALREADY_STARTED -> {
                statusText = "ADVERTISE_FAILED_ALREADY_STARTED"
                flutterBlePeripheralStateChangedHandler.publish(FlutterBlePeripheralState.advertising)
            }
            ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> {
                statusText = "ADVERTISE_FAILED_FEATURE_UNSUPPORTED"
                flutterBlePeripheralStateChangedHandler.publish(FlutterBlePeripheralState.unsupported)
            }
            ADVERTISE_FAILED_INTERNAL_ERROR -> {
                statusText = "ADVERTISE_FAILED_INTERNAL_ERROR"
                flutterBlePeripheralStateChangedHandler.publish(FlutterBlePeripheralState.idle)
            }
            ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> {
                statusText = "ADVERTISE_FAILED_TOO_MANY_ADVERTISERS"
                flutterBlePeripheralStateChangedHandler.publish(FlutterBlePeripheralState.idle)
            }
            ADVERTISE_FAILED_DATA_TOO_LARGE -> {
                statusText = "ADVERTISE_FAILED_DATA_TOO_LARGE"
                flutterBlePeripheralStateChangedHandler.publish(FlutterBlePeripheralState.idle)
            }
            else -> {
                statusText = "UNDOCUMENTED"
                flutterBlePeripheralStateChangedHandler.publish(FlutterBlePeripheralState.unknown)
            }
        }
        result.error(errorCode.toString(), statusText, "startAdvertising")
    }
}