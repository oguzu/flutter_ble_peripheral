/*
 * Copyright (c) 2020. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'dart:typed_data';

import 'package:flutter_ble_peripheral/src/core/utils/uint8list_converter.dart';
import 'package:json_annotation/json_annotation.dart';

part 'windows_advertise_settings.g.dart';

/// Windows-specific advertising settings.
///
/// This class maps to Windows Runtime's BluetoothLEAdvertisement API.
/// These settings are used with BluetoothLEAdvertisementPublisher.
///
/// Reference: https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.advertisement.bluetoothleadvertisement
@JsonSerializable()
class WindowsAdvertiseSettings {
  /// Manufacturer-specific data.
  ///
  /// The manufacturer data consists of a company identifier and data payload.
  /// Use [manufacturerId] to specify the company ID (assigned by Bluetooth SIG).
  ///
  /// Maps to `BluetoothLEManufacturerData.Data`
  @Uint8ListConverter()
  final Uint8List? manufacturerData;

  /// Manufacturer identifier.
  ///
  /// Company identifier assigned by Bluetooth SIG.
  /// Must be used together with [manufacturerData].
  ///
  /// Maps to `BluetoothLEManufacturerData.CompanyId`
  final int? manufacturerId;

  /// Bluetooth LE advertisement flags.
  ///
  /// Flags control the discoverability and capability modes.
  ///
  /// Common flag values:
  /// - 0x01: LE Limited Discoverable Mode
  /// - 0x02: LE General Discoverable Mode
  /// - 0x04: BR/EDR Not Supported
  /// - 0x08: Simultaneous LE and BR/EDR Controller
  /// - 0x10: Simultaneous LE and BR/EDR Host
  ///
  /// Maps to `BluetoothLEAdvertisement.Flags`
  final int? flags;

  /// Use extended advertisement format.
  ///
  /// If true, uses the extended advertisement format which allows:
  /// - Larger data payloads
  /// - Better performance with multiple concurrent advertisements
  /// - Support for advertising on secondary PHY channels
  ///
  /// Requires Windows 10 version 1809 (Build 17763) or later.
  ///
  /// Default: false
  final bool useExtendedAdvertisement;

  /// Preferred transmission power level in dBm.
  ///
  /// This is a hint to the system about the desired transmission power.
  /// Actual power used may differ based on hardware capabilities.
  ///
  /// Typical values:
  /// - High: 4 dBm
  /// - Medium: 0 dBm
  /// - Low: -10 dBm
  /// - Ultra Low: -20 dBm
  ///
  /// Default: null (system decides)
  final int? preferredTransmitPowerLevel;

  /// Whether to include the TX power level in the advertisement.
  ///
  /// If true, the transmission power level will be included in the
  /// advertisement data, which helps receivers estimate distance.
  ///
  /// Default: false
  final bool includeTxPower;

  const WindowsAdvertiseSettings({
    this.manufacturerData,
    this.manufacturerId,
    this.flags,
    this.useExtendedAdvertisement = false,
    this.preferredTransmitPowerLevel,
    this.includeTxPower = false,
  });

  factory WindowsAdvertiseSettings.fromJson(Map<String, dynamic> json) =>
      _$WindowsAdvertiseSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$WindowsAdvertiseSettingsToJson(this);

  /// Creates a copy with optional field replacements
  WindowsAdvertiseSettings copyWith({
    Uint8List? manufacturerData,
    int? manufacturerId,
    int? flags,
    bool? useExtendedAdvertisement,
    int? preferredTransmitPowerLevel,
    bool? includeTxPower,
  }) {
    return WindowsAdvertiseSettings(
      manufacturerData: manufacturerData ?? this.manufacturerData,
      manufacturerId: manufacturerId ?? this.manufacturerId,
      flags: flags ?? this.flags,
      useExtendedAdvertisement:
          useExtendedAdvertisement ?? this.useExtendedAdvertisement,
      preferredTransmitPowerLevel:
          preferredTransmitPowerLevel ?? this.preferredTransmitPowerLevel,
      includeTxPower: includeTxPower ?? this.includeTxPower,
    );
  }
}
