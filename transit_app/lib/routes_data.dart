import 'package:latlong2/latlong.dart';

class Stop {
  final String name;
  final LatLng coordinates;
  const Stop({required this.name, required this.coordinates});
}

class BusRoute {
  final String id;
  final String company;
  final String label;
  final List<Stop> stops;
  BusRoute({
    required this.id,
    required this.company,
    required this.label,
    required this.stops,
  });
}

// ---- Shared stop coordinates ----
const Map<String, LatLng> stopCoordinates = {
  'Kalanki': LatLng(27.6956, 85.2796),
  'Banasthali': LatLng(27.7249, 85.2978),
  'Balaju': LatLng(27.7310, 85.2981),
  'Sorhakhutte': LatLng(27.7160, 85.3070),
  'Lainchaur': LatLng(27.7194, 85.3151),
  'Jamal': LatLng(27.7093, 85.3152),
  'Samakhusi': LatLng(27.7273, 85.3175),
  'Chabahil': LatLng(27.7168, 85.3537),
  'Baudha': LatLng(27.7214, 85.3619),
  'Ratnapark': LatLng(27.7063, 85.3152),
  'Baneshwor': LatLng(27.6986, 85.3356),
  'Koteshwor': LatLng(27.6756, 85.3459),
};

Stop _s(String name) => Stop(name: name, coordinates: stopCoordinates[name]!);

// ---- Shared routes ----
final List<BusRoute> allRoutes = [
  BusRoute(
    id: 'mayuri_jamal',
    company: 'Mayuri',
    label: 'Kalanki → Jamal (via Lainchaur)',
    stops: [
      _s('Kalanki'),
      _s('Banasthali'),
      _s('Balaju'),
      _s('Sorhakhutte'),
      _s('Lainchaur'),
      _s('Jamal'),
    ],
  ),
  BusRoute(
    id: 'mayuri_baudha',
    company: 'Mayuri',
    label: 'Kalanki → Baudha (via Chabahil)',
    stops: [
      _s('Kalanki'),
      _s('Banasthali'),
      _s('Balaju'),
      _s('Samakhusi'),
      _s('Chabahil'),
      _s('Baudha'),
    ],
  ),
  BusRoute(
    id: 'sajha_koteshwor',
    company: 'Sajha',
    label: 'Ratnapark → Koteshwor',
    stops: [
      _s('Ratnapark'),
      _s('Baneshwor'),
      _s('Koteshwor'),
    ],
  ),
];

List<String> allStopNames() {
  final set = <String>{};
  for (final r in allRoutes) {
    set.addAll(r.stops.map((s) => s.name));
  }
  return set.toList()..sort();
}

List<BusRoute> searchRoutes(String from, String to) {
  return allRoutes.where((route) {
    final fromIndex = route.stops.indexWhere(
      (s) => s.name.toLowerCase() == from.toLowerCase(),
    );
    final toIndex = route.stops.indexWhere(
      (s) => s.name.toLowerCase() == to.toLowerCase(),
    );
    return fromIndex != -1 && toIndex != -1 && fromIndex < toIndex;
  }).toList();
}

LatLng? stopCoordinatesFor(String stopName) => stopCoordinates[stopName];
