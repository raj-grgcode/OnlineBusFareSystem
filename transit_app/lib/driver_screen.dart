import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'routes_data.dart';

List<String> allCompanies() => allRoutes.map((r) => r.company).toSet().toList();

List<BusRoute> routesFor(String company) =>
    allRoutes.where((r) => r.company == company).toList();

class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  static const String _wsUrl = 'wss://busam.onrender.com/ws/driver';

  WebSocketChannel? _channel;
  Timer? _sendTimer;
  bool _isOnline = false;
  String _status = 'Offline';
  Position? _lastPosition;

  String? _selectedCompany;
  BusRoute? _selectedRoute;

  @override
  void dispose() {
    _stopBroadcasting();
    super.dispose();
  }

  Future<bool> _ensureLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _status = 'Location services are off');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _status = 'Location permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _status = 'Location permission permanently denied');
      return false;
    }

    return true;
  }

  Future<void> _startBroadcasting() async {
    if (_selectedRoute == null) {
      setState(() => _status = 'Please select a route first');
      return;
    }

    final ok = await _ensureLocationPermission();
    if (!ok) return;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
    } catch (e) {
      setState(() => _status = 'Failed to connect: $e');
      return;
    }

    setState(() {
      _isOnline = true;
      _status = 'Online — broadcasting';
    });

    _sendCurrentLocation();
    _sendTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _sendCurrentLocation();
    });
  }

  Future<void> _sendCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _lastPosition = position;

      final payload = jsonEncode({
        'lat': position.latitude,
        'lng': position.longitude,
        'route_id': _selectedRoute?.id,
      });

      _channel?.sink.add(payload);

      if (mounted) {
        setState(() {
          _status =
              'Sent: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'GPS error: $e');
    }
  }

  void _stopBroadcasting() {
    _sendTimer?.cancel();
    _sendTimer = null;
    _channel?.sink.close();
    _channel = null;

    if (mounted) {
      setState(() {
        _isOnline = false;
        _status = 'Offline';
      });
    }
  }

  void _toggleOnline() {
    if (_isOnline) {
      _stopBroadcasting();
    } else {
      _startBroadcasting();
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = allCompanies();
    final routesForCompany = _selectedCompany == null
        ? <BusRoute>[]
        : routesFor(_selectedCompany!);

    return Scaffold(
      appBar: AppBar(title: const Text('Driver')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Bus Company',
                border: OutlineInputBorder(),
              ),
              value: _selectedCompany,
              items: companies
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: _isOnline
                  ? null
                  : (v) {
                      setState(() {
                        _selectedCompany = v;
                        _selectedRoute = null;
                      });
                    },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<BusRoute>(
              decoration: const InputDecoration(
                labelText: 'Route',
                border: OutlineInputBorder(),
              ),
              value: _selectedRoute,
              items: routesForCompany
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                  .toList(),
              onChanged: (_selectedCompany == null || _isOnline)
                  ? null
                  : (v) => setState(() => _selectedRoute = v),
            ),
            const SizedBox(height: 32),
            Icon(
              _isOnline ? Icons.wifi_tethering : Icons.wifi_tethering_off,
              size: 80,
              color: _isOnline ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 24),
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _toggleOnline,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isOnline ? Colors.red : Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: Text(
                _isOnline ? 'Go Offline' : 'Go Online',
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}