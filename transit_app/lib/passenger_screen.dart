//1.Import part
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
//Goal is to collect every unique stop name from all routes
//add to Sets
List<String> allStopNames() {
  final set = <String>{};
  for (final r in allRoutes) {
    set.addAll(r.stops);
  }
  return set.toList()..sort();
}

//5.To search starting and ending point of trip and see if its available or not
//allRoutes.where().toList()
List<BusRoute> searchRoutes(String from, String to) {
  //Conrtains start and final destination
  return allRoutes.where((route) {
    final fromIndex = route.stops.indexWhere(
      //fromIndex=Index of Balahju
      (s) => s.toLowerCase() == from.toLowerCase(),
    );
    final toIndex = route.stops.indexWhere(
      //toIndex= Index of final destination
      (s) => s.toLowerCase() == to.toLowerCase(),
    );
    return fromIndex != -1 &&
        toIndex != -1 &&
        fromIndex < toIndex; //Returns true if conditon is met for example 2<5
  }).toList();
}

//6.Createstate is a function that returns a PassengerScreenState class and _ means private4
class PassengerScreen extends StatefulWidget {
  const PassengerScreen({super.key});

  @override
  State<PassengerScreen> createState() => _PassengerScreenState();
}

//7.State is a built in flutter class (setState,initState,dispose)tools
class _PassengerScreenState extends State<PassengerScreen> {
  //ws protocol contains my wifi ip address at passenger end
  static const String _wsUrl = 'ws://192.168.18.156:8000/ws/passenger';

  //Websocket latlng are data type
  WebSocketChannel? _channel; //variable will hold websocket channel object
  LatLng? _busLocation; // holds bus coordinates
  LatLng? _myLocation; // holds passenger coordinates
  String _status = 'Connecting...';

  final MapController _mapController =
      MapController(); //creating a object of MapController class
  // // A Stream = a sequence of values that arrive over time, one at a time (not all at once)
  //Keep watching and report my new position every time i move

  StreamSubscription<Position>? _positionSub;
  bool _hasCenteredOnMe = false;

  String? _activeRouteId;
  bool _driverOnline = false;

  int _navIndex = 0; // 0 = Home

  String? _fromStop;
  String? _toStop;
  List<BusRoute>? _searchResults;

  //8.runs once
  @override
  void initState() {
    super.initState(); //Internal setup
    _connect(); //start opening websocket connection to backend
    _startTrackingMyLocation(); //checking and asking location of passenger permission
  }

