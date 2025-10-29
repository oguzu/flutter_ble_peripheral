/*
 * Copyright (c) 2020. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'dart:typed_data';

import 'package:flutter_ble_peripheral/src/core/models/advertise_data_core.dart';
import 'package:flutter_ble_peripheral/src/core/utils/uint8list_converter.dart';
import 'package:json_annotation/json_annotation.dart';

part 'android_advertise_data.g.dart';

/// Android-specific advertising data model.
///
/// This class extends [AdvertiseDataCore] with Android-specific fields
/// that map directly to Android's `AdvertiseData.Builder` API.
///
/// For Android advertising settings (mode, timeout, tx power), use [AdvertiseSettings].
/// For extended advertising (Android 8+), use [AdvertiseSetParameters].
@JsonSerializable()
class AndroidAdvertiseData extends AdvertiseDataCore {
  /// Specifies a manufacturer ID.
  ///
  /// Manufacturer ID assigned by Bluetooth SIG.
  /// Must be used together with [manufacturerData].
  ///
  /// Android API: `AdvertiseData.Builder.addManufacturerData(manufacturerId, data)`
  final int? manufacturerId;

  /// Specifies manufacturer-specific data.
  ///
  /// Must be used together with [manufacturerId].
  /// Maximum length: 27 bytes (for legacy advertising).
  ///
  /// Android API: `AdvertiseData.Builder.addManufacturerData(manufacturerId, data)`
  @Uint8ListConverter()
  final Uint8List? manufacturerData;

  /// Specifies service data UUID.
  ///
  /// Must be used together with [serviceData].
  ///
  /// Android API: `AdvertiseData.Builder.addServiceData(serviceDataUuid, serviceData)`
  final String? serviceDataUuid;

  /// Specifies service data payload.
  ///
  /// Must be used together with [serviceDataUuid].
  ///
  /// Android API: `AdvertiseData.Builder.addServiceData(serviceDataUuid, serviceData)`
  final List<int>? serviceData;

  /// Set to true if device name needs to be included with advertisement.
  ///
  /// Default: false
  ///
  /// Note: Including the device name reduces the available space for other data.
  /// On Android, the default device name is typically the device model.
  ///
  /// Android API: `AdvertiseData.Builder.setIncludeDeviceName(includeDeviceName)`
  final bool includeDeviceName;

  /// Set to true if you want to include the TX power level in the advertisement.
  ///
  /// Default: false
  ///
  /// The TX power level helps receivers estimate the distance to the advertiser.
  /// Including this reduces available space for other advertising data.
  ///
  /// Android API: `AdvertiseData.Builder.setIncludeTxPowerLevel(transmissionPowerIncluded)`
  final bool transmissionPowerIncluded;

  /// A service solicitation UUID to advertise.
  ///
  /// Android SDK 31 (Android 12) and above only.
  ///
  /// Service solicitation UUIDs indicate which services the peripheral
  /// is interested in connecting to, which can improve discovery performance.
  ///
  /// Android API: `AdvertiseData.Builder.addServiceSolicitationUuid(parcelUuid)`
  final String? serviceSolicitationUuid;

  const AndroidAdvertiseData({
    // Core fields
    super.serviceUuid,
    super.serviceUuids,
    super.localName,
    // Android-specific fields
    this.manufacturerId,
    this.manufacturerData,
    this.serviceDataUuid,
    this.serviceData,
    this.includeDeviceName = false,
    this.transmissionPowerIncluded = false,
    this.serviceSolicitationUuid,
  });

  factory AndroidAdvertiseData.fromJson(Map<String, dynamic> json) =>
      _$AndroidAdvertiseDataFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$AndroidAdvertiseDataToJson(this);

  /// Creates a copy with optional field replacements
  @override
  AndroidAdvertiseData copyWith({
    String? serviceUuid,
    List<String>? serviceUuids,
    String? localName,
    int? manufacturerId,
    Uint8List? manufacturerData,
    String? serviceDataUuid,
    List<int>? serviceData,
    bool? includeDeviceName,
    bool? transmissionPowerIncluded,
    String? serviceSolicitationUuid,
  }) {
    return AndroidAdvertiseData(
      serviceUuid: serviceUuid ?? this.serviceUuid,
      serviceUuids: serviceUuids ?? this.serviceUuids,
      localName: localName ?? this.localName,
      manufacturerId: manufacturerId ?? this.manufacturerId,
      manufacturerData: manufacturerData ?? this.manufacturerData,
      serviceDataUuid: serviceDataUuid ?? this.serviceDataUuid,
      serviceData: serviceData ?? this.serviceData,
      includeDeviceName: includeDeviceName ?? this.includeDeviceName,
      transmissionPowerIncluded:
          transmissionPowerIncluded ?? this.transmissionPowerIncluded,
      serviceSolicitationUuid:
          serviceSolicitationUuid ?? this.serviceSolicitationUuid,
    );
  }

  /// Creates an AndroidAdvertiseData from a core AdvertiseDataCore instance
  factory AndroidAdvertiseData.fromCore(AdvertiseDataCore core) {
    return AndroidAdvertiseData(
      serviceUuid: core.serviceUuid,
      serviceUuids: core.serviceUuids,
      localName: core.localName,
    );
  }
}
