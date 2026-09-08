//1.Import part

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'qr_scan_screen.dart';
import 'device_id.dart';
import 'load_money_screen.dart';
import 'pass_company_screen.dart';
import 'profile_screen.dart';

//2. class for the Busroute validation
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

//3. allRoutes variable contain list of all the BusRoute object only
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

//4. allStopNames function which contains only List of string
List<String> allStopNames() {
  final set = <String>{};
  for (final r in allRoutes) {
    set.addAll(r.stops);
  }
  return set.toList()..sort();
}

//5.To search starting and ending point of trip and see if its available or not
List<BusRoute> searchRoutes(String from, String to) {
  return allRoutes.where((route) {
    final fromIndex = route.stops.indexWhere(
      (s) => s.toLowerCase() == from.toLowerCase(),
    );
    final toIndex = route.stops.indexWhere(
      (s) => s.toLowerCase() == to.toLowerCase(),
    );
    return fromIndex != -1 && toIndex != -1 && fromIndex < toIndex;
  }).toList();
}

//6.Createstate is a function that returns a PassengerScreenState class
class PassengerScreen extends StatefulWidget {
  const PassengerScreen({super.key});

  @override
  State<PassengerScreen> createState() => _PassengerScreenState();
}

//7.State is a built in flutter class (setState,initState,dispose)tools
class _PassengerScreenState extends State<PassengerScreen> {
  static const String _wsUrl = 'wss://busam.onrender.com/ws/passenger';
  static const String _backendUrl = 'https://busam.onrender.com';

  WebSocketChannel? _channel;
  LatLng? _busLocation;
  LatLng? _myLocation;
  String _status = 'Connecting...';

  final MapController _mapController = MapController();

  StreamSubscription<Position>? _positionSub;
  bool _hasCenteredOnMe = false;

  String? _activeRouteId;
  bool _driverOnline = false;

  int _navIndex = 0; // 0 = Home

  String? _fromStop;
  String? _toStop;
  List<BusRoute>? _searchResults;

  String? _deviceId;

  double _walletBalance = 0.0;

  //8.runs once
  @override
  void initState() {
    super.initState();
    _connect();
    _startTrackingMyLocation();
    _loadDeviceId();
  }

  Future<void> _loadDeviceId() async {
    final id = await getOrCreateDeviceId();
    if (mounted) setState(() => _deviceId = id);
    await _fetchWalletBalance();
  }

  Future<void> _fetchWalletBalance() async {
    if (_deviceId == null) return;
    try {
      final response = await http.get(
        Uri.parse('$_backendUrl/wallet/$_deviceId'),
      );
      final data = jsonDecode(response.body);
      if (mounted) {
        setState(() => _walletBalance = (data['balance'] ?? 0.0).toDouble());
      }
    } catch (e) {
      // silently ignore for now, balance just stays at last known value
    }
  }

  //9. Connecting flutter to websocket
  void _connect() {
    _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
    setState(() => _status = 'Waiting for bus location...');

    _channel!.stream.listen(
      (data) {
        final decoded = jsonDecode(data);
        final lat = decoded['lat'];
        final lng = decoded['lng'];
        final routeId = decoded['route_id'];
        final driverOnline = decoded['driver_online'] ?? false;

        setState(() {
          _driverOnline = driverOnline;
          _activeRouteId = routeId;
          if (lat != null && lng != null) {
            _busLocation = LatLng(lat, lng);
            _status = 'Live';
          } else {
            _busLocation = null;
            _status = 'No bus online';
          }
        });

        if (lat != null && lng != null) {
          _mapController.move(LatLng(lat, lng), _mapController.camera.zoom);
        }
      },
      onError: (error) {
        setState(() => _status = 'Connection error: $error');
      },
      onDone: () {
        setState(() => _status = 'Disconnected');
      },
    );
  }

