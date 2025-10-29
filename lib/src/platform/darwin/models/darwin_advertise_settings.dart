/*
 * Copyright (c) 2020. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'dart:typed_data';

import 'package:flutter_ble_peripheral/src/core/utils/uint8list_converter.dart';
import 'package:flutter_ble_peripheral/src/core/utils/uint8list_map_string_converter.dart';
import 'package:json_annotation/json_annotation.dart';

part 'darwin_advertise_settings.g.dart';

/// Darwin (iOS/macOS) specific advertising settings.
///
/// This class maps to CoreBluetooth's CBPeripheralManager advertising options.
/// These settings are passed to `peripheralManager.startAdvertising(_:)`
///
/// Reference: https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager
@JsonSerializable()
class DarwinAdvertiseSettings {
  /// Manufacturer-specific data.
  ///
  /// Maps to `CBAdvertisementDataManufacturerDataKey`.
  ///
  /// The first two bytes of the data should be the manufacturer identifier
  /// (little-endian), followed by manufacturer-specific data.
  ///
  /// Example:
  /// ```dart
  /// // Apple Inc. manufacturer ID (0x004C)
  /// final data = Uint8List.fromList([0x4C, 0x00, 0x01, 0x02, 0x03]);
  /// ```
  @Uint8ListConverter()
  final Uint8List? manufacturerData;

  /// Service data dictionary.
  ///
  /// Maps to `CBAdvertisementDataServiceDataKey`.
  ///
  /// A dictionary where:
  /// - Keys: Service UUID strings
  /// - Values: Service-specific data as Uint8List
  ///
  /// Example:
  /// ```dart
  /// final serviceData = {
  ///   "180F": Uint8List.fromList([0x64]), // Battery Service: 100%
  /// };
  /// ```
  @Uint8ListMapStringConverter()
  final Map<String, Uint8List>? serviceData;

  /// Overflow service UUIDs.
  ///
  /// Maps to `CBAdvertisementDataOverflowServiceUUIDsKey`.
  ///
  /// Service UUIDs that don't fit in the main advertisement packet
  /// but should still be discoverable via a scan response.
  ///
  /// iOS automatically handles overflow for you in most cases.
  final List<String>? overflowServiceUuids;

  /// Solicited service UUIDs.
  ///
  /// Maps to `CBAdvertisementDataSolicitedServiceUUIDsKey`.
  ///
  /// Service UUIDs that this peripheral is interested in connecting to.
  /// This can help centrals prioritize discovery based on their services.
  ///
  /// This is useful when the peripheral wants to connect to centrals
  /// that provide specific services.
  final List<String>? solicitedServiceUuids;

  /// Whether the peripheral is connectable.
  ///
  /// Platform-specific behavior:
  /// - iOS: Maps to `CBAdvertisementDataIsConnectable` (NSNumber with boolean)
  ///   - If null or true: Advertisement is connectable (default behavior)
  ///   - If false: Advertisement is non-connectable (beacon mode)
  /// - macOS: This option may not be available on all macOS versions
  ///
  /// Note: When set to false, the peripheral acts as a beacon and
  /// cannot accept connections. This is useful for broadcast-only scenarios.
  ///
  /// Default: true (connectable)
  final bool? isConnectable;

  /// Show a power alert if Bluetooth is off when starting advertising.
  ///
  /// Maps to `CBPeripheralManagerOptionShowPowerAlertKey`.
  ///
  /// If true and Bluetooth is powered off, the system will show
  /// an alert to the user when attempting to start advertising.
  ///
  /// Default: true
  final bool showPowerAlert;

  /// Restore identifier for state restoration.
  ///
  /// Maps to `CBPeripheralManagerOptionRestoreIdentifierKey`.
  ///
  /// If provided, the system will preserve the peripheral manager's state
  /// and restore it when the app is relaunched in the background.
  ///
  /// This is required for background advertising on iOS.
  ///
  /// Example: `"com.yourapp.peripheral"`
  final String? restoreIdentifier;

  const DarwinAdvertiseSettings({
    this.manufacturerData,
    this.serviceData,
    this.overflowServiceUuids,
    this.solicitedServiceUuids,
    this.isConnectable = true,
    this.showPowerAlert = true,
    this.restoreIdentifier,
  });

  factory DarwinAdvertiseSettings.fromJson(Map<String, dynamic> json) =>
      _$DarwinAdvertiseSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$DarwinAdvertiseSettingsToJson(this);

  /// Creates a copy with optional field replacements
  DarwinAdvertiseSettings copyWith({
    Uint8List? manufacturerData,
    Map<String, Uint8List>? serviceData,
    List<String>? overflowServiceUuids,
    List<String>? solicitedServiceUuids,
    bool? isConnectable,
    bool? showPowerAlert,
    String? restoreIdentifier,
  }) {
    return DarwinAdvertiseSettings(
      manufacturerData: manufacturerData ?? this.manufacturerData,
      serviceData: serviceData ?? this.serviceData,
      overflowServiceUuids: overflowServiceUuids ?? this.overflowServiceUuids,
      solicitedServiceUuids:
          solicitedServiceUuids ?? this.solicitedServiceUuids,
      isConnectable: isConnectable ?? this.isConnectable,
      showPowerAlert: showPowerAlert ?? this.showPowerAlert,
      restoreIdentifier: restoreIdentifier ?? this.restoreIdentifier,
    );
  }

  /// Converts this settings object to a dictionary suitable for
  /// CBPeripheralManager.startAdvertising(_:)
  ///
  /// This is used by the native iOS/macOS implementation.
  Map<String, dynamic> toAdvertisementData() {
    final data = <String, dynamic>{};

    if (manufacturerData != null) {
      data['CBAdvertisementDataManufacturerDataKey'] = manufacturerData;
    }

    if (serviceData != null && serviceData!.isNotEmpty) {
      data['CBAdvertisementDataServiceDataKey'] = serviceData;
    }

    if (overflowServiceUuids != null && overflowServiceUuids!.isNotEmpty) {
      data['CBAdvertisementDataOverflowServiceUUIDsKey'] =
          overflowServiceUuids;
    }

    if (solicitedServiceUuids != null && solicitedServiceUuids!.isNotEmpty) {
      data['CBAdvertisementDataSolicitedServiceUUIDsKey'] =
          solicitedServiceUuids;
    }

    if (isConnectable != null) {
      data['CBAdvertisementDataIsConnectable'] = isConnectable;
    }

    return data;
  }

  /// Converts this settings object to peripheral manager options
  /// suitable for CBPeripheralManager initialization.
  Map<String, dynamic> toPeripheralManagerOptions() {
    final options = <String, dynamic>{};

    options['CBPeripheralManagerOptionShowPowerAlertKey'] = showPowerAlert;

    if (restoreIdentifier != null) {
      options['CBPeripheralManagerOptionRestoreIdentifierKey'] =
          restoreIdentifier;
    }

    return options;
  }
}
