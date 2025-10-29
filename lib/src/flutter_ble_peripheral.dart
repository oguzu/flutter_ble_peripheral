/*
 * Copyright (c) 2022. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'dart:async';
import 'dart:io';
// ignore: unnecessary_import
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_ble_peripheral/src/core/enums/flutter_ble_bluetooth_state.dart';
import 'package:flutter_ble_peripheral/src/core/models/advertise_data.dart';
import 'package:flutter_ble_peripheral/src/core/models/advertise_data_core.dart';
import 'package:flutter_ble_peripheral/src/platform/android/enums/flutter_ble_peripheral_state.dart';
import 'package:flutter_ble_peripheral/src/platform/android/models/android_advertise_data.dart';
import 'package:flutter_ble_peripheral/src/platform/android/models/android_advertise_settings.dart';
import 'package:flutter_ble_peripheral/src/platform/darwin/models/darwin_advertise_settings.dart';
import 'package:flutter_ble_peripheral/src/platform/windows/models/windows_advertise_settings.dart';

class FlutterBlePeripheral {
  /// Singleton instance
  static final FlutterBlePeripheral _instance =
      FlutterBlePeripheral._internal();

  /// Singleton factory
  factory FlutterBlePeripheral() {
    return _instance;
  }

  /// Singleton constructor
  FlutterBlePeripheral._internal();

  /// Method Channel used to communicate state with
  static const MethodChannel _methodChannel =
      MethodChannel('dev.steenbakker.flutter_ble_peripheral/ble_state');

  /// Event Channel for MTU state
  final EventChannel _mtuChangedEventChannel = const EventChannel(
    'dev.steenbakker.flutter_ble_peripheral/ble_mtu_changed',
  );

  /// Event Channel used to changed state
  final EventChannel _stateChangedEventChannel = const EventChannel(
    'dev.steenbakker.flutter_ble_peripheral/ble_state_changed',
  );

  /// Event Channel used to receive data
  final EventChannel _dataReceivedEventChannel = const EventChannel(
    'dev.steenbakker.flutter_ble_peripheral/ble_data_received',
  );

  Stream<int>? _mtuState;
  Stream<FlutterBlePeripheralState>? _peripheralState;
  Stream<Uint8List>? _dataReceived;

  /// Start advertising.
  ///
  /// [advertiseData] - Core advertising data. Use [AdvertiseDataCore] for cross-platform,
  /// or platform-specific classes like [AndroidAdvertiseData] for platform features.
  ///
  /// Platform-specific settings:
  /// - Android: [androidSettings]
  /// - iOS/macOS: [darwinSettings]
  /// - Windows: [windowsSettings]
  ///
  /// For backward compatibility, also accepts legacy [AdvertiseData] (deprecated).
  Future<FlutterBleBluetoothState> start({
    required AdvertiseDataCore advertiseData,

    // Platform-specific settings
    AndroidAdvertiseSettings? androidSettings,
    DarwinAdvertiseSettings? darwinSettings,
    WindowsAdvertiseSettings? windowsSettings,
  }) async {
    final parameters = advertiseData.toJson();

    // Handle Android-specific manufacturer data
    if (advertiseData is AndroidAdvertiseData) {
      // Android-specific manufacturer data
      final androidData = advertiseData as AndroidAdvertiseData;
      parameters["manufacturerDataBytes"] = androidData.manufacturerData;
    } else if (advertiseData is AdvertiseData) {
      // Legacy support for deprecated AdvertiseData
      final legacyData = advertiseData as AdvertiseData;
      parameters["manufacturerDataBytes"] = legacyData.manufacturerData;
    }

    if (advertiseData.serviceUuids != null) {
      parameters['serviceUuids'] = advertiseData.serviceUuids;
    }

    // Android settings
    if (Platform.isAndroid && androidSettings != null) {
      // Automatically set advertiseSet flag based on which parameters are provided
      final useExtendedAdvertising = androidSettings.advertiseSetParameters != null;
      parameters['advertiseSet'] = useExtendedAdvertising;

      // Legacy advertising settings
      if (androidSettings.advertiseSettings != null) {
        final json = androidSettings.advertiseSettings!.toJson();
        for (final key in json.keys) {
          parameters[key] = json[key];
        }
      }

      // Extended advertising parameters (advertiseSetParameters)
      if (androidSettings.advertiseSetParameters != null) {
        final json = androidSettings.advertiseSetParameters!.toJson();
        for (final key in json.keys) {
          parameters['set$key'] = json[key];
        }
      }

      // Scan response data (advertiseResponseData)
      if (androidSettings.advertiseResponseData != null) {
        final responseData = androidSettings.advertiseResponseData!;
        final json = responseData.toJson();
        for (final key in json.keys) {
          parameters['response$key'] = json[key];
        }

        // Handle manufacturer data bytes separately for response data
        if (responseData.manufacturerData != null) {
          parameters['responsemanufacturerDataBytes'] = responseData.manufacturerData;
        }
      }

      // Periodic advertising data
      if (androidSettings.periodicAdvertiseData != null) {
        final periodicData = androidSettings.periodicAdvertiseData!;
        final json = periodicData.toJson();
        for (final key in json.keys) {
          parameters['periodicData$key'] = json[key];
        }

        // Handle manufacturer data bytes separately for periodic data
        if (periodicData.manufacturerData != null) {
          parameters['periodicDatamanufacturerDataBytes'] = periodicData.manufacturerData;
        }
      }

      // Periodic advertising settings
      if (androidSettings.periodicAdvertiseSettings != null) {
        final json = androidSettings.periodicAdvertiseSettings!.toJson();
        for (final key in json.keys) {
          parameters['periodicsettings$key'] = json[key];
        }
      }
    }

    // Darwin (iOS/macOS) settings
    if ((Platform.isIOS || Platform.isMacOS) && darwinSettings != null) {
      final darwinJson = darwinSettings.toJson();
      for (final key in darwinJson.keys) {
        parameters['darwin$key'] = darwinJson[key];
      }

      // Convert manufacturer data if present
      if (darwinSettings.manufacturerData != null) {
        parameters['darwinManufacturerDataBytes'] =
            darwinSettings.manufacturerData;
      }

      // Convert service data dictionary if present
      if (darwinSettings.serviceData != null) {
        final serviceDataMap = <String, dynamic>{};
        darwinSettings.serviceData!.forEach((uuid, data) {
          serviceDataMap[uuid] = data;
        });
        parameters['darwinServiceDataMap'] = serviceDataMap;
      }
    }

    // Windows settings
    if (Platform.isWindows && windowsSettings != null) {
      final windowsJson = windowsSettings.toJson();
      for (final key in windowsJson.keys) {
        parameters['windows$key'] = windowsJson[key];
      }

      // Convert manufacturer data if present
      if (windowsSettings.manufacturerData != null) {
        parameters['windowsManufacturerDataBytes'] =
            windowsSettings.manufacturerData;
      }
    }

    final response =
        await _methodChannel.invokeMethod<int>('start', parameters);
    return response == null
        ? FlutterBleBluetoothState.unknown
        : FlutterBleBluetoothState.values[response];
  }

  /// Stop advertising
  Future<FlutterBleBluetoothState> stop() async {
    final response = await _methodChannel.invokeMethod<int>('stop');
    return response == null
        ? FlutterBleBluetoothState.unknown
        : FlutterBleBluetoothState.values[response];
  }

  /// Returns `true` if advertising or false if not advertising
  Future<bool> get isAdvertising async {
    return await _methodChannel.invokeMethod<bool>('isAdvertising') ?? false;
  }

  /// Returns `true` if advertising over BLE is supported
  Future<bool> get isSupported async =>
      await _methodChannel.invokeMethod<bool>('isSupported') ?? false;

  /// Returns `true` if device is connected
  Future<bool> get isConnected async =>
      await _methodChannel.invokeMethod<bool>('isConnected') ?? false;

  /// Start advertising. Takes [AdvertiseData] as an input.
  Future<void> sendData(Uint8List data) async {
    await _methodChannel.invokeMethod('sendData', data);
  }

  /// Stop advertising
  ///
  /// [askUser] ONLY AVAILABLE ON ANDROID SDK < 33
  /// If set to false, it will enable bluetooth without asking user.
  Future<bool> enableBluetooth({bool askUser = true}) async {
    if (!Platform.isAndroid) return false;
    return await _methodChannel.invokeMethod<bool>(
          'enableBluetooth',
          askUser,
        ) ??
        false;
  }

  Future<FlutterBleBluetoothState> requestPermission() async {
    final response =
        await _methodChannel.invokeMethod<int>('requestPermission');
    return response == null
        ? FlutterBleBluetoothState.unknown
        : FlutterBleBluetoothState.values[response];
  }

  Future<FlutterBleBluetoothState> hasPermission() async {
    final response = await _methodChannel.invokeMethod<int>('hasPermission');
    return response == null
        ? FlutterBleBluetoothState.unknown
        : FlutterBleBluetoothState.values[response];
  }

  Future<void> openBluetoothSettings() async {
    await _methodChannel.invokeMethod('openBluetoothSettings');
  }

  Future<void> openAppSettings() async {
    await _methodChannel.invokeMethod('openAppSettings');
  }

  /// Returns Stream of MTU updates.
  Stream<int> get onMtuChanged {
    _mtuState ??= _mtuChangedEventChannel
        .receiveBroadcastStream()
        .cast<int>()
        .distinct()
        .map((dynamic event) => event as int);
    return _mtuState!;
  }

  /// Returns Stream of state.
  ///
  /// After listening to this Stream, you'll be notified about changes in peripheral state.
  Stream<FlutterBlePeripheralState>? get onPeripheralStateChanged {
    if (Platform.isWindows) return null;
    _peripheralState ??= _stateChangedEventChannel
        .receiveBroadcastStream()
        .map((dynamic event) => FlutterBlePeripheralState.values[event as int]);
    return _peripheralState!;
  }

  /// Returns Stream of data received from connected centrals.
  ///
  /// After listening to this Stream, you'll be notified when data is written
  /// to the RX characteristic by a connected central device.
  Stream<Uint8List> get onDataReceived {
    _dataReceived ??= _dataReceivedEventChannel
        .receiveBroadcastStream()
        .map((dynamic event) => event as Uint8List);
    return _dataReceived!;
  }
}
