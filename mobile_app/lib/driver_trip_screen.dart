import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'dart:async';

class DriverTripScreen extends StatefulWidget {
  final String vanId; 
  final String serverUrl;
  final Map routeData; 
  final bool isReturnTrip; 

  const DriverTripScreen({
    super.key, 
    required this.vanId, 
    required this.serverUrl,
    required this.routeData,
    required this.isReturnTrip, 
  });

  @override
  State<DriverTripScreen> createState() => _DriverTripScreenState();
}

class _DriverTripScreenState extends State<DriverTripScreen> {
  
  bool _isSimulation = true; 
  
  bool _isTripActive = false;
  bool _isPausedForAction = false; 
  bool _isPassiveTracking = false;
  String _statusMessage = "Initializing...";
  String _currentStopName = "";
  
  Timer? _simTimer;
  StreamSubscription<Position>? _gpsStream; 
  
  int _pathIndex = 0;
  List<LatLng> _roadPath = [];
  List<Map> _pendingStops = [];
  LatLng _currentPos = const LatLng(18.5204, 73.8567);
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _initializeRoute();
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    _gpsStream?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _statusMessage = "GPS Disabled. Enable it.");
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _statusMessage = "Location Permission Denied");
        return;
      }
    }
  }

  // SETUP
  Future<void> _initializeRoute() async {
    List rawStops = widget.routeData['stops'] ?? [];
    if (rawStops.isEmpty) return;

    // Prepare Stops List
    List allStops = List.from(rawStops);

    // Set Start Position 
    var startNode = allStops[0];
    double startLat = double.parse(startNode['home_lat'].toString());
    double startLng = double.parse(startNode['home_lng'].toString());
    
    // Define Pending Stops 
    _pendingStops = List.from(allStops.sublist(1));

    setState(() {
      _currentPos = LatLng(startLat, startLng);
      _statusMessage = "At Depot. Ready to start.";
    });

    // Build Coordinates String for OSRM 
    String coordinates = "";
    for (int i = 0; i < allStops.length; i++) {
      var stop = allStops[i];
      coordinates += "${stop['home_lng']},${stop['home_lat']}";
      if (i < allStops.length - 1) coordinates += ";";
    }

    final url = "http://router.project-osrm.org/route/v1/driving/$coordinates?overview=full&geometries=geojson";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final geometry = data['routes'][0]['geometry']['coordinates'] as List;
        setState(() {
          _roadPath = geometry.map((p) => LatLng(p[1], p[0])).toList();
          _statusMessage = "Route Loaded. Ready to Start.";
        });
      }
    } catch (e) {
      setState(() => _statusMessage = "Route Error: $e");
    }
  }

  // MAIN ENGINE
  void _toggleTrip() {
    if (_isPausedForAction) return;

    setState(() => _isTripActive = !_isTripActive);

    if (_isTripActive) {
      setState(() => _statusMessage = "Driving to next stop...");
      if (_isSimulation) {
        _startSimulationEngine();
      } else {
        _startRealGpsEngine();
      }
    } else {
      setState(() => _statusMessage = "Trip Paused");
      _simTimer?.cancel();
      _gpsStream?.pause();
    }
  }

  void _startSimulationEngine() {
    _simTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_pathIndex >= _roadPath.length - 1) {
        _finishTrip();
        return;
      }
      setState(() {
        _pathIndex++; 
        _currentPos = _roadPath[_pathIndex];
      });
      _onLocationUpdated();
    });
  }

  void _startRealGpsEngine() {
    const settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5);
    _gpsStream = Geolocator.getPositionStream(locationSettings: settings).listen((Position position) {
      setState(() {
        _currentPos = LatLng(position.latitude, position.longitude);
      });
      _onLocationUpdated();
    });
  }

  // COMMON LOGIC
  void _onLocationUpdated() {
    _mapController.move(_currentPos, 16); 
    
    _checkForStopArrival(); 
    
    if (!_isSimulation || _pathIndex % 20 == 0) {
       _sendLocationUpdate(_isPassiveTracking ? "Passive" : "On Route");
    }
  }

  void _checkForStopArrival() {
    if (_pendingStops.isEmpty) {
      _finishTrip();
      return;
    }
    
    var nextStop = _pendingStops.first;
    LatLng stopLoc = LatLng(
      double.parse(nextStop['home_lat'].toString()), 
      double.parse(nextStop['home_lng'].toString())
    );
    
    // Threshold: 100 meters
    if (const Distance().as(LengthUnit.Meter, _currentPos, stopLoc) < 100) {
      _pauseEngine();
      
      String name = nextStop['name'];
      
      setState(() {
        _isTripActive = false;
        _isPausedForAction = true; 
        _currentStopName = name;
        _statusMessage = "Arrived at $name";
      });
    }
  }

  void _pauseEngine() {
    _simTimer?.cancel();
    _gpsStream?.pause();
  }

  void _confirmAction() {
    bool wasLastStop = _pendingStops.length == 1;

    setState(() {
      _pendingStops.removeAt(0); // Remove the stop we just visited
      _isPausedForAction = false;
    });
    
    if (wasLastStop) {
      _finishTrip();
    } else {
      setState(() {
        _isTripActive = true;
        _statusMessage = "Moving to next stop...";
      });
      if (_isSimulation) _startSimulationEngine(); else _gpsStream?.resume();
    }
  }

  void _finishTrip() {
    _pauseEngine();
    setState(() {
      _isPassiveTracking = true;
      _roadPath.clear(); 
      _statusMessage = "Trip Complete. Passive Tracking Active.";
    });
  }

  Future<void> _sendLocationUpdate(String status) async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    try {
      await http.post(
        Uri.parse("$baseUrl/update-location"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "van_id": widget.vanId, 
          "lat": _currentPos.latitude,
          "lng": _currentPos.longitude,
          "status": status
        }),
      );
    } catch (e) { print("Server Error: $e"); }
  }

  IconData _getIconForType(String? type, String name) {
    if (type == 'school' || name.contains("SCHOOL")) return Icons.school;
    if (type == 'depot' || name.contains("START")) return Icons.flag;
    return Icons.person_pin_circle;
  }
  
  Color _getColorForType(String? type, String name) {
    if (type == 'school' || name.contains("SCHOOL")) return Colors.purple;
    if (type == 'depot' || name.contains("START")) return Colors.green;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isPassiveTracking ? "TRACKING ACTIVE" : "ON ROUTE", style: GoogleFonts.oswald()), 
        backgroundColor: _isPassiveTracking ? Colors.grey : Colors.indigo,
        actions: [
          Switch(
            value: _isSimulation, 
            onChanged: (val) => setState(() => _isSimulation = val),
            activeColor: Colors.white,
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: _currentPos, initialZoom: 15.0),
              children: [
                TileLayer(urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png', subdomains: const ['a', 'b', 'c']),
                
                // Route Line
                if (!_isPassiveTracking) 
                  PolylineLayer(polylines: [Polyline(points: _roadPath, strokeWidth: 5.0, color: Colors.blue)]),
                
                // Stop Markers 
                if (!_isPassiveTracking) 
                  MarkerLayer(
                    markers: widget.routeData['stops'].map<Marker>((stop) {
                       return Marker(
                         point: LatLng(double.parse(stop['home_lat'].toString()), double.parse(stop['home_lng'].toString())), 
                         width: 60, 
                         height: 60, 
                         child: Icon(
                           _getIconForType(stop['type'], stop['name']), 
                           color: _getColorForType(stop['type'], stop['name']), 
                           size: 40
                         )
                       );
                    }).toList()
                  ),
                
                // Bus Marker
                MarkerLayer(markers: [Marker(point: _currentPos, width: 60, height: 60, child: const Icon(Icons.directions_bus, color: Colors.black, size: 40))]),
              ],
            ),
          ),
          
          // CONTROL PANEL 
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Column(
              children: [
                Text(_statusMessage, style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                const SizedBox(height: 15),
                
                if (_isPassiveTracking)
                   SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: Colors.grey), child: const Text("EXIT TRIP", style: TextStyle(color: Colors.white))))
                
                else if (_isPausedForAction)
                  SizedBox(
                    width: double.infinity, 
                    height: 50, 
                    child: ElevatedButton.icon(
                      onPressed: _confirmAction, 
                      icon: const Icon(Icons.check_circle), 
                      label: Text("CONFIRM ARRIVAL AT $_currentStopName"), 
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.black)
                    )
                  )
                
                else
                  SizedBox(
                    width: double.infinity, 
                    height: 50, 
                    child: ElevatedButton(
                      onPressed: _toggleTrip, 
                      style: ElevatedButton.styleFrom(backgroundColor: _isTripActive ? Colors.red : Colors.green), 
                      child: Text(_isTripActive ? "PAUSE TRIP" : "START TRIP", style: const TextStyle(color: Colors.white, fontSize: 18))
                    )
                  ),
              ],
            ),
          )
        ],
      ),
    );
  }
}