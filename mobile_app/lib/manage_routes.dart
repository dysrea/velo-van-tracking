import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ManageRoutesScreen extends StatefulWidget {
  final String serverUrl;
  final String agencyId;

  const ManageRoutesScreen({super.key, required this.serverUrl, required this.agencyId});

  @override
  State<ManageRoutesScreen> createState() => _ManageRoutesScreenState();
}

class _ManageRoutesScreenState extends State<ManageRoutesScreen> {
  List _routes = [];
  List _approvedVans = [];
  List _allStudents = []; 
  
  String? _selectedVanId;
  String _selectedTripType = "Pickup (Home -> School)";
  List<String> _selectedStudentIds = []; 
  bool _isLoading = false;

  final List<String> _tripTypes = [
    "Pickup (Home -> School)",
    "Return (School -> Home)",
    "Coaching Pickup (Home -> Coaching)",
    "Coaching Return (Coaching -> Home)"
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    try {
      final rRes = await http.get(Uri.parse("$baseUrl/routes?agency_id=${widget.agencyId}"));
      final vRes = await http.get(Uri.parse("$baseUrl/vans/${widget.agencyId}"));
      final sRes = await http.get(Uri.parse("$baseUrl/students/${widget.agencyId}"));

      if (mounted) {
        setState(() {
          if (rRes.statusCode == 200) _routes = jsonDecode(rRes.body);
          if (vRes.statusCode == 200) {
             final allVans = jsonDecode(vRes.body);
             _approvedVans = allVans.where((v) => v['status'] == 'approved').toList();
          }
          if (sRes.statusCode == 200) _allStudents = jsonDecode(sRes.body);
        });
      }
    } catch (e) {
      print("Fetch Error: $e");
    }
  }

  Future<void> _createRoute() async {
    if (_selectedVanId == null || _selectedStudentIds.isEmpty) return;

    setState(() => _isLoading = true);
    final baseUrl = widget.serverUrl.replaceAll('/login', '');

    try {
      final van = _approvedVans.firstWhere((v) => v['id'] == _selectedVanId);
      final response = await http.post(
        Uri.parse("$baseUrl/routes/create"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "agency_id": widget.agencyId,
          "van_id": _selectedVanId,
          "driver_id": van['assigned_driver_id'], 
          "trip_type": _selectedTripType,
          "student_ids": _selectedStudentIds
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Route Optimized & Created!"), backgroundColor: Colors.green));
        await _fetchData(); 
        setState(() => _selectedStudentIds.clear()); 
      } else {
        final err = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed: ${err['detail']}"), backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  Future<void> _deleteRoute(String id) async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    await http.delete(Uri.parse("$baseUrl/routes/delete/$id"));
    _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    int vanCapacity = 0;
    bool driverReady = false;
    
    if (_selectedVanId != null) {
      final van = _approvedVans.firstWhere((v) => v['id'] == _selectedVanId, orElse: () => null);
      if (van != null) {
        vanCapacity = van['capacity'] ?? 0;
        driverReady = (van['assigned_driver_id'] != null);
      }
    }

    bool isOverCapacity = _selectedStudentIds.length > vanCapacity;
    bool canGenerate = _selectedVanId != null && driverReady && !isOverCapacity && _selectedStudentIds.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(title: Text("ROUTE PLANNER", style: GoogleFonts.oswald()), backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedVanId,
                  hint: const Text("Select Approved Van"),
                  isExpanded: true,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.directions_bus), border: OutlineInputBorder()),
                  items: _approvedVans.map<DropdownMenuItem<String>>((v) {
                    return DropdownMenuItem(value: v['id'], child: Text("${v['van_number']} (Cap: ${v['capacity']})"));
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedVanId = val),
                ),
                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  value: _selectedTripType,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.alt_route), border: OutlineInputBorder()),
                  items: _tripTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (val) => setState(() => _selectedTripType = val!),
                ),
                
                if (_selectedVanId != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                       Text(driverReady ? "Driver: Ready" : "Driver: MISSING", style: TextStyle(color: driverReady ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                       Text("Selected: ${_selectedStudentIds.length} / $vanCapacity", style: TextStyle(color: isOverCapacity ? Colors.red : Colors.black, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],

                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canGenerate ? _createRoute : null,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("GENERATE ROUTE"),
                  ),
                )
              ],
            ),
          ),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.indigo.shade50,
            child: Text("1. Select Students for Route", style: GoogleFonts.oswald(color: Colors.indigo)),
          ),
          
          Expanded(
            flex: 1,
            child: _selectedVanId == null 
              ? Center(child: Text("Select a Van first", style: GoogleFonts.oswald(color: Colors.grey)))
              : ListView.builder(
                  itemCount: _allStudents.length,
                  itemBuilder: (ctx, i) {
                    final s = _allStudents[i];
                    final isChecked = _selectedStudentIds.contains(s['id']);
                    
                    final currentAssignedVan = s['assigned_van_id'];
                    final isTaken = currentAssignedVan != null && currentAssignedVan != _selectedVanId;

                    return CheckboxListTile(
                      title: Text(
                        s['name'], 
                        style: TextStyle(
                          color: isTaken ? Colors.grey : Colors.black,
                          decoration: isTaken ? TextDecoration.lineThrough : null
                        )
                      ),
                      subtitle: Text(
                        isTaken 
                          ? "Already assigned to another Van" 
                          : "Home: ${s['home_lat']}, ${s['home_lng']}",
                        style: TextStyle(color: isTaken ? Colors.red : Colors.grey),
                      ),
                      value: isChecked,
                      activeColor: const Color(0xFF1A237E),
                      enabled: !isTaken,
                      onChanged: isTaken ? null : (bool? val) {
                        setState(() {
                          if (val == true) _selectedStudentIds.add(s['id']);
                          else _selectedStudentIds.remove(s['id']);
                        });
                      },
                    );
                  },
                ),
          ),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.orange.shade50,
            child: Text("2. Generated Routes", style: GoogleFonts.oswald(color: Colors.deepOrange)),
          ),
          
          Expanded(
            flex: 1,
            child: _routes.isEmpty 
              ? const Center(child: Text("No Routes Generated Yet"))
              : ListView.builder(
                  itemCount: _routes.length,
                  itemBuilder: (ctx, i) {
                    final route = _routes[i];
                    final stops = (route['stops'] as List? ?? []);
                    
                    final totalStops = stops.length;
                    final studentCount = totalStops > 2 ? totalStops - 2 : 0;
                    
                    final van = _approvedVans.firstWhere((v) => v['id'] == route['van_id'], orElse: () => {'van_number': 'Unknown'});
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ExpansionTile(
                        leading: const Icon(Icons.alt_route, color: Colors.blue),
                        title: Text("Van: ${van['van_number']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                        
                        subtitle: Text("${route['trip_type']} • $studentCount Students"),
                        
                        children: stops.map<Widget>((stop) {
                          final type = stop['type']?.toString().toLowerCase() ?? '';
                          final name = stop['name']?.toString().toLowerCase() ?? '';
                          final isDepot = type == 'depot' || name.contains("start");
                          final isSchool = type == 'school' || name.contains("school");
                          
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isDepot ? Icons.flag : (isSchool ? Icons.school : Icons.person), 
                              color: isDepot ? Colors.green : (isSchool ? Colors.purple : Colors.grey), 
                              size: 20
                            ),
                            title: Text(stop['name']),
                            trailing: Text("${stop['home_lat']}, ${stop['home_lng']}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          );
                        }).toList(),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteRoute(route['id']),
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}