// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'advertise_data_core.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdvertiseDataCore _$AdvertiseDataCoreFromJson(Map<String, dynamic> json) =>
    AdvertiseDataCore(
      serviceUuid: json['serviceUuid'] as String?,
      serviceUuids: (json['serviceUuids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      localName: json['localName'] as String?,
    );

Map<String, dynamic> _$AdvertiseDataCoreToJson(AdvertiseDataCore instance) =>
    <String, dynamic>{
      'serviceUuid': instance.serviceUuid,
      'serviceUuids': instance.serviceUuids,
      'localName': instance.localName,
    };
