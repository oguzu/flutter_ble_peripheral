/*
 * Copyright (c) 2020. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'package:json_annotation/json_annotation.dart';

part 'advertise_data_core.g.dart';

/// Core cross-platform advertising data model.
///
/// This class contains only the fields that are supported across all platforms
/// (Android, iOS/macOS, Windows). For platform-specific settings, use the
/// corresponding platform settings classes:
/// - Android: [AndroidAdvertiseData], [AdvertiseSettings], [AdvertiseSetParameters]
/// - iOS/macOS: [DarwinAdvertiseSettings]
/// - Windows: [WindowsAdvertiseSettings]
@JsonSerializable()
class AdvertiseDataCore {
  /// Specifies a single service UUID to be advertised.
  ///
  /// Supported on all platforms.
  /// If [serviceUuids] is specified, this field may be ignored depending on platform.
  final String? serviceUuid;

  /// Specifies multiple service UUIDs to be advertised.
  ///
  /// Supported on all platforms:
  /// - iOS/macOS: Full support for multiple UUIDs
  /// - Android: Limited support (use [serviceUuid] for better compatibility)
  /// - Windows: Check platform documentation
  ///
  /// If specified, [serviceUuid] may be used as fallback on some platforms.
  final List<String>? serviceUuids;

  /// The local name to broadcast.
  ///
  /// Platform-specific behavior:
  /// - iOS/macOS: Sets CBAdvertisementDataLocalNameKey (max 10 bytes recommended)
  /// - Android: Use [AndroidAdvertiseData.includeDeviceName] instead
  /// - Windows: Sets the local name in advertisement
  final String? localName;

  const AdvertiseDataCore({
    this.serviceUuid,
    this.serviceUuids,
    this.localName,
  });

  factory AdvertiseDataCore.fromJson(Map<String, dynamic> json) =>
      _$AdvertiseDataCoreFromJson(json);

  Map<String, dynamic> toJson() => _$AdvertiseDataCoreToJson(this);

  /// Creates a copy with optional field replacements
  AdvertiseDataCore copyWith({
    String? serviceUuid,
    List<String>? serviceUuids,
    String? localName,
  }) {
    return AdvertiseDataCore(
      serviceUuid: serviceUuid ?? this.serviceUuid,
      serviceUuids: serviceUuids ?? this.serviceUuids,
      localName: localName ?? this.localName,
    );
  }
}
