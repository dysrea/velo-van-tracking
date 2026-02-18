import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';

class ManageVansScreen extends StatefulWidget {
  final String serverUrl;
  final String agencyId;

  const ManageVansScreen({super.key, required this.serverUrl, required this.agencyId});

  @override
  State<ManageVansScreen> createState() => _ManageVansScreenState();
}

class _ManageVansScreenState extends State<ManageVansScreen> {
  List _vans = [];
  final _vanNumberController = TextEditingController();
  final _capacityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchVans();
  }

  Future<void> _fetchVans() async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    final res = await http.get(Uri.parse("$baseUrl/vans?agency_id=${widget.agencyId}"));
    if (res.statusCode == 200) setState(() => _vans = jsonDecode(res.body));
  }

  Future<void> _addVan() async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    await http.post(
      Uri.parse("$baseUrl/vans/add"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "van_number": _vanNumberController.text,
        "capacity": int.tryParse(_capacityController.text) ?? 10,
        "agency_id": widget.agencyId // Linking by ID
      }),
    );
    _vanNumberController.clear();
    _fetchVans();
  }

  Future<void> _deleteVan(String id) async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    await http.delete(Uri.parse("$baseUrl/vans/delete/$id"));
    _fetchVans();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("MANAGE VANS", style: GoogleFonts.oswald())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _vanNumberController, decoration: const InputDecoration(labelText: "Van Number"))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _capacityController, decoration: const InputDecoration(labelText: "Capacity"))),
                IconButton(icon: const Icon(Icons.add_circle, size: 40, color: Colors.green), onPressed: _addVan)
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _vans.length,
              itemBuilder: (ctx, i) => ListTile(
                title: Text(_vans[i]['van_number']),
                subtitle: Text("Status: ${_vans[i]['status']}"),
                trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteVan(_vans[i]['id'])),
              ),
            ),
          )
        ],
      ),
    );
  }
}