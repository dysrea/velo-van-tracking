import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';

class FleetTrackingScreen extends StatefulWidget {
  final String serverUrl;
  final String agencyId;

  const FleetTrackingScreen({super.key, required this.serverUrl, required this.agencyId});

  @override
  State<FleetTrackingScreen> createState() => _FleetTrackingScreenState();
}

class _FleetTrackingScreenState extends State<FleetTrackingScreen> {
  List _vans = [];
  Timer? _timer;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _fetchVans();
    // Refresh every 5 seconds
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) => _fetchVans());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchVans() async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    try {
      // Fetch vans to get location & tracking status
      final response = await http.get(Uri.parse("$baseUrl/vans?agency_id=${widget.agencyId}"));
      if (response.statusCode == 200) {
        if (mounted) setState(() => _vans = jsonDecode(response.body));
      }
    } catch (e) {
      print("Error fetching vans: $e");
    }
  }

  Future<void> _toggleTracking(String vanId) async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    try {
      await http.post(Uri.parse("$baseUrl/vans/toggle-tracking/$vanId"));
      _fetchVans(); // Refresh UI immediately
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tracking Status Updated"))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("LIVE FLEET TRACKING", style: GoogleFonts.oswald()), backgroundColor: const Color(0xFFFFC107)),
      body: Column(
        children: [
          // MAP VIEW 
          Expanded(
            flex: 2,
            child: FlutterMap(
              mapController: _mapController,
              options: const MapOptions(
                initialCenter: LatLng(18.5204, 73.8567), 
                initialZoom: 13.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.agency.fleet_tracker',
                  subdomains: const ['a', 'b', 'c'],
                ),
                MarkerLayer(
                  markers: _vans.map((van) {
                    double lat = van['current_lat'] ?? 18.5204;
                    double lng = van['current_lng'] ?? 73.8567;
                    
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 80,
                      height: 80,
                      child: Column(
                        children: [
                          const Icon(Icons.directions_bus, color: Colors.blue, size: 30),
                          Container(
                            padding: const EdgeInsets.all(2),
                            color: Colors.white,
                            child: Text(van['van_number'], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // VAN CONTROL PANEL 
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.white,
              child: ListView.builder(
                itemCount: _vans.length,
                itemBuilder: (ctx, i) {
                  final van = _vans[i];
                  bool isTrackAlways = van['track_always'] ?? false;
                  
                  return ListTile(
                    leading: Icon(Icons.directions_bus, color: isTrackAlways ? Colors.green : Colors.grey),
                    title: Text(van['van_number'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(isTrackAlways ? "Tracking: ALWAYS ON" : "Tracking: Trip Only"),
                    trailing: Switch(
                      value: isTrackAlways,
                      activeColor: Colors.green,
                      onChanged: (val) => _toggleTracking(van['id']),
                    ),
                  );
                },
              ),
            ),
          )
        ],
      ),
    );
  }
}