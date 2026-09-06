import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;

class QrScanScreen extends StatefulWidget {
  final String deviceId;
  const QrScanScreen({super.key, required this.deviceId});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  static const String _backendUrl = 'http://192.168.18.156:8000';

  bool _processing = false;
  bool _scanCompleted = false; // NEW: locks out further scans once one succeeds
  String? _resultMessage;

  Future<void> _handleScan(String routeId) async {
    // Ignore any further detections once we're processing OR already got a result
    if (_processing || _scanCompleted) return;

    setState(() {
      _processing = true;
      _scanCompleted = true; // lock immediately, before the async call even starts
    });

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final response = await http.post(
        Uri.parse('$_backendUrl/qr/scan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id': widget.deviceId,
          'route_id': routeId,
          'lat': position.latitude,
          'lng': position.longitude,
        }),
      );

      final data = jsonDecode(response.body);

      setState(() {
        _resultMessage = data['message'];
      });
    } catch (e) {
      setState(() => _resultMessage = 'Error: $e');
    } finally {
      setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Bus QR')),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: _scanCompleted
                ? Container(
                    color: Colors.black,
                    child: const Center(
                      child: Icon(Icons.check_circle,
                          color: Colors.green, size: 64),
                    ),
                  )
                : MobileScanner(
                    onDetect: (capture) {
                      final barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty) {
                        final routeId = barcodes.first.rawValue;
                        if (routeId != null) {
                          _handleScan(routeId);
                        }
                      }
                    },
                  ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: _processing
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _resultMessage ??
                                'Point camera at the bus QR code',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16),
                          ),
                          if (_scanCompleted) ...[
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Done'),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}