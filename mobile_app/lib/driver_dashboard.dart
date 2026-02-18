import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'driver_trip_screen.dart'; 
import 'main.dart'; 

class DriverDashboard extends StatefulWidget {
  final String serverUrl;
  final String driverId;
  final String driverName;

  const DriverDashboard({
    super.key, 
    required this.serverUrl, 
    required this.driverId,
    required this.driverName
  });

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  List _myRoutes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMyRoutes();
  }

  Future<void> _fetchMyRoutes() async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    try {
      final response = await http.get(Uri.parse("$baseUrl/routes?driver_id=${widget.driverId}"));
      
      if (response.statusCode == 200) {
        setState(() {
          _myRoutes = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text("HELLO, ${widget.driverName.toUpperCase()}", style: GoogleFonts.oswald()), 
        backgroundColor: const Color(0xFFFFC107),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout), 
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LoginScreen(serverUrl: widget.serverUrl)))
          )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _myRoutes.isEmpty 
          ? Center(child: Text("No trips assigned yet.", style: GoogleFonts.lato(fontSize: 18, color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _myRoutes.length,
              itemBuilder: (ctx, i) {
                final route = _myRoutes[i];
                final stops = route['stops'] as List;
                bool isMorning = route['trip_type'].toString().contains("Pickup");

                return Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // HEADER 
                        Row(
                          children: [
                            Icon(isMorning ? Icons.wb_sunny : Icons.nights_stay, color: isMorning ? Colors.orange : Colors.indigo, size: 30),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                route['trip_type'], 
                                style: GoogleFonts.oswald(fontSize: 18, fontWeight: FontWeight.bold)
                              ),
                            ),
                          ],
                        ),
                        
                        const Divider(height: 20),
                        
                        // DETAILS 
                        _infoRow(Icons.school, "${stops.where((s) => s['type'] != 'depot' && s['type'] != 'school').length} Students"),
                        _infoRow(Icons.route, "Optimized Route Ready"),
                        
                        const SizedBox(height: 15),

                        Row(
                          children: [
                            // PICKUP BUTTON
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => DriverTripScreen(
                                      serverUrl: widget.serverUrl,
                                      vanId: route['van_id'],
                                      routeData: route,
                                      isReturnTrip: false, 
                                    )
                                  ));
                                },
                                icon: const Icon(Icons.wb_sunny),
                                label: const Text("PICKUP"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            
                            const SizedBox(width: 10),

                            // RETURN BUTTON
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => DriverTripScreen(
                                      serverUrl: widget.serverUrl,
                                      vanId: route['van_id'],
                                      routeData: route,
                                      isReturnTrip: true, 
                                    )
                                  ));
                                },
                                icon: const Icon(Icons.nights_stay),
                                label: const Text("RETURN"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(text, style: GoogleFonts.lato(fontSize: 14)),
        ],
      ),
    );
  }
}