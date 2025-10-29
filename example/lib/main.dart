/*
 * Copyright (c) 2020. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'dart:io';
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
  // Service UUID for GATT server - configurable
  String _serviceUuid = 'bf27730d-860a-4e09-889c-2d8b6a9e0fe7';
  String _localName = 'FlutterBLE Peripheral';

  late AdvertiseDataCore _advertiseData;
  AndroidAdvertiseSettings? _androidSettings;
  DarwinAdvertiseSettings? _darwinSettings;
  WindowsAdvertiseSettings? _windowsSettings;

  bool _isSupported = false;
  String _lastReceivedData = 'None';
  int _currentMtu = 23; // Default MTU
  int _messageCounter = 0;

  final _serviceUuidController = TextEditingController();
  final _localNameController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // Initialize controllers with default values
    _serviceUuidController.text = _serviceUuid;
    _localNameController.text = _localName;

    // Initialize advertise data and settings
    _updateAdvertiseData();

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

  @override
  void dispose() {
    _serviceUuidController.dispose();
    _localNameController.dispose();
    super.dispose();
  }

  void _updateAdvertiseData() {
    // Core advertising data (cross-platform)
    _advertiseData = AdvertiseDataCore(
      serviceUuid: _serviceUuid,
      localName: _localName,
    );

    // Platform-specific settings
    if (Platform.isAndroid) {
      // Android-specific settings (matches native API structure)
      _androidSettings = const AndroidAdvertiseSettings(
        // Extended advertising (Android 8+) - RECOMMENDED
        // Provides more control and features than legacy advertising
        advertiseSetParameters: AdvertiseSetParameters(
          connectable: true, // IMPORTANT: Enable connections for GATT server
          interval: intervalLow, // 250ms advertising interval
          txPowerLevel: txPowerHigh, // Maximum range
          legacyMode: false, // Use extended advertising features
          // primaryPhy: phy1m, // Optional: 1M PHY (default)
          // secondaryPhy: phy2m, // Optional: 2M PHY for higher throughput
        ),

        // Legacy advertising (pre-Android 8) - DEPRECATED
        // Use only if you need to support Android 7 and below
        // IMPORTANT: Only use ONE of advertiseSettings OR advertiseSetParameters
        //
        // advertiseSettings: AdvertiseSettings(
        //   connectable: true,
        //   timeout: 0, // 0 = no timeout
        //   advertiseMode: AdvertiseMode.advertiseModeLowLatency,
        //   txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
        // ),

        // Optional: scan response data
        // advertiseResponseData: AndroidAdvertiseData(...),

        // Optional: periodic advertising (requires advertiseSetParameters)
        // periodicAdvertiseData: AndroidAdvertiseData(...),
        // periodicAdvertiseSettings: PeriodicAdvertiseSettings(...),
      );
    } else if (Platform.isIOS || Platform.isMacOS) {
      // Darwin (iOS/macOS) specific settings
      _darwinSettings = DarwinAdvertiseSettings(
        // Example: Add manufacturer data (Apple Inc. = 0x004C)
        manufacturerData: Uint8List.fromList([
          0x4C,
          0x00, // Apple manufacturer ID (little-endian)
          0x01,
          0x02,
          0x03, // Custom data
        ]),
        // Example: Add service data
        serviceData: {
          "180F": Uint8List.fromList([0x64]), // Battery Service: 100%
        },
        // Enable connections
        isConnectable: true,
      );
    } else if (Platform.isWindows) {
      // Windows-specific settings
      _windowsSettings = WindowsAdvertiseSettings(
        manufacturerId: 1234,
        manufacturerData: Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05]),
        flags: 0x06, // LE General Discoverable + BR/EDR Not Supported
      );
    }
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
      // Update advertise data with current configuration before starting
      _updateAdvertiseData();
      await FlutterBlePeripheral().start(
        advertiseData: _advertiseData,
        androidSettings: _androidSettings,
        darwinSettings: _darwinSettings,
        windowsSettings: _windowsSettings,
      );
    }
  }

  Future<void> _showConfigDialog() async {
    // Check if currently advertising
    final isAdvertising = await FlutterBlePeripheral().isAdvertising;

    if (isAdvertising) {
      _messangerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Please stop advertising before changing configuration'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configure Peripheral'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Service UUID',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _serviceUuidController,
                decoration: const InputDecoration(
                  hintText: 'bf27730d-860a-4e09-889c-2d8b6a9e0fe7',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Text(
                'Device Name',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _localNameController,
                decoration: const InputDecoration(
                  hintText: 'FlutterBLE Peripheral',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _serviceUuid = _serviceUuidController.text;
                _localName = _localNameController.text;
                _updateAdvertiseData();
              });
              Navigator.pop(context);
              _messangerKey.currentState?.showSnackBar(
                const SnackBar(
                  content: Text('Configuration updated'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Future<void> _toggleAdvertiseSet() async {
  //   if (await FlutterBlePeripheral().isAdvertising) {
  //     await FlutterBlePeripheral().stop();
  //   } else {
  //     await FlutterBlePeripheral().start(
  //       advertiseData: advertiseData,
  //       advertiseSetParameters: advertiseSetParameters,
  //     );
  //   }
  // }

  Future<void> _requestPermissions([FlutterBleBluetoothState? state]) async {
    final hasPermission = await FlutterBlePeripheral().requestPermission();
    switch (hasPermission) {
      case FlutterBleBluetoothState.denied:
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
        backgroundColor: hasPermissions == FlutterBleBluetoothState.granted
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
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Configure',
              onPressed: _showConfigDialog,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Peripheral Status',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text('BLE Supported: $_isSupported'),
                      StreamBuilder(
                        stream: FlutterBlePeripheral().onPeripheralStateChanged,
                        initialData: FlutterBlePeripheralState.unknown,
                        builder:
                            (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
                          final state = (snapshot.data as FlutterBlePeripheralState).name;
                          return Text(
                            'Connection State: $state',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: snapshot.data == FlutterBlePeripheralState.connected
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'GATT Server Configuration',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Service UUID:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SelectableText(
                        _serviceUuid,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Device Name:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _localName,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Text('MTU: $_currentMtu bytes'),
                      const SizedBox(height: 4),
                      const Text(
                        'Last received:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SelectableText(
                        _lastReceivedData,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              StreamBuilder(
                stream: FlutterBlePeripheral().onPeripheralStateChanged,
                initialData: FlutterBlePeripheralState.unknown,
                builder:
                    (BuildContext context, AsyncSnapshot<FlutterBlePeripheralState> snapshot) {
                  final isConnected = snapshot.data == FlutterBlePeripheralState.connected;
                  return ElevatedButton.icon(
                    onPressed: isConnected ? _sendTestData : null,
                    icon: const Icon(Icons.send),
                    label: Text(
                      isConnected ? 'Send Test Data' : 'Not Connected',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isConnected ? Colors.green : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              const Divider(),
              const Text(
                'Advertising Controls',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _toggleAdvertise,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
                child: const Text('Toggle Advertising'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Permissions & Settings',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _requestPermissions,
                      child: const Text('Request Permissions'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _hasPermissions,
                      child: const Text('Check Permissions'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => FlutterBlePeripheral().openBluetoothSettings(),
                child: const Text('Open Bluetooth Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
