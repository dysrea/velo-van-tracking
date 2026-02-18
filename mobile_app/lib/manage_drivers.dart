import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';

class ManageDriversScreen extends StatefulWidget {
  final String serverUrl;
  final String agencyId;

  const ManageDriversScreen({super.key, required this.serverUrl, required this.agencyId});

  @override
  State<ManageDriversScreen> createState() => _ManageDriversScreenState();
}

class _ManageDriversScreenState extends State<ManageDriversScreen> {
  List _drivers = [];
  List _allVans = []; // Store ALL vans for lookup
  List _approvedVans = []; // For Dropdown (only approved ones)
  
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  String? _selectedVanId;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    
    try {
      final dRes = await http.get(Uri.parse("$baseUrl/drivers?agency_id=${widget.agencyId}"));
      final vRes = await http.get(Uri.parse("$baseUrl/vans?agency_id=${widget.agencyId}"));

      if (dRes.statusCode == 200 && vRes.statusCode == 200) {
        setState(() {
          _drivers = jsonDecode(dRes.body);
          _allVans = jsonDecode(vRes.body); // Keep complete list for lookup
          _approvedVans = _allVans.where((v) => v['status'] == 'approved').toList();
        });
      }
    } catch (e) {
      print("Error fetching data: $e");
    }
  }

  Future<void> _addDriver() async {
    if (_nameController.text.isEmpty || _emailController.text.isEmpty || _passController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields")));
      return;
    }

    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    try {
      await http.post(
        Uri.parse("$baseUrl/drivers/add"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": _nameController.text,
          "email": _emailController.text,
          "password": _passController.text,
          "agency_id": widget.agencyId,
          "assigned_van_id": _selectedVanId 
        }),
      );
      
      _nameController.clear();
      _emailController.clear();
      _passController.clear();
      setState(() => _selectedVanId = null);
      
      _fetchData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Driver Added Successfully")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _deleteDriver(String id) async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    try {
      await http.delete(Uri.parse("$baseUrl/drivers/delete/$id"));
      _fetchData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Driver Deleted")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error deleting: $e")));
    }
  }

  // TO FIND VAN NUMBER
  String _getVanNumber(String? vanId) {
    if (vanId == null || vanId.isEmpty) return "Unassigned";
    final van = _allVans.firstWhere(
      (v) => v['id'] == vanId, 
      orElse: () => null
    );
    return van != null ? van['van_number'] : "Unknown ID";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("MANAGE DRIVERS", style: GoogleFonts.oswald()),
        backgroundColor: const Color(0xFFFFC107),
      ),
      body: Column(
        children: [
          // ADD FORM
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Name", prefixIcon: Icon(Icons.person))),
                const SizedBox(height: 10),
                TextField(controller: _emailController, decoration: const InputDecoration(labelText: "Email", prefixIcon: Icon(Icons.email))),
                const SizedBox(height: 10),
                TextField(controller: _passController, obscureText: true, decoration: const InputDecoration(labelText: "Password", prefixIcon: Icon(Icons.lock))),
                const SizedBox(height: 10),
                
                DropdownButtonFormField<String>(
                  value: _selectedVanId,
                  hint: const Text("Assign Van (Optional)"),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.directions_bus), filled: true, fillColor: Colors.white),
                  items: _approvedVans.map<DropdownMenuItem<String>>((v) {
                    return DropdownMenuItem(value: v['id'], child: Text(v['van_number']));
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedVanId = val),
                ),
                
                const SizedBox(height: 15),
                ElevatedButton(
                  onPressed: _addDriver, 
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white),
                  child: const Text("ADD DRIVER")
                )
              ],
            ),
          ),
          
          const Divider(height: 1),

          // LIST
          Expanded(
            child: _drivers.isEmpty 
              ? Center(child: Text("No drivers added.", style: GoogleFonts.lato(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: _drivers.length,
                  itemBuilder: (ctx, i) {
                    final driver = _drivers[i];
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF1A237E),
                          child: Text(driver['name'][0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(driver['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Email: ${driver['email']}\nAssigned Van: ${_getVanNumber(driver['assigned_van_id'])}"),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteDriver(driver['id']),
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