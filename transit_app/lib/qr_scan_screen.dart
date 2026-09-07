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
  static const String _backendUrl = 'https://busam.onrender.com';

  bool _processing = false;
  bool _scanCompleted = false;
  String? _resultMessage;

  // exit payment-choice state
  bool _showPaymentChoice = false;
  Map<String, dynamic>? _exitData;

  Future<void> _handleScan(String routeId) async {
    // Ignore further detections while processing, mid-payment-choice, or already done
    if (_processing || _scanCompleted || _showPaymentChoice) return;

    setState(() => _processing = true);

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

      if (data['event'] == 'exit_pending') {
        // exit scan: show payment choice instead of a final message
        setState(() {
          _showPaymentChoice = true;
          _exitData = data;
        });
      } else {
        // boarding scan
        setState(() {
          _scanCompleted = true;
          _resultMessage = data['message'];
        });
      }
    } catch (e) {
      setState(() {
        _scanCompleted = true;
        _resultMessage = 'Error: $e';
      });
    } finally {
      setState(() => _processing = false);
    }
  }

  Future<void> _confirmExit(String method) async {
    setState(() => _processing = true);

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/qr/confirm_exit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id': widget.deviceId,
          'method': method,
        }),
      );
      final data = jsonDecode(response.body);

      setState(() {
        _processing = false;
        _showPaymentChoice = false;
        _scanCompleted = true;
        _resultMessage = data['message'] ??
            (data['success'] == true ? 'Trip complete.' : 'Payment failed.');
      });
    } catch (e) {
      setState(() {
        _processing = false;
        _resultMessage = 'Error: $e';
      });
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
            child: (_scanCompleted || _showPaymentChoice)
                ? Container(
                    color: Colors.black,
                    child: Center(
                      child: Icon(
                        _showPaymentChoice ? Icons.payment : Icons.check_circle,
                        color: Colors.green,
                        size: 64,
                      ),
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
            flex: 2,
            child: Center(
              child: _processing
                  ? const CircularProgressIndicator()
                  : _showPaymentChoice
                      ? _buildPaymentChoice()
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

  Widget _buildPaymentChoice() {
    final distance = _exitData?['distance_km'];
    final walletFare = _exitData?['wallet_fare'];
    final passAvailable = _exitData?['pass_available'] == true;
    final passRides = _exitData?['pass_rides_remaining'] ?? 0;
    final company = _exitData?['company'] ?? 'this company';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Distance: ${distance}km',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          const Text(
            'How would you like to pay?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => _confirmExit('wallet'),
              child: Text('Pay with Wallet — NPR $walletFare'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: passAvailable ? () => _confirmExit('pass') : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: passAvailable ? Colors.blue : Colors.grey[300],
              ),
              child: Text(
                passAvailable
                    ? 'Pay with $company Pass ($passRides left)'
                    : 'No $company pass available',
              ),
            ),
          ),
        ],
      ),
    );
  }
}