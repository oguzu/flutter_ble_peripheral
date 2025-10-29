// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'darwin_advertise_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DarwinAdvertiseSettings _$DarwinAdvertiseSettingsFromJson(
        Map<String, dynamic> json) =>
    DarwinAdvertiseSettings(
      manufacturerData: const Uint8ListConverter()
          .fromJson(json['manufacturerData'] as List?),
      serviceData: const Uint8ListMapStringConverter()
          .fromJson(json['serviceData'] as Map<String, dynamic>?),
      overflowServiceUuids: (json['overflowServiceUuids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      solicitedServiceUuids: (json['solicitedServiceUuids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      isConnectable: json['isConnectable'] as bool? ?? true,
      showPowerAlert: json['showPowerAlert'] as bool? ?? true,
      restoreIdentifier: json['restoreIdentifier'] as String?,
    );

Map<String, dynamic> _$DarwinAdvertiseSettingsToJson(
        DarwinAdvertiseSettings instance) =>
    <String, dynamic>{
      'manufacturerData':
          const Uint8ListConverter().toJson(instance.manufacturerData),
      'serviceData':
          const Uint8ListMapStringConverter().toJson(instance.serviceData),
      'overflowServiceUuids': instance.overflowServiceUuids,
      'solicitedServiceUuids': instance.solicitedServiceUuids,
      'isConnectable': instance.isConnectable,
      'showPowerAlert': instance.showPowerAlert,
      'restoreIdentifier': instance.restoreIdentifier,
    };
