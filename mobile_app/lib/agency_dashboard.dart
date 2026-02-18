import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'main.dart'; 

class AgencyDashboard extends StatefulWidget {
  final String serverUrl;
  final String agencyId;

  const AgencyDashboard({super.key, required this.serverUrl, required this.agencyId});

  @override
  State<AgencyDashboard> createState() => _AgencyDashboardState();
}

class _AgencyDashboardState extends State<AgencyDashboard> {
  int _selectedIndex = 0;
  bool _isLoading = true;
  Timer? _refreshTimer;
  
  // Data Lists
  List _vans = [];
  List _drivers = [];
  List _students = [];
  List _routes = []; 

  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _fetchData();
    // Auto-refresh map data every 3 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_selectedIndex == 0) _fetchLocationsOnly();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // DATA FETCHING 
  Future<void> _fetchData() async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    try {
      final vRes = await http.get(Uri.parse("$baseUrl/vans/${widget.agencyId}"));
      final sRes = await http.get(Uri.parse("$baseUrl/students/${widget.agencyId}"));
      final dRes = await http.get(Uri.parse("$baseUrl/drivers/${widget.agencyId}")); 
      final rRes = await http.get(Uri.parse("$baseUrl/routes?agency_id=${widget.agencyId}")); 

      if (vRes.statusCode == 200) {
        if (mounted) {
          setState(() {
            _vans = jsonDecode(vRes.body);
            _students = jsonDecode(sRes.body);
            try { _drivers = jsonDecode(dRes.body); } catch (_) { _drivers = []; }
            try { _routes = jsonDecode(rRes.body); } catch (_) { _routes = []; } 
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print("Error fetching data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchLocationsOnly() async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    try {
      final response = await http.get(Uri.parse("$baseUrl/vans/${widget.agencyId}"));
      if (response.statusCode == 200 && mounted) {
        setState(() => _vans = jsonDecode(response.body));
      }
    } catch (e) { print("Sync Error: $e"); }
  }

  // ADD / EDIT / DELETE 
  Future<void> _saveEntity(String endpoint, Map<String, dynamic> data, {String? updateId}) async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    try {
      if (updateId != null) {
        await http.put(Uri.parse("$baseUrl/$endpoint/update/$updateId"), headers: {"Content-Type": "application/json"}, body: jsonEncode(data));
      } else {
        await http.post(Uri.parse("$baseUrl/$endpoint/add"), headers: {"Content-Type": "application/json"}, body: jsonEncode(data));
      }
      _fetchData(); 
      if (mounted) Navigator.pop(context);
    } catch (e) { print("Save Error: $e"); }
  }

  Future<void> _deleteEntity(String endpoint, String id) async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    await http.delete(Uri.parse("$baseUrl/$endpoint/delete/$id"));
    _fetchData();
  }

  Future<void> _createRoute(String vanId, List<String> studentIds) async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    var van = _vans.firstWhere((v) => v['id'] == vanId);
    
    if (van['assigned_driver_id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: This van has no driver!")));
      return;
    }

    Map<String, dynamic> payload = {
      "agency_id": widget.agencyId,
      "van_id": vanId,
      "driver_id": van['assigned_driver_id'],
      "trip_type": "Pickup (Home -> School)",
      "student_ids": studentIds 
    };

    final res = await http.post(Uri.parse("$baseUrl/routes/create"), 
      headers: {"Content-Type": "application/json"}, body: jsonEncode(payload));
      
    if (res.statusCode == 200) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Route Created Successfully!")));
       _fetchData(); 
    } else {
       final err = jsonDecode(res.body);
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed: ${err['detail']}")));
    }
  }

  Future<void> _approveEntity(String type, String id) async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    await http.post(Uri.parse("$baseUrl/approve/$type/$id"));
    _fetchData();
  }