  //9. Connecting flutter to websocket
  void _connect() {
    _channel = WebSocketChannel.connect(
      Uri.parse(_wsUrl),
    ); //uri.pase(string->uri object), _wsurl is a websocket server url
    setState(
      () => _status = 'Waiting for bus location...',
    ); //smtg changed rebuild the UI

    //Websocket sends data in JSON as text. Jsondecode converts it into smtg you can access like map
    _channel!.stream.listen(
      (data) {
        final decoded = jsonDecode(
          data,
        ); //converts text that looks like JSON into actual dart object
        final lat = decoded['lat'];
        final lng = decoded['lng'];
        final routeId = decoded['route_id'];
        final driverOnline = decoded['driver_online'] ?? false;

        //using above data to assign buslocation and status
        setState(() {
          //smtg changed build() again so the screen catches up
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
          _mapController.move(
            LatLng(lat, lng),
            _mapController.camera.zoom,
          ); //Move the maps view so that bus new location is centered
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

  //aysnc/await/Future
  //Future->I will give you later
  //async->doing smtg that may take time
  //await->wait until future work is done
  //Future<T> will be available later not right now
  //

  //Checks if the passenger gps is on or not
  Future<void> _startTrackingMyLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    //Ask for permission(popup passenger see)
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    //Block the check permanently
    if (permission == LocationPermission.deniedForever) return;

    //Permission granted,now actually start tracking
    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            //class from geolocator package
            accuracy: LocationAccuracy.high,
            distanceFilter: 5, //if moved 5 metre
          ),
        ).listen((Position position) {
          //receive values from stream current lat/lng
          if (!mounted) return; //screen alive or not ny mounted(bool)
          final newLocation = LatLng(
            position.latitude,
            position.longitude,
          ); // using new coordinates as new location
          setState(() => _myLocation = newLocation);

          //if passenger is not centered and bus is not available centre on passenger
          if (!_hasCenteredOnMe && _busLocation == null) {
            _hasCenteredOnMe = true;
            _mapController.move(
              newLocation,
              16,
            ); //16 is zoom level for close up
          }
        });
  }

  void _runSearch() {
    if (_fromStop == null || _toStop == null) return;
    final matched = searchRoutes(_fromStop!, _toStop!);

    // Only keep routes that a currently-online bus is actually running
    final liveMatches = matched
        .where((r) => _driverOnline && r.id == _activeRouteId) //true && true
        .toList();

    setState(() {
      _searchResults = liveMatches;
    });
  }

  //closing everything that happenbed in inistate
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
            mapController:
                _mapController, //mapcontroller to autocenter passenger
            options: MapOptions(
              initialCenter: center,
              initialZoom: 14,
            ), //mapoption for intial map load of centering
            children: [
              TileLayer(
                //visible map like street,building,water
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png', //Openstreetmap
                userAgentPackageName:
                    'com.example.transit_app', //to identify my app for requesting map
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
            //to decide exactly where top/middle/bottom
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              //avoid phone hardware obstruction
              child: Container(
                margin: const EdgeInsets.all(
                  12,
                ), //for the white card with balance and student id
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
                      children: const [
                        Icon(Icons.account_balance_wallet_outlined),
                        SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NPR 000.00',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
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

          //3. search box
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(// to avoid hardware obstruction
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
                        //Basically bus icon with route a->b->c->
                        ..._searchResults!.map(
                          (r) => ListTile(
                            //template
                            dense: true,
                            leading: const Icon(
                              Icons.directions_bus,
                              color: Colors.green,
                            ),
                            title: Text(r.label),
                            subtitle: Text(r.stops.join(' → ')),
                          ),
                        ),

                      const Divider(), //------draws horizontal line across screen
                    ],
                    Row(
                      children: [
                        const Icon(Icons.trip_origin, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          //icon 18 px sizedbox 8 pix expanded grows to fill whatever horizontal space is left in the row
                          child: Autocomplete<String>( //build in widget that handles 'type text,see filtered suggestion dropdown,pick me' pattern
                            optionsBuilder: (TextEditingValue value) {//For recommendation  If B is typed Balaju is recommended
                              if (value.text.isEmpty)
                                return const Iterable<String>.empty();
                              return stops.where(
                                (s) => s.toLowerCase().startsWith(
                                  value.text.toLowerCase(),
                                ),
                              );
                            },
                            //Runs when passenger taps one of the suggestion
                            onSelected: (String selection) => //selection -> whichever location he tapped saves in into fromstop variable set via setState
                                setState(() => _fromStop = selection),
                            
                            //what the txt box looks like (only the top box the actual texfield ram types into the location)
                            fieldViewBuilder:
                                (context, controller, focusNode, onSubmit) {
                                  return TextField(
                                    controller: controller,//A TextEditingController object, created and owned by Autocomplete itself — not by you 
                                    //Its job: hold the actual text currently typed, and let you read/change it programmatically
                                    focusNode: focusNode,// A FocusNode object — tracks whether this particular text field is currently focused 
                                    //Needed because Autocomplete needs to know "is the user actively typing in THIS box" to decide when to show/hide the suggestions dropdown
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
        onTap: (index) {
          setState(() => _navIndex = index);
          if (index != 0) {
            final labels = ['Home', 'Load Money', 'Pass', 'History', 'Profile'];
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${labels[index]} - coming soon')),
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
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
