import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ---- Hardcoded route data (same as passenger_screen.dart) ----
class BusRoute {
  final String id;
  final String company;
  final String label;
  final List<String> stops;
  BusRoute({
    required this.id,
    required this.company,
    required this.label,
    required this.stops,
  });
}

final List<BusRoute> allRoutes = [
  BusRoute(
    id: 'mayuri_jamal',
    company: 'Mayuri',
    label: 'Kalanki → Jamal (via Lainchaur)',
    stops: [
      'Kalanki',
      'Banasthali',
      'Balaju',
      'Sorhakhutte',
      'Lainchaur',
      'Jamal',
    ],
  ),
  BusRoute(
    id: 'mayuri_baudha',
    company: 'Mayuri',
    label: 'Kalanki → Baudha (via Chabahil)',
    stops: [
      'Kalanki',
      'Banasthali',
      'Balaju',
      'Samakhusi',
      'Chabahil',
      'Baudha',
    ],
  ),
  BusRoute(
    id: 'sajha_koteshwor',
    company: 'Sajha',
    label: 'Ratnapark → Koteshwor',
    stops: ['Ratnapark', 'Baneshwor', 'Koteshwor'],
  ),
];
//Take every route → grab just its company name → throw away duplicates → give back a clean list
List<String> allCompanies() => allRoutes.map((r) => r.company).toSet().toList();
//so this function basically compares chosen routes name with all the companies available
List<BusRoute> routesFor(String company) =>
    allRoutes.where((r) => r.company == company).toList();

// ---- Driver screen ----
class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  static const String _wsUrl = 'wss://busam.onrender.com/ws/driver';

  WebSocketChannel? _channel;
  Timer?
  _sendTimer; //will fire every few seconds to exactly know when we hit _startBroadcasting()
  bool _isOnline = false;
  String _status = 'Offline';
  String? _selectedCompany;
  BusRoute? _selectedRoute;

  @override
  void dispose() {
    _stopBroadcasting();
    super.dispose();
  }

//To check if the driver online location is on or not right?
  Future<bool> _ensureLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  //If off throw a message
    if (!serviceEnabled) {
      setState(() => _status = 'Location services are off');
      return false;
    }
//: check current permission → if not yet granted, ask once → if still refused, fail → separately, if permanently blocked
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


//Runs when driver taps go online
  Future<void> _startBroadcasting() async {
    if (_selectedRoute == null) {
      setState(() => _status = 'Please select a route first');
      return;
    }
//await → pause here until that whole permission-check/request flow finishes.
    final ok = await _ensureLocationPermission();
    if (!ok) return;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl)); //attempt to open the WebSocket connection.
    } catch (e) {
      setState(() => _status = 'Failed to connect: $e');
      return;
    }

    setState(() {
      _isOnline = true;
      _status = 'Online — broadcasting';
    });
//after every 3 econd current location is thrown?
    _sendCurrentLocation();
    _sendTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _sendCurrentLocation();
    });
  }

  Future<void> _sendCurrentLocation() async {
    try {
      //getPositionStream(...) — an ongoing subscription that auto-fires on movement. 
      //This is getCurrentPosition(...) — a one-time GPS check: "give me my location right now, once." Makes sense here, since this function itself is already being called repeatedly by the Timer
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final payload = jsonEncode({
        'lat': position.latitude,
        'lng': position.longitude,
        'route_id': _selectedRoute?.id,
      });
 //.add(payload) → pushes this String out through the open connection, to the backend, which then relays it to any listening passengers.
      _channel?.sink.add(payload);

      if (mounted) { //mounted=is this sceen still alive(as in screen not destroyed or removed(dispose))
        setState(() {
          _status =
              'Sent: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}'; //status=lan and lgt but only 5 digit after point
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'GPS error: $e');
    }
  }

//runs when the driver taps "Go Offline"
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
            // Company dropdown
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Bus Company',
                border: OutlineInputBorder(),
              ),
              value: _selectedCompany,
              items: companies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: _isOnline //If _isOnline is true, use null; otherwise use the function.
                  ? null 
                  : (v) {
                      setState(() {
                        _selectedCompany = v;
                        _selectedRoute = null; // reset route on company change
                      });
                    },
            ),
            const SizedBox(height: 16),

            // Route dropdown (depends on company)
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


            Icon( //Ternary operation for wifi signal on or off
              _isOnline ? Icons.wifi_tethering : Icons.wifi_tethering_off,
              size: 80,
              color: _isOnline ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 24),
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 32),
            ElevatedButton( 
              onPressed: _toggleOnline,
              style: ElevatedButton.styleFrom( //for online/offline button coloring green or red
                backgroundColor: _isOnline ? Colors.red : Colors.green,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
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
