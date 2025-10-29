// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'android_advertise_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AndroidAdvertiseData _$AndroidAdvertiseDataFromJson(
        Map<String, dynamic> json) =>
    AndroidAdvertiseData(
      serviceUuid: json['serviceUuid'] as String?,
      serviceUuids: (json['serviceUuids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      localName: json['localName'] as String?,
      manufacturerId: (json['manufacturerId'] as num?)?.toInt(),
      manufacturerData: const Uint8ListConverter()
          .fromJson(json['manufacturerData'] as List?),
      serviceDataUuid: json['serviceDataUuid'] as String?,
      serviceData: (json['serviceData'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      includeDeviceName: json['includeDeviceName'] as bool? ?? false,
      transmissionPowerIncluded:
          json['transmissionPowerIncluded'] as bool? ?? false,
      serviceSolicitationUuid: json['serviceSolicitationUuid'] as String?,
    );

Map<String, dynamic> _$AndroidAdvertiseDataToJson(
        AndroidAdvertiseData instance) =>
    <String, dynamic>{
      'serviceUuid': instance.serviceUuid,
      'serviceUuids': instance.serviceUuids,
      'localName': instance.localName,
      'manufacturerId': instance.manufacturerId,
      'manufacturerData':
          const Uint8ListConverter().toJson(instance.manufacturerData),
      'serviceDataUuid': instance.serviceDataUuid,
      'serviceData': instance.serviceData,
      'includeDeviceName': instance.includeDeviceName,
      'transmissionPowerIncluded': instance.transmissionPowerIncluded,
      'serviceSolicitationUuid': instance.serviceSolicitationUuid,
    };