  // MAIN UI 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedIndex == 0 ? "LIVE MAP" : (_selectedIndex == 1 ? "FLEET MANAGER" : "ROUTE PLANNER"), style: GoogleFonts.oswald()),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData),
          IconButton(
            icon: const Icon(Icons.logout), 
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LoginScreen(serverUrl: widget.serverUrl)))
          )
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : IndexedStack(
              index: _selectedIndex,
              children: [
                _buildLiveMap(),        
                _buildFleetManager(),   
                _buildRoutePlanner(), 
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: const Color(0xFF1A237E),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "Live Map"),
          BottomNavigationBarItem(icon: Icon(Icons.directions_bus), label: "Fleet"),
          BottomNavigationBarItem(icon: Icon(Icons.alt_route), label: "Routes"),
        ],
      ),
    );
  }

  // LIVE MAP 
  Widget _buildLiveMap() {
    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(initialCenter: LatLng(18.5204, 73.8567), initialZoom: 12.0),
      children: [
        TileLayer(urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png', subdomains: const ['a', 'b', 'c']),
        MarkerLayer(
          markers: _vans.map<Marker>((van) {
            double lat = van['current_lat'] ?? 0.0;
            double lng = van['current_lng'] ?? 0.0;
            if (lat == 0) return const Marker(point: LatLng(0,0), child: SizedBox());
            return Marker(
              point: LatLng(lat, lng), width: 80, height: 80,
              child: Column(children: [
                Container(color: Colors.white, padding: const EdgeInsets.all(2), child: Text(van['van_number'], style: const TextStyle(fontSize: 10))),
                Icon(Icons.directions_bus, color: van['last_active'] == 'On Route' ? Colors.green : Colors.grey, size: 40)
              ]),
            );
          }).toList(),
        ),
      ],
    );
  }

  // FLEET MANAGER 
  Widget _buildFleetManager() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            color: Colors.indigo.shade50,
            child: const TabBar(
              labelColor: Colors.indigo,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.indigo,
              tabs: [Tab(text: "Students"), Tab(text: "Drivers"), Tab(text: "Vans")],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildList(_students, "students", "name", Icons.person, (ctx, [s]) => _showStudentDialog(ctx, s)),
                _buildList(_drivers, "drivers", "name", Icons.airline_seat_recline_normal, (ctx, [d]) => _showDriverDialog(ctx, d)),
                _buildVanList(), 
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List data, String endpoint, String titleKey, IconData icon, Function(BuildContext, [Map?]) onEditOrAdd) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => onEditOrAdd(context),
        backgroundColor: const Color(0xFF1A237E),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: ListView.builder(
        itemCount: data.length,
        itemBuilder: (ctx, i) {
          final item = data[i];
          final status = item['status'] ?? 'pending';
          final isPending = status == 'pending';

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            color: isPending ? Colors.orange.shade50 : Colors.white,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isPending ? Colors.orange : Colors.indigo, 
                child: Icon(icon, color: Colors.white)
              ),
              title: Text(item[titleKey], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("Status: ${status.toUpperCase()}", style: TextStyle(color: isPending ? Colors.orange : Colors.green)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => onEditOrAdd(context, item)),
                  if (isPending) IconButton(icon: const Icon(Icons.check_circle, color: Colors.green), onPressed: () => _approveEntity(endpoint == "vans" ? "van" : "driver", item['id'])),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteEntity(endpoint, item['id'])),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVanList() {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showVanDialog(context),
        backgroundColor: const Color(0xFF1A237E),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: ListView.builder(
        itemCount: _vans.length,
        itemBuilder: (ctx, i) {
          final van = _vans[i];
          final status = van['status'] ?? 'pending';
          final isPending = status == 'pending';
          final driverId = van['assigned_driver_id'];
          final driverName = driverId != null ? _drivers.firstWhere((d) => d['id'] == driverId, orElse: () => {'name': 'Unknown'})['name'] : "No Driver";

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            color: isPending ? Colors.orange.shade50 : Colors.white,
            child: ListTile(
              leading: const Icon(Icons.directions_bus, color: Colors.indigo, size: 30),
              title: Text("${van['van_number']} (${van['capacity']} Seats)", style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("Status: ${status.toUpperCase()}\nDriver: $driverName"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showVanDialog(context, van)),
                  if (isPending) IconButton(icon: const Icon(Icons.check_circle, color: Colors.green), onPressed: () => _approveEntity("van", van['id'])),
                  if (!isPending) IconButton(icon: const Icon(Icons.link, color: Colors.blue), onPressed: () => _showAssignDriverDialog(context, van)),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteEntity("vans", van['id'])),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ROUTE PLANNER 
  Widget _buildRoutePlanner() {
    String? selectedVan;
    List<String> selectedStudents = [];
    
    final availableVans = _vans.where((v) => v['status'] == 'approved' && v['assigned_driver_id'] != null).toList();
    
    return Column(
      children: [
        Expanded(
          flex: 4,
          child: StatefulBuilder(
            builder: (context, setStateLocal) {
              return Container(
                padding: const EdgeInsets.all(16.0),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("1. CREATE NEW ROUTE", style: GoogleFonts.oswald(fontSize: 18, color: Colors.indigo)),
                    const SizedBox(height: 10),
                    if (availableVans.isEmpty)
                      const Text("No ready vans (Approved + Driver Assigned) available.", style: TextStyle(color: Colors.red))
                    else
                      DropdownButtonFormField(
                        decoration: const InputDecoration(labelText: "Select Van", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                        items: availableVans.map<DropdownMenuItem<String>>((v) => DropdownMenuItem(value: v['id'].toString(), child: Text(v['van_number']))).toList(),
                        onChanged: (val) => setStateLocal(() => selectedVan = val),
                      ),
                    const SizedBox(height: 10),
                    const Text("Select Students:", style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                        child: ListView(
                          children: _students.map((s) {
                            final isSelected = selectedStudents.contains(s['id']);
                            return CheckboxListTile(
                              dense: true,
                              title: Text(s['name']),
                              subtitle: Text("Lat: ${s['home_lat']}, Lng: ${s['home_lng']}"),
                              value: isSelected,
                              onChanged: (bool? checked) {
                                setStateLocal(() {
                                  if (checked == true) selectedStudents.add(s['id']); else selectedStudents.remove(s['id']);
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        onPressed: () {
                          if (selectedVan != null && selectedStudents.isNotEmpty) {
                            _createRoute(selectedVan!, selectedStudents);
                            setStateLocal(() => selectedStudents.clear()); 
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select a Van and at least 1 Student")));
                          }
                        },
                        child: const Text("GENERATE OPTIMIZED ROUTE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        const Divider(height: 5, thickness: 5, color: Colors.grey),

        Expanded(
          flex: 3,
          child: Container(
            color: Colors.grey.shade50,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text("2. GENERATED ROUTES (${_routes.length})", style: GoogleFonts.oswald(fontSize: 18, color: Colors.black54)),
                ),
                Expanded(
                  child: _routes.isEmpty 
                    ? const Center(child: Text("No routes generated yet."))
                    : ListView.builder(
                        itemCount: _routes.length,
                        itemBuilder: (ctx, i) {
                          final route = _routes[i];
                          final stops = (route['stops'] as List? ?? []);
                          // Get Van Name
                          final van = _vans.firstWhere((v) => v['id'] == route['van_id'], orElse: () => {'van_number': 'Unknown'});
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            child: ExpansionTile(
                              leading: const Icon(Icons.alt_route, color: Colors.blue),
                              title: Text("Van: ${van['van_number']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text("${route['trip_type']} - ${stops.length} Stops"),
                              children: stops.map<Widget>((stop) {
                                final isDepot = stop['type'] == 'depot' || stop['name'].toString().contains("START");
                                return ListTile(
                                  dense: true,
                                  leading: Icon(isDepot ? Icons.flag : Icons.person, color: isDepot ? Colors.red : Colors.grey, size: 20),
                                  title: Text(stop['name']),
                                  trailing: Text("${stop['home_lat']}, ${stop['home_lng']}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                );
                              }).toList(),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteEntity("routes", route['id']),
                              ),
                            ),
                          );
                        },
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // DIALOGS (ADD + EDIT)
  void _showStudentDialog(BuildContext context, [Map? student]) {
    final isEdit = student != null;
    final nameCtrl = TextEditingController(text: isEdit ? student['name'] : "");
    final hLatCtrl = TextEditingController(text: isEdit ? student['home_lat'].toString() : "");
    final hLngCtrl = TextEditingController(text: isEdit ? student['home_lng'].toString() : "");
    final sLatCtrl = TextEditingController(text: isEdit ? student['school_lat']?.toString() ?? "" : "");
    final sLngCtrl = TextEditingController(text: isEdit ? student['school_lng']?.toString() ?? "" : "");
    String schedule = isEdit ? student['schedule'] : "Both";

    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(isEdit ? "Edit Student" : "Add Student"),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Name")),
            const SizedBox(height: 10),
            TextField(controller: hLatCtrl, decoration: const InputDecoration(labelText: "Home Latitude")),
            TextField(controller: hLngCtrl, decoration: const InputDecoration(labelText: "Home Longitude")),
            const SizedBox(height: 10),
            TextField(controller: sLatCtrl, decoration: const InputDecoration(labelText: "School Latitude")),
            TextField(controller: sLngCtrl, decoration: const InputDecoration(labelText: "School Longitude")),
            const SizedBox(height: 10),
            DropdownButtonFormField(
              value: schedule,
              items: ["Morning", "Evening", "Both"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (val) => setState(() => schedule = val.toString()),
              decoration: const InputDecoration(labelText: "Schedule"),
            )
          ]),
        ),
        actions: [
          TextButton(onPressed: () {
            _saveEntity("students", {
              "name": nameCtrl.text,
              "home_lat": double.tryParse(hLatCtrl.text) ?? 0.0,
              "home_lng": double.tryParse(hLngCtrl.text) ?? 0.0,
              "school_lat": double.tryParse(sLatCtrl.text) ?? 0.0,
              "school_lng": double.tryParse(sLngCtrl.text) ?? 0.0,
              "agency_id": widget.agencyId,
              "schedule": schedule
            }, updateId: isEdit ? student['id'] : null);
          }, child: const Text("SAVE"))
        ],
      ),
    ));
  }

  void _showDriverDialog(BuildContext context, [Map? driver]) {
    final isEdit = driver != null;
    final nameCtrl = TextEditingController(text: isEdit ? driver['name'] : "");
    final emailCtrl = TextEditingController(text: isEdit ? driver['email'] : "");
    final passCtrl = TextEditingController(text: isEdit ? driver['password'] : "");

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(isEdit ? "Edit Driver" : "Add Driver"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Name")),
        TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: "Email")),
        TextField(controller: passCtrl, decoration: const InputDecoration(labelText: "Password")),
      ]),
      actions: [
        TextButton(onPressed: () {
          _saveEntity("drivers", {
            "name": nameCtrl.text, "email": emailCtrl.text, "password": passCtrl.text, "agency_id": widget.agencyId
          }, updateId: isEdit ? driver['id'] : null);
        }, child: const Text("SAVE"))
      ],
    ));
  }

  void _showVanDialog(BuildContext context, [Map? van]) {
    final isEdit = van != null;
    final numCtrl = TextEditingController(text: isEdit ? van['van_number'] : "");
    final capCtrl = TextEditingController(text: isEdit ? van['capacity'].toString() : "");
    final latCtrl = TextEditingController(text: isEdit ? (van['start_lat']?.toString() ?? "18.5204") : "18.5204");
    final lngCtrl = TextEditingController(text: isEdit ? (van['start_lng']?.toString() ?? "73.8567") : "73.8567");

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(isEdit ? "Edit Van" : "Add Van"),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: numCtrl, decoration: const InputDecoration(labelText: "Van Number")),
          TextField(controller: capCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Capacity")),
          const SizedBox(height: 10),
          const Text("Start Location (Depot/Home):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          TextField(controller: latCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Start Latitude")),
          TextField(controller: lngCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Start Longitude")),
        ]),
      ),
      actions: [
        TextButton(onPressed: () {
          _saveEntity("vans", {
            "van_number": numCtrl.text, 
            "capacity": int.tryParse(capCtrl.text) ?? 10, 
            "start_lat": double.tryParse(latCtrl.text) ?? 18.5204,
            "start_lng": double.tryParse(lngCtrl.text) ?? 73.8567,
            "agency_id": widget.agencyId
          }, updateId: isEdit ? van['id'] : null);
        }, child: const Text("SAVE"))
      ],
    ));
  }
  
  void _showAssignDriverDialog(BuildContext context, Map van) {
    String? selectedDriverId;
    List availableDrivers = _drivers.where((d) => 
      d['status'] == 'approved' && (d['assigned_van_id'] == null || d['assigned_van_id'] == van['id'])
    ).toList();

    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (context, setStateLocal) {
        return AlertDialog(
          title: Text("Assign Driver to ${van['van_number']}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (availableDrivers.isEmpty)
                const Text("No available approved drivers found!", style: TextStyle(color: Colors.red))
              else
                DropdownButtonFormField(
                  decoration: const InputDecoration(labelText: "Select Driver", border: OutlineInputBorder()),
                  items: availableDrivers.map<DropdownMenuItem<String>>((d) {
                    return DropdownMenuItem(value: d['id'].toString(), child: Text(d['name']));
                  }).toList(),
                  onChanged: (val) => setStateLocal(() => selectedDriverId = val),
                )
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (selectedDriverId != null) {
                  final baseUrl = widget.serverUrl.replaceAll('/login', '');
                  await http.post(
                    Uri.parse("$baseUrl/vans/assign-driver"),
                    headers: {"Content-Type": "application/json"},
                    body: jsonEncode({
                      "van_id": van['id'],
                      "driver_id": selectedDriverId
                    })
                  );
                  _fetchData(); 
                  Navigator.pop(context);
                }
              }, 
              child: const Text("ASSIGN")
            )
          ],
        );
      }
    ));
  }
}