// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'windows_advertise_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WindowsAdvertiseSettings _$WindowsAdvertiseSettingsFromJson(
        Map<String, dynamic> json) =>
    WindowsAdvertiseSettings(
      manufacturerData: const Uint8ListConverter()
          .fromJson(json['manufacturerData'] as List?),
      manufacturerId: (json['manufacturerId'] as num?)?.toInt(),
      flags: (json['flags'] as num?)?.toInt(),
      useExtendedAdvertisement:
          json['useExtendedAdvertisement'] as bool? ?? false,
      preferredTransmitPowerLevel:
          (json['preferredTransmitPowerLevel'] as num?)?.toInt(),
      includeTxPower: json['includeTxPower'] as bool? ?? false,
    );

Map<String, dynamic> _$WindowsAdvertiseSettingsToJson(
        WindowsAdvertiseSettings instance) =>
    <String, dynamic>{
      'manufacturerData':
          const Uint8ListConverter().toJson(instance.manufacturerData),
      'manufacturerId': instance.manufacturerId,
      'flags': instance.flags,
      'useExtendedAdvertisement': instance.useExtendedAdvertisement,
      'preferredTransmitPowerLevel': instance.preferredTransmitPowerLevel,
      'includeTxPower': instance.includeTxPower,
    };