  //Checks if the passenger gps is on or not
  Future<void> _startTrackingMyLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((Position position) {
          if (!mounted) return;
          final newLocation = LatLng(position.latitude, position.longitude);
          setState(() => _myLocation = newLocation);

          if (!_hasCenteredOnMe && _busLocation == null) {
            _hasCenteredOnMe = true;
            _mapController.move(newLocation, 16);
          }
        });
  }

  void _runSearch() {
    if (_fromStop == null || _toStop == null) return;
    final matched = searchRoutes(_fromStop!, _toStop!);

    final liveMatches = matched
        .where((r) => _driverOnline && r.id == _activeRouteId)
        .toList();

    setState(() {
      _searchResults = liveMatches;
    });
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _positionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center =
        _busLocation ?? _myLocation ?? const LatLng(27.7172, 85.3240);
    final stops = allStopNames();
    final bool showBusMarker =
        _searchResults == null || _searchResults!.isNotEmpty;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: center, initialZoom: 14),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.transit_app',
              ),
              MarkerLayer(
                markers: [
                  if (_busLocation != null && showBusMarker)
                    Marker(
                      point: _busLocation!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.directions_bus,
                        color: Colors.red,
                        size: 36,
                      ),
                    ),
                  if (_myLocation != null)
                    Marker(
                      point: _myLocation!,
                      width: 30,
                      height: 30,
                      child: const Icon(
                        Icons.person_pin_circle,
                        color: Colors.blue,
                        size: 30,
                      ),
                    ),
                ],
              ),
            ],
          ),
          //1.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NPR ${_walletBalance.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              'Balance',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () {
                        // TODO: open student ID card screen
                      },
                      child: Row(
                        children: const [
                          Icon(Icons.badge_outlined),
                          SizedBox(width: 4),
                          Text('Student ID'),
                          Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          //2. Black box with disconnected
          Positioned(
            bottom: 230,
            left: 12,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _status,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),

          //2b. QR Scan floating button (board/exit scan)
          Positioned(
            bottom: 230,
            right: 12,
            child: SafeArea(
              child: FloatingActionButton(
                heroTag: 'qr_scan_btn',
                backgroundColor: Colors.green,
                onPressed: _deviceId == null
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                QrScanScreen(deviceId: _deviceId!),
                          ),
                        );
                      },
                child: const Icon(Icons.qr_code_scanner),
              ),
            ),
          ),

          //3. search box
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchResults != null) ...[
                      if (_searchResults!.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('No buses found for this route'),
                        )
                      else
                        ..._searchResults!.map(
                          (r) => ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.directions_bus,
                              color: Colors.green,
                            ),
                            title: Text(r.label),
                            subtitle: Text(r.stops.join(' → ')),
                          ),
                        ),

                      const Divider(),
                    ],
                    Row(
                      children: [
                        const Icon(Icons.trip_origin, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Autocomplete<String>(
                            optionsBuilder: (TextEditingValue value) {
                              if (value.text.isEmpty)
                                return const Iterable<String>.empty();
                              return stops.where(
                                (s) => s.toLowerCase().startsWith(
                                  value.text.toLowerCase(),
                                ),
                              );
                            },
                            onSelected: (String selection) =>
                                setState(() => _fromStop = selection),
                            fieldViewBuilder:
                                (context, controller, focusNode, onSubmit) {
                                  return TextField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    decoration: const InputDecoration(
                                      hintText: 'From',
                                      border: InputBorder.none,
                                    ),
                                  );
                                },
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Autocomplete<String>(
                            optionsBuilder: (TextEditingValue value) {
                              if (value.text.isEmpty)
                                return const Iterable<String>.empty();
                              return stops.where(
                                (s) => s.toLowerCase().startsWith(
                                  value.text.toLowerCase(),
                                ),
                              );
                            },
                            onSelected: (String selection) =>
                                setState(() => _toStop = selection),
                            fieldViewBuilder:
                                (context, controller, focusNode, onSubmit) {
                                  return TextField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    decoration: const InputDecoration(
                                      hintText: 'To',
                                      border: InputBorder.none,
                                    ),
                                  );
                                },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _runSearch,
                        child: const Text('Search buses'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _navIndex,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        onTap: (index) async {
          setState(() => _navIndex = index);
          if (index == 1 && _deviceId != null) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LoadMoneyScreen(deviceId: _deviceId!),
              ),
            );
            _fetchWalletBalance();
          } else if (index == 2 && _deviceId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PassCompanyScreen(deviceId: _deviceId!),
              ),
            );
          } else if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ProfileScreen()),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Load Money',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.confirmation_number),
            label: 'Pass',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}