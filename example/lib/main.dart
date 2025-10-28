/*
 * Copyright (c) 2020. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

// ignore: unnecessary_import
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

void main() => runApp(const FlutterBlePeripheralExample());

class FlutterBlePeripheralExample extends StatefulWidget {
  const FlutterBlePeripheralExample({super.key});

  @override
  FlutterBlePeripheralExampleState createState() =>
      FlutterBlePeripheralExampleState();
}

class FlutterBlePeripheralExampleState
    extends State<FlutterBlePeripheralExample> {
  final AdvertiseData advertiseData = AdvertiseData(
    serviceUuid: 'bf27730d-860a-4e09-889c-2d8b6a9e0fe7',
    // serviceUuids: ['ffffffff-ffff-ffff-ffff-ffffffffffff'],
    localName: 'FlutterBLE',
    manufacturerId: 1234,
    manufacturerData: Uint8List.fromList([1, 2, 3, 4, 5, 6]),
  );

  // final advertiseSettings = AdvertiseSettings(
  //   advertiseMode: AdvertiseMode.advertiseModeBalanced,
  //   txPowerLevel: AdvertiseTxPower.advertiseTxPowerMedium,
  //   timeout: 3000,
  // );

  final AdvertiseSetParameters advertiseSetParameters =
      AdvertiseSetParameters();

  bool _isSupported = false;
  String _lastReceivedData = 'None';
  int _currentMtu = 23; // Default MTU
  int _messageCounter = 0;

  @override
  void initState() {
    super.initState();
    initPlatformState();

    // Listen to data received
    FlutterBlePeripheral().onDataReceived.listen((data) {
      setState(() {
        _lastReceivedData = 'Bytes: ${data.length}, Data: ${_formatBytes(data)}';
      });
      if (kDebugMode) {
        print('Received data: $data');
      }
    });

    // Listen to MTU changes
    FlutterBlePeripheral().onMtuChanged.listen((mtu) {
      setState(() {
        _currentMtu = mtu;
      });
      if (kDebugMode) {
        print('MTU changed to: $mtu');
      }
    });
  }

  String _formatBytes(Uint8List bytes) {
    if (bytes.length <= 20) {
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    }
    return '${bytes.sublist(0, 20).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}...';
  }

  Future<void> initPlatformState() async {
    final isSupported = await FlutterBlePeripheral().isSupported;
    setState(() {
      _isSupported = isSupported;
    });
  }

  Future<void> _sendTestData() async {
    final isConnected = await FlutterBlePeripheral().isConnected;
    if (!isConnected) {
      _messangerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('No device connected!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      _messageCounter++;
      final message = 'Hello from Flutter #$_messageCounter';
      final data = Uint8List.fromList(message.codeUnits);

      await FlutterBlePeripheral().sendData(data);

      _messangerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Sent: $message'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      _messangerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Send failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleAdvertise() async {
    if (await FlutterBlePeripheral().isAdvertising) {
      await FlutterBlePeripheral().stop();
    } else {
      await FlutterBlePeripheral().start(advertiseData: advertiseData);
    }
  }

  Future<void> _toggleAdvertiseSet() async {
    if (await FlutterBlePeripheral().isAdvertising) {
      await FlutterBlePeripheral().stop();
    } else {
      await FlutterBlePeripheral().start(
        advertiseData: advertiseData,
        advertiseSetParameters: advertiseSetParameters,
      );
    }
  }

  Future<void> _requestPermissions([BluetoothPeripheralState? state]) async {
    final hasPermission = await FlutterBlePeripheral().requestPermission();
    switch (hasPermission) {
      case BluetoothPeripheralState.denied:
        _messangerKey.currentState?.showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text(
              "We don't have permissions, requesting now!",
            ),
          ),
        );

        final status = await FlutterBlePeripheral().requestPermission();
        _requestPermissions(status);
        return;
      default:
        _messangerKey.currentState?.showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(
              'State: $hasPermission!',
            ),
          ),
        );
    }
  }

  Future<void> _hasPermissions() async {
    final hasPermissions = await FlutterBlePeripheral().hasPermission();
    _messangerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('Has permission: $hasPermissions'),
        backgroundColor: hasPermissions == BluetoothPeripheralState.granted
            ? Colors.green
            : Colors.red,
      ),
    );
  }

  final _messangerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _messangerKey,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter BLE Peripheral'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('Is supported: $_isSupported'),
              StreamBuilder(
                stream: FlutterBlePeripheral().onPeripheralStateChanged,
                initialData: PeripheralState.unknown,
                builder:
                    (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
                  return Text(
                    'State: ${(snapshot.data as PeripheralState).name}',
                  );
                },
              ),
              const Divider(),
              const Text(
                'GATT Server Info',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text('MTU: $_currentMtu bytes'),
              Text(
                'Data received: $_lastReceivedData',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              StreamBuilder(
                stream: FlutterBlePeripheral().onPeripheralStateChanged,
                initialData: PeripheralState.unknown,
                builder:
                    (BuildContext context, AsyncSnapshot<PeripheralState> snapshot) {
                  final isConnected = snapshot.data == PeripheralState.connected;
                  return MaterialButton(
                    onPressed: isConnected ? _sendTestData : null,
                    color: isConnected ? Colors.green : Colors.grey,
                    child: Text(
                      isConnected ? 'Send Test Data' : 'Not Connected',
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                },
              ),
              const Divider(),
              Text(
                'Service UUID: ${advertiseData.serviceUuid}',
                style: const TextStyle(fontSize: 12),
              ),
              MaterialButton(
                onPressed: _toggleAdvertise,
                child: Text(
                  'Toggle advertising',
                  style: Theme.of(context)
                      .primaryTextTheme
                      .labelLarge!
                      .copyWith(color: Colors.blue),
                ),
              ),
              MaterialButton(
                onPressed: () async {
                  await FlutterBlePeripheral().start(
                    advertiseData: advertiseData,
                    advertiseSetParameters: advertiseSetParameters,
                  );
                },
                child: Text(
                  'Start advertising',
                  style: Theme.of(context)
                      .primaryTextTheme
                      .labelLarge!
                      .copyWith(color: Colors.blue),
                ),
              ),
              MaterialButton(
                onPressed: () async {
                  await FlutterBlePeripheral().stop();
                },
                child: Text(
                  'Stop advertising',
                  style: Theme.of(context)
                      .primaryTextTheme
                      .labelLarge!
                      .copyWith(color: Colors.blue),
                ),
              ),
              MaterialButton(
                onPressed: _toggleAdvertiseSet,
                child: Text(
                  'Toggle advertising set for 1 second',
                  style: Theme.of(context)
                      .primaryTextTheme
                      .labelLarge!
                      .copyWith(color: Colors.blue),
                ),
              ),
              StreamBuilder(
                stream: FlutterBlePeripheral().onPeripheralStateChanged,
                initialData: PeripheralState.unknown,
                builder: (
                  BuildContext context,
                  AsyncSnapshot<PeripheralState> snapshot,
                ) {
                  return MaterialButton(
                    onPressed: () async {
                      final bool enabled = await FlutterBlePeripheral()
                          .enableBluetooth(askUser: false);
                      if (enabled) {
                        _messangerKey.currentState!.showSnackBar(
                          const SnackBar(
                            content: Text('Bluetooth enabled!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        _messangerKey.currentState!.showSnackBar(
                          const SnackBar(
                            content: Text('Bluetooth not enabled!'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    child: Text(
                      'Enable Bluetooth (ANDROID)',
                      style: Theme.of(context)
                          .primaryTextTheme
                          .labelLarge!
                          .copyWith(color: Colors.blue),
                    ),
                  );
                },
              ),
              MaterialButton(
                onPressed: () async {
                  final bool enabled =
                      await FlutterBlePeripheral().enableBluetooth();
                  if (enabled) {
                    _messangerKey.currentState!.showSnackBar(
                      const SnackBar(
                        content: Text('Bluetooth enabled!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    _messangerKey.currentState!.showSnackBar(
                      const SnackBar(
                        content: Text('Bluetooth not enabled!'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: Text(
                  'Ask if enable Bluetooth (ANDROID)',
                  style: Theme.of(context)
                      .primaryTextTheme
                      .labelLarge!
                      .copyWith(color: Colors.blue),
                ),
              ),
              MaterialButton(
                onPressed: _requestPermissions,
                child: Text(
                  'Request Permissions',
                  style: Theme.of(context)
                      .primaryTextTheme
                      .labelLarge!
                      .copyWith(color: Colors.blue),
                ),
              ),
              MaterialButton(
                onPressed: _hasPermissions,
                child: Text(
                  'Has permissions',
                  style: Theme.of(context)
                      .primaryTextTheme
                      .labelLarge!
                      .copyWith(color: Colors.blue),
                ),
              ),
              MaterialButton(
                onPressed: () => FlutterBlePeripheral().openBluetoothSettings(),
                child: Text(
                  'Open bluetooth settings',
                  style: Theme.of(context)
                      .primaryTextTheme
                      .labelLarge!
                      .copyWith(color: Colors.blue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
