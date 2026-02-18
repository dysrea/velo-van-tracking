import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';

class ManageStudentsScreen extends StatefulWidget {
  final String serverUrl;
  final String agencyId;

  const ManageStudentsScreen({super.key, required this.serverUrl, required this.agencyId});

  @override
  State<ManageStudentsScreen> createState() => _ManageStudentsScreenState();
}

class _ManageStudentsScreenState extends State<ManageStudentsScreen> {
  List _students = [];
  List _approvedVans = [];
  
  final _nameController = TextEditingController();
  String? _selectedVanId;
  String _selectedSchedule = "Both"; 

  final double _mockHomeLat = 18.5204;
  final double _mockHomeLng = 73.8567;
  final double _mockSchoolLat = 18.5600;
  final double _mockSchoolLng = 73.9000;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    try {
      final sRes = await http.get(Uri.parse("$baseUrl/students?agency_id=${widget.agencyId}"));
      final vRes = await http.get(Uri.parse("$baseUrl/vans?agency_id=${widget.agencyId}"));

      if (sRes.statusCode == 200 && vRes.statusCode == 200) {
        setState(() {
          _students = jsonDecode(sRes.body);
          final allVans = jsonDecode(vRes.body);
          _approvedVans = allVans.where((v) => v['status'] == 'approved').toList();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error loading data: $e")));
    }
  }

  Future<void> _addStudent() async {
    if (_nameController.text.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a name")));
       return;
    }

    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    
    try {
      await http.post(
        Uri.parse("$baseUrl/students/add"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": _nameController.text,
          "home_lat": _mockHomeLat,
          "home_lng": _mockHomeLng,
          "school_lat": _mockSchoolLat, 
          "school_lng": _mockSchoolLng, 
          "agency_id": widget.agencyId,
          "assigned_van_id": _selectedVanId,
          "schedule": _selectedSchedule,     
        }),
      );
      
      _nameController.clear();
      setState(() {
        _selectedVanId = null;
        _selectedSchedule = "Both";
      });
      _fetchData(); // Refresh list
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Student Registered!")));

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error adding student: $e")));
    }
  }

  Future<void> _deleteStudent(String id) async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    await http.delete(Uri.parse("$baseUrl/students/delete/$id"));
    _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text("MANAGE STUDENTS", style: GoogleFonts.oswald()), 
        backgroundColor: const Color(0xFFFFC107)
      ),
      body: Column(
        children: [
          // REGISTRATION FORM
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController, 
                  decoration: const InputDecoration(labelText: "Student Name", prefixIcon: Icon(Icons.person))
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _selectedVanId,
                  hint: const Text("Assign Approved Van"),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.directions_bus), filled: true, fillColor: Colors.white),
                  items: _approvedVans.isEmpty 
                    ? [] 
                    : _approvedVans.map<DropdownMenuItem<String>>((v) {
                        return DropdownMenuItem(value: v['id'], child: Text(v['van_number']));
                      }).toList(),
                  onChanged: (val) => setState(() => _selectedVanId = val),
                ),
                if (_approvedVans.isEmpty)
                   const Padding(
                     padding: EdgeInsets.only(top:5, left: 10),
                     child: Text("No approved vans available.", style: TextStyle(color: Colors.red, fontSize: 12)),
                   ),
                
                const SizedBox(height: 10),

                // Schedule Dropdown
                DropdownButtonFormField<String>(
                  value: _selectedSchedule,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.schedule), labelText: "Transport Schedule", filled: true, fillColor: Colors.white),
                  items: const [
                    DropdownMenuItem(value: "Both", child: Text("Both Ways (Pick & Drop)")),
                    DropdownMenuItem(value: "Morning", child: Text("Morning Only (Pickup)")),
                    DropdownMenuItem(value: "Evening", child: Text("Evening Only (Drop)")),
                  ],
                  onChanged: (val) => setState(() => _selectedSchedule = val!),
                ),
                
                const SizedBox(height: 15),
                ElevatedButton(
                  onPressed: _addStudent, 
                  child: const Text("REGISTER STUDENT")
                )
              ],
            ),
          ),
          
          const Divider(height: 1),

          // STUDENTS LIST
          Expanded(
            child: _students.isEmpty 
              ? Center(child: Text("No students registered yet.", style: GoogleFonts.lato(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: _students.length,
                  itemBuilder: (ctx, i) {
                    final student = _students[i];
                    
                    final van = _approvedVans.firstWhere(
                      (v) => v['id'] == student['assigned_van_id'], 
                      orElse: () => {'van_number': 'Unassigned'}
                    );

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF1A237E), 
                          child: Text(student['name'][0].toUpperCase(), style: const TextStyle(color: Colors.white))
                        ),
                        title: Text(student['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(children: [
                              const Icon(Icons.directions_bus, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text("Van: ${van['van_number']}"),
                            ]),
                            Row(children: [
                              const Icon(Icons.schedule, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text("Schedule: ${student['schedule']}"),
                            ]),
                            Row(children: [
                              const Icon(Icons.location_on, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text("Home: ${student['home_lat']}, ${student['home_lng']}", style: const TextStyle(fontSize: 10)),
                            ]),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red), 
                          onPressed: () => _deleteStudent(student['id'])
                        ),
                      ),
                    );
                  },
                ),
          )
        ],
      ),
    );
  }
}