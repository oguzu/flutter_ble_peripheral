import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

class BleStatusScreen extends StatelessWidget {
  const BleStatusScreen({required this.status, super.key});

  final FlutterBlePeripheralState status;
  // idle, advertising, connected, unsupported, unauthorized }
  String determineText(FlutterBlePeripheralState status) {
    switch (status) {
      case FlutterBlePeripheralState.unsupported:
        return "This device does not support Bluetooth";
      case FlutterBlePeripheralState.unauthorized:
        return "Authorize the BlePeripheral example app to use Bluetooth and location";
      case FlutterBlePeripheralState.poweredOff:
        return "Bluetooth is powered off on your device turn it on";
      // case PeripheralState.unauthorized:
      //   return "Enable location services";
      case FlutterBlePeripheralState.idle:
        return "Bluetooth is up and running";
      default:
        return "Waiting to fetch Bluetooth status $status";
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Text(determineText(status)),
        ),
      );
}
