import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:developer'; // Use log for debugging

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartBin App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  MyHomePageState createState() => MyHomePageState();
}

class MyHomePageState extends State<MyHomePage> {
  BluetoothDevice? _connectedDevice;
  List<BluetoothDevice> _devicesList = [];
  bool _isScanning = false;
  int trashLevel = 0; // Trash level percentage (0-100)

  @override
  void initState() {
    super.initState();
    requestBluetoothPermissions();
    _listenForScanResults();
  }

  /// ✅ Request Bluetooth Permissions & Ensure Location is Enabled
  Future<void> requestBluetoothPermissions() async {
    try {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse, // BLE requires foreground location access
        Permission.nearbyWifiDevices, // Added for Android 12+ compatibility
      ].request();

      log("Permission status: $statuses"); // Debugging output

      if (!(await Permission.locationWhenInUse.isGranted)) {
        log("Error: Location permission required for BLE scanning.");
      }

    } catch (e) {
      log("Error requesting permissions: $e");
    }
  }

  /// ✅ Ensure Location Services Are Enabled Before Scanning
  Future<bool> _isLocationEnabled() async {
    return await Permission.locationWhenInUse.isGranted;
  }

  void _startScan() async {
    if (!(await Permission.bluetoothScan.isGranted) || !(await Permission.bluetoothConnect.isGranted)) {
      log("Error: Missing Bluetooth permissions.");
      await requestBluetoothPermissions();
      return;
    }

    if (!(await _isLocationEnabled())) {
      log("Error: Location services must be enabled for BLE scanning.");
      await requestBluetoothPermissions();
      return;
    }

    if (!_isScanning) {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
      setState(() {
        _isScanning = true;
      });
    }
  }

  void _stopScan() {
    FlutterBluePlus.stopScan();
    setState(() {
      _isScanning = false;
    });
  }

  void _listenForScanResults() {
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _devicesList = results.map((ScanResult result) => result.device).toList();
      });
    });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        _connectedDevice = device;
      });

      _listenForTrashLevel(device);
    } catch (e) {
      log("Error connecting to device: $e");
    }
  }

  void _disconnectFromDevice() async {
    if (_connectedDevice != null) {
      await _connectedDevice?.disconnect();
      setState(() {
        _connectedDevice = null;
        trashLevel = 0; // Reset trash level on disconnect
      });
    }
  }

  void _listenForTrashLevel(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();

      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          if (characteristic.properties.read) {
            characteristic.read().then((data) {
              setState(() {
                trashLevel = int.tryParse(String.fromCharCodes(data)) ?? 0; // Convert bytes to integer safely
              });
            }).catchError((error) {
              log("Error reading trash level: $error");
            });
          }
        }
      }
    } catch (e) {
      log("Error discovering services: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartBin - Trashbin Monitor'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: _isScanning ? _stopScan : _startScan,
              child: Text(_isScanning ? 'Scanning...' : 'Start Scan'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _devicesList.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_devicesList[index].platformName),
                  subtitle: Text(_devicesList[index].remoteId.toString()),
                  onTap: () => _connectToDevice(_devicesList[index]),
                );
              },
            ),
          ),
          if (_connectedDevice != null) ...[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton(
                onPressed: _disconnectFromDevice,
                child: Text('Disconnect from ${_connectedDevice!.platformName}'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  const Text('Trash Level:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('$trashLevel%', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  LinearProgressIndicator(value: trashLevel / 100),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}